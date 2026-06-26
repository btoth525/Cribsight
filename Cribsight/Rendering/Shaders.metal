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

fragment float4 fsDewarp(VSOut in [[stage_in]],
                         texture2d<float> yTex   [[texture(0)]],
                         texture2d<float> cbcrTex [[texture(1)]],
                         constant DewarpUniforms& u [[buffer(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);

    float2 srcUV;
    float theta = 0.0;
    bool fisheye = (u.mode != 0);

    if (u.mode == 0) {
        // Passthrough (normal camera / raw fisheye).
        srcUV = fillUV(in.uv, u.texAspect, u.viewAspect);
    } else if (u.mode == 1) {
        // Panorama: x → azimuth, y → polar angle.
        float coverage = (2.0 * M_PI_F) / max(u.zoom, 0.2);
        float phi = (in.uv.x - 0.5) * coverage + u.pan;
        theta = mix(u.panoUp, u.panoDown, in.uv.y);
        srcUV = fisheyeUV(theta, phi, u);
    } else if (u.mode == 2) {
        // Rectilinear virtual-PTZ with a LEVEL horizon (the navigable mode pro
        // fisheye apps use). pan = azimuth about the lens/vertical axis (z, which
        // points down for a ceiling mount); tilt = elevation from straight-down.
        // The "right" basis vector is kept horizontal, so dragging left↔right
        // scrolls level instead of rolling the image.
        float tanHalf = tan(u.outputFOV * 0.5) / max(u.zoom, 0.2);
        float sx = (in.uv.x - 0.5) * 2.0 * tanHalf * max(u.viewAspect, 1e-4);
        float sy = (0.5 - in.uv.y) * 2.0 * tanHalf;

        float tilt = clamp(u.tilt, 0.02, 1.56);     // 0 = straight down, ~89° = horizontal
        float cp = cos(u.pan), sp = sin(u.pan);
        float st = sin(tilt), ct = cos(tilt);

        float3 fwd   = float3(st * cp, st * sp, ct);   // view direction
        float3 right = float3(-sp, cp, 0.0);           // always horizontal → level pan
        float3 up    = cross(right, fwd);              // toward the ceiling

        float3 dir = normalize(fwd + sx * right + sy * up);
        theta = acos(clamp(dir.z, -1.0, 1.0));
        float phi = atan2(dir.y, dir.x);
        srcUV = fisheyeUV(theta, phi, u);
    } else {
        // Little planet: stereographic projection of the fisheye onto a disc.
        // pan spins the planet, tilt tips it up toward the horizon (Reolink-style
        // "rise up into the room"), and zoom scales the planet.
        float2 p = (in.uv - 0.5) * 2.0;
        p.x *= max(u.viewAspect, 1e-4);
        float R = length(p) / max(u.zoom, 0.2);
        float phi0 = atan2(p.y, p.x) + u.pan;       // spin around the lens axis
        float theta0 = 2.0 * atan(R);               // 0 at center (nadir) → π at rim

        // Stereographic plane coord → ray in the lens frame (+z = down the axis).
        float3 ray = float3(sin(theta0) * cos(phi0),
                            sin(theta0) * sin(phi0),
                            cos(theta0));
        // Tip the planet about the X axis so dragging up looks up toward the walls.
        float ct = cos(u.tilt), st = sin(u.tilt);
        float3 dir = float3(ray.x,
                            ct * ray.y - st * ray.z,
                            st * ray.y + ct * ray.z);

        theta = acos(clamp(dir.z, -1.0, 1.0));
        float phi = atan2(dir.y, dir.x);
        srcUV = fisheyeUV(theta, phi, u);
    }

    srcUV = rotateUV(srcUV, u.rotation, u.flip);

    if (!fisheye) {
        float yv = yTex.sample(s, srcUV).r;
        float2 cc = cbcrTex.sample(s, srcUV).rg;
        return float4(yuvToRGB(yv, cc), 1.0);
    }

    // Soft, anti-aliased mask: fade out at the lens edge and at the source
    // borders so the circular boundary doesn't show a hard jagged ring.
    float edge = u.lensFOV * 0.5;
    float aa = 1.0 - smoothstep(edge * 0.98, edge, theta);
    aa *= smoothstep(0.0, 0.004, srcUV.x) * (1.0 - smoothstep(0.996, 1.0, srcUV.x));
    aa *= smoothstep(0.0, 0.004, srcUV.y) * (1.0 - smoothstep(0.996, 1.0, srcUV.y));

    float3 bg = float3(0.02, 0.02, 0.03);
    if (aa <= 0.0) { return float4(bg, 1.0); }

    float2 uv = clamp(srcUV, 0.0, 1.0);
    float yv = yTex.sample(s, uv).r;
    float2 cc = cbcrTex.sample(s, uv).rg;
    float3 color = yuvToRGB(yv, cc);
    return float4(mix(bg, color, aa), 1.0);
}
