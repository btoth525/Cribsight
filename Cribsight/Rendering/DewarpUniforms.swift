import Foundation

/// CPU-side mirror of the `DewarpUniforms` struct in `Shaders.metal`.
/// Field order and sizes MUST match the Metal struct exactly (all 4-byte
/// scalars, no SIMD packing surprises).
struct DewarpUniformsData {
    var mode: Int32 = 0          // 0 = passthrough, 1 = panorama, 2 = perspective
    var rotation: Int32 = 0      // 0,1,2,3 → 0/90/180/270°
    var flip: Int32 = 0          // 0/1 horizontal flip
    var pad0: Int32 = 0

    var centerX: Float = 0.5
    var centerY: Float = 0.5
    var radius: Float = 0.5
    var lensFOV: Float = 3.4907       // 200° in radians

    var outputFOV: Float = 1.6581     // 95° in radians
    var pan: Float = 0
    var tilt: Float = 0
    var zoom: Float = 1

    var panoUp: Float = 0.2094        // 12°
    var panoDown: Float = 1.5708      // 90°
    var roll: Float = 0
    var texAspect: Float = 1.7778

    var viewAspect: Float = 1.7778
    var pad1: Float = 0
    var pad2: Float = 0
    var pad3: Float = 0

    static func make(isFisheye: Bool,
                     params: DewarpParams,
                     orientation: ViewOrientation,
                     mode: FisheyeProjectionMode) -> DewarpUniformsData {
        var u = DewarpUniformsData()
        if !isFisheye {
            u.mode = 0
        } else {
            u.mode = (mode == .panorama) ? 1 : 2
        }
        u.flip = params.flipHorizontal ? 1 : 0
        u.centerX = params.centerX
        u.centerY = params.centerY
        u.radius = params.radius
        u.lensFOV = params.lensFOVDegrees * .pi / 180
        u.outputFOV = params.outputFOVDegrees * .pi / 180
        u.pan = orientation.pan
        u.tilt = orientation.tilt
        u.zoom = max(0.2, orientation.zoom)
        u.panoUp = params.panoramaUpDegrees * .pi / 180
        u.panoDown = params.panoramaDownDegrees * .pi / 180
        u.roll = params.roll
        return u
    }
}
