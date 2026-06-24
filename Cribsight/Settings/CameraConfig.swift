import Foundation
import CoreGraphics

/// How the fisheye pane is unwrapped.
enum FisheyeProjectionMode: Int, Codable, CaseIterable, Identifiable {
    case panorama      // equirectangular strip — the ceiling-down default
    case perspective   // virtual pinhole camera (rectilinear), for zooming on a crib
    case littlePlanet  // stereographic "tiny planet" of the whole room

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .panorama: return "Panorama"
        case .perspective: return "Zoom"
        case .littlePlanet: return "Planet"
        }
    }
}

/// Live look-around state for the virtual camera (also stored inside presets).
struct ViewOrientation: Codable, Equatable {
    var pan: Float = 0      // yaw, radians
    var tilt: Float = 0     // pitch, radians
    var zoom: Float = 1     // 1 = nominal output FOV; >1 zooms in

    static let identity = ViewOrientation()
}

/// Fisheye lens calibration + default framing for the dewarp shader.
struct DewarpParams: Codable, Equatable {
    /// Normalized center of the fisheye circle (0…1 of the source frame).
    var centerX: Float = 0.5
    var centerY: Float = 0.5
    /// Normalized radius of the fisheye circle (fraction of the shorter side).
    var radius: Float = 0.5
    /// Physical lens field of view (Reolink fisheye ≈ 180–200°).
    var lensFOVDegrees: Float = 200
    /// Output FOV used by the perspective/virtual-PTZ mode.
    var outputFOVDegrees: Float = 95
    /// Vertical extent of the panorama strip, in degrees from the lens axis.
    var panoramaUpDegrees: Float = 12     // how far above the horizon to include
    var panoramaDownDegrees: Float = 90   // down toward the floor/cribs
    var roll: Float = 0
    var flipHorizontal: Bool = false
    /// Flip the drag direction per axis (mount-dependent). Defaults give the
    /// "grab the scene" feel; flip if pan/tilt feels backwards on your install.
    var invertPan: Bool = false
    var invertTilt: Bool = false
    /// The single immersive mode: the stereographic "planet" — shows the whole
    /// room and lets you pinch-zoom and drag to look around inside it.
    var mode: FisheyeProjectionMode = .littlePlanet
    /// Opens on the full planet overview (the whole room); pinch/drag from there.
    var defaultOrientation: ViewOrientation = .identity
}

// Tolerant decoding: start from defaults and override only the keys present in
// the saved JSON, so adding a new field never resets a user's saved settings.
extension DewarpParams {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try c.decodeIfPresent(Float.self, forKey: .centerX) { centerX = v }
        if let v = try c.decodeIfPresent(Float.self, forKey: .centerY) { centerY = v }
        if let v = try c.decodeIfPresent(Float.self, forKey: .radius) { radius = v }
        if let v = try c.decodeIfPresent(Float.self, forKey: .lensFOVDegrees) { lensFOVDegrees = v }
        if let v = try c.decodeIfPresent(Float.self, forKey: .outputFOVDegrees) { outputFOVDegrees = v }
        if let v = try c.decodeIfPresent(Float.self, forKey: .panoramaUpDegrees) { panoramaUpDegrees = v }
        if let v = try c.decodeIfPresent(Float.self, forKey: .panoramaDownDegrees) { panoramaDownDegrees = v }
        if let v = try c.decodeIfPresent(Float.self, forKey: .roll) { roll = v }
        if let v = try c.decodeIfPresent(Bool.self, forKey: .flipHorizontal) { flipHorizontal = v }
        if let v = try c.decodeIfPresent(Bool.self, forKey: .invertPan) { invertPan = v }
        if let v = try c.decodeIfPresent(Bool.self, forKey: .invertTilt) { invertTilt = v }
        if let v = try c.decodeIfPresent(FisheyeProjectionMode.self, forKey: .mode) { mode = v }
        if let v = try c.decodeIfPresent(ViewOrientation.self, forKey: .defaultOrientation) { defaultOrientation = v }
    }
}

/// A saved framing the user can snap to.
struct ViewPreset: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var systemImage: String
    var mode: FisheyeProjectionMode
    var orientation: ViewOrientation
}

/// One camera pane.
struct CameraSettings: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var displayName: String
    var streamName: String
    var isFisheye: Bool
    var startMuted: Bool
    /// 0 = least sensitive (only very loud), 1 = most sensitive.
    var crySensitivity: Double
    var dewarp: DewarpParams
    var presets: [ViewPreset]

    static func owlet() -> CameraSettings {
        CameraSettings(
            displayName: "Owlet",
            streamName: "owlet",
            isFisheye: false,
            startMuted: false,
            crySensitivity: 0.6,
            dewarp: DewarpParams(),
            presets: []
        )
    }

    static func reolink() -> CameraSettings {
        CameraSettings(
            displayName: "Nursery",
            streamName: "reolink",
            isFisheye: true,
            startMuted: false,
            crySensitivity: 0.6,
            dewarp: DewarpParams(mode: .littlePlanet),
            presets: ViewPreset.defaults
        )
    }

    /// Seed cameras for a fresh install (also the migration fallback).
    static func defaults() -> [CameraSettings] { [owlet(), reolink()] }

    /// A blank camera the user can fill in when adding one by hand.
    static func blank() -> CameraSettings {
        CameraSettings(displayName: "Camera", streamName: "", isFisheye: false,
                       startMuted: false, crySensitivity: 0.6,
                       dewarp: DewarpParams(), presets: [])
    }
}

extension ViewPreset {
    /// Quick aims for the immersive planet view (the only fisheye mode the app exposes).
    static var defaults: [ViewPreset] {
        [
            ViewPreset(name: "Overview", systemImage: "globe.americas",
                       mode: .littlePlanet, orientation: .identity),
            ViewPreset(name: "Crib A", systemImage: "bed.double",
                       mode: .littlePlanet,
                       orientation: ViewOrientation(pan: -0.6, tilt: 0.6, zoom: 1.6)),
            ViewPreset(name: "Crib B", systemImage: "bed.double.fill",
                       mode: .littlePlanet,
                       orientation: ViewOrientation(pan: 0.6, tilt: 0.6, zoom: 1.6))
        ]
    }
}
