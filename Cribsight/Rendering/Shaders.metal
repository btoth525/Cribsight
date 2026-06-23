#include <metal_stdlib>
using namespace metal;

// Must match DewarpUniformsData in DewarpUniforms.swift (all 4-byte scalars).
struct DewarpUniforms {
    int   mode;        // 0 = passthrough, 1 = panorama, 2 = perspective
    int   rotation;    // 0,1,2,3 → 0/90/180/270°
    int   flip;        // horizontal flip
    int   pad0;

    float centerX;
    float centerY;
    float radius;
    float lensFOV;     // radians

    float outputFOV;   // radians
    float pan;
    float tilt;
    float zoom;

    float panoUp;      // radians
    float panoDown;    // radians
    float roll;
    float texAspect;   // source W/H

    float viewAspect;  // output W/H
    float pad1;
    float pad2;
    float pad3;
};

struct VSOut {
    float4 position [[position]];
    float2 uv;
};

// Full-screen triangle; uv has origin at top-left to match the video texture.
vertex VSOut vsFullscreen(uint vid [[vertex_id]]) {
    float2 pos[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    VSOut out;
    float2 p = pos[vid];
    out.position = float4(p, 0.0, 1.0);
    out.uv = float2((p.x + 1.0) * 0.5, (1.0 - p.y) * 0.5);
    return out;
}

static float3 yuvToRGB(float y, float2 cbcr) {
    // BT.709, video range.
    float Y  = (y - 0.0627451) * 1.164383;
    float Cb = (cbcr.x - 0.5) * 1.138393;
    float Cr = (cbcr.y - 0.5) * 1.138393;
    float r = Y + 1.792741 * Cr;
    float g = Y - 0.213249 * Cb - 0.532909 * Cr;
    float b = Y + 2.112402 * Cb;
    return clamp(float3(r, g, b), 0.0, 1.0);
}

static float2 rotateUV(float2 uv, int rotation, int flip) {
    float2 r = uv;
    if (rotation == 1)      { r = float2(uv.y, 1.0 - uv.x); }         // 90°
    else if (rotation == 2) { r = float2(1.0 - uv.x, 1.0 - uv.y); }   // 180°
    else if (rotation == 3) { r = float2(1.0 - uv.y, uv.x); }         // 270°
    if (flip == 1) { r.x = 1.0 - r.x; }
    return r;
}

// Aspect-fill mapping so passthrough video covers the pane without distortion.
static float2 fillUV(float2 uv, float texA, float viewA) {
    float2 r = uv;
    if (viewA > texA) {
        float scale = texA / viewA;
        r.y = (uv.y - 0.5) * scale + 0.5;
    } else {
        float scale = viewA / texA;
        r.x = (uv.x - 0.5) * scale + 0.5;
    }
    return r;
}

// Project a ray (polar angle theta from lens axis, azimuth phi) onto the
// fisheye image using the equidistant model r = f·theta.
static float2 fisheyeUV(float theta, float phi, constant DewarpUniforms& u) {
    float rNorm = theta / max(u.lensFOV * 0.5, 1e-4);
    float2 dir = float2(cos(phi), sin(phi));
    float2 uv;
    uv.x = u.centerX + rNorm * (u.radius / max(u.texAspect, 1e-4)) * dir.x;
    uv.y = u.centerY + rNorm * u.radius * dir.y;
    return uv;
}

static float3 rotateRay(float3 v, float pan, float tilt, float roll) {
    // Rz(roll)
    float cr = cos(roll), sr = sin(roll);
    float3 a = float3(cr * v.x - sr * v.y, sr * v.x + cr * v.y, v.z);
    // Rx(tilt)
    float ct = cos(tilt), st = sin(tilt);
    float3 b = float3(a.x, ct * a.y - st * a.z, st * a.y + ct * a.z);
    // Ry(pan)
    float cp = cos(pan), sp = sin(pan);
    return float3(cp * b.x + sp * b.z, b.y, -sp * b.x + cp * b.z);
}

fragment float4 fsDewarp(VSOut in [[stage_in]],
                         texture2d<float> yTex   [[texture(0)]],
                         texture2d<float> cbcrTex [[texture(1)]],
                         constant DewarpUniforms& u [[buffer(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);

    float2 srcUV;
    bool valid = true;

    if (u.mode == 0) {
        // Passthrough (Owlet pane / raw fisheye).
        srcUV = fillUV(in.uv, u.texAspect, u.viewAspect);
    } else if (u.mode == 1) {
        // Panorama: x → azimuth, y → polar angle.
        float coverage = (2.0 * M_PI_F) / max(u.zoom, 0.2);
        float phi = (in.uv.x - 0.5) * coverage + u.pan;
        float theta = mix(u.panoUp, u.panoDown, in.uv.y);
        srcUV = fisheyeUV(theta, phi, u);
        valid = theta <= (u.lensFOV * 0.5);
    } else {
        // Perspective virtual-PTZ.
        float tanHalf = tan(u.outputFOV * 0.5) / max(u.zoom, 0.2);
        float px = (in.uv.x - 0.5) * 2.0 * tanHalf * max(u.viewAspect, 1e-4);
        float py = (0.5 - in.uv.y) * 2.0 * tanHalf;
        float3 ray = normalize(float3(px, py, 1.0));
        float3 dir = rotateRay(ray, u.pan, u.tilt, u.roll);
        float theta = acos(clamp(dir.z, -1.0, 1.0));
        float phi = atan2(dir.y, dir.x);
        srcUV = fisheyeUV(theta, phi, u);
        valid = theta <= (u.lensFOV * 0.5);
    }

    srcUV = rotateUV(srcUV, u.rotation, u.flip);

    if (u.mode != 0) {
        if (srcUV.x < 0.0 || srcUV.x > 1.0 || srcUV.y < 0.0 || srcUV.y > 1.0) {
            valid = false;
        }
    }
    if (!valid) {
        return float4(0.02, 0.02, 0.03, 1.0);
    }

    float yv = yTex.sample(s, srcUV).r;
    float2 cc = cbcrTex.sample(s, srcUV).rg;
    return float4(yuvToRGB(yv, cc), 1.0);
}
