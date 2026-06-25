import Foundation
import CoreGraphics

/// A single metric that can appear on the Baby Mode vitals HUD. The user chooses
/// and orders these per camera (Settings → camera → HUD metrics), so the overlay
/// shows exactly what they want to watch.
enum VitalsField: String, Codable, CaseIterable, Identifiable {
    case heartRate, oxygen, oxygenAvg, sleep, battery
    case skinTemp, roomTemp, humidity, signal, movement, noise

    var id: String { rawValue }

    /// The default HUD for a newly paired camera.
    static let defaultFields: [VitalsField] = [.heartRate, .oxygen, .sleep, .battery]

    var label: String {
        switch self {
        case .heartRate: return "Heart rate"
        case .oxygen:    return "Oxygen"
        case .oxygenAvg:  return "Oxygen (avg)"
        case .sleep:     return "Sleep"
        case .battery:   return "Battery"
        case .skinTemp:  return "Skin temp"
        case .roomTemp:  return "Room temp"
        case .humidity:  return "Humidity"
        case .signal:    return "Signal"
        case .movement:  return "Movement"
        case .noise:     return "Noise"
        }
    }

    var icon: String {
        switch self {
        case .heartRate: return "heart.fill"
        case .oxygen:    return "lungs.fill"
        case .oxygenAvg:  return "lungs"
        case .sleep:     return "moon.zzz.fill"
        case .battery:   return "battery.100"
        case .skinTemp:  return "thermometer.medium"
        case .roomTemp:  return "thermometer.low"
        case .humidity:  return "humidity.fill"
        case .signal:    return "antenna.radiowaves.left.and.right"
        case .movement:  return "waveform.path.ecg"
        case .noise:     return "waveform"
        }
    }

    var unit: String {
        switch self {
        case .heartRate: return "bpm"
        case .oxygen, .oxygenAvg, .humidity, .battery: return "%"
        case .sleep, .movement: return ""
        case .skinTemp, .roomTemp: return "°F"
        case .signal: return "dBm"
        case .noise: return "dB"
        }
    }

    /// The value text for this field from a vitals sample (nil when no data).
    func value(from v: Vitals) -> String? {
        switch self {
        case .heartRate: return v.heartRate.map { "\($0)" }
        case .oxygen:    return v.oxygen.map { "\($0)" }
        case .oxygenAvg:  return v.oxygenAvg.map { "\($0)" }
        case .sleep:     return v.sleepShort
        case .battery:   return v.battery.map { "\($0)" }
        case .skinTemp:  return v.skinTemp.map { String(format: "%.0f", $0) }
        case .roomTemp:  return v.roomTemp.map { String(format: "%.0f", $0) }
        case .humidity:  return v.humidity.map { String(format: "%.0f", $0) }
        case .signal:    return v.signalStrength.map { "\($0)" }
        case .movement:  return v.movement.map { "\($0)" }
        case .noise:     return v.noise.map { String(format: "%.0f", $0) }
        }
    }
}

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
    /// Base field of view of the virtual-PTZ window (zoom narrows it further).
    var outputFOVDegrees: Float = 90
    /// Vertical extent of the panorama strip, in degrees from the lens axis.
    var panoramaUpDegrees: Float = 12     // how far above the horizon to include
    var panoramaDownDegrees: Float = 90   // down toward the floor/cribs
    var roll: Float = 0
    var flipHorizontal: Bool = false
    /// Flip the drag direction per axis (mount-dependent). Defaults give the
    /// "grab the scene" feel; flip if pan/tilt feels backwards on your install.
    var invertPan: Bool = false
    var invertTilt: Bool = false
    /// The single immersive mode: a rectilinear virtual-PTZ with a level horizon.
    var mode: FisheyeProjectionMode = .perspective
    /// Opens looking into the room at a moderate downward angle, filling the pane.
    var defaultOrientation: ViewOrientation = ViewOrientation(pan: 0, tilt: 0.9, zoom: 1.2)
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
    /// When true, this camera streams directly from the Owlet bridge (go2rtc) and
    /// `streamName` is the bridge camera name — not a Frigate stream.
    var isOwletBridge: Bool = false
    /// Paired Owlet sock (by dsn) whose vitals show on this camera.
    var owletSockDSN: String? = nil
    /// Which vitals appear on the live HUD, in order (user-customizable).
    var hudFields: [VitalsField] = VitalsField.defaultFields

    /// Baby Mode = has live sock vitals / bridge talk + lullaby.
    var babyMode: Bool { isOwletBridge || owletSockDSN != nil }

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
            dewarp: DewarpParams(mode: .perspective),
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

// Tolerant decoding so adding the Owlet fields never resets saved cameras.
extension CameraSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? "Camera"
        streamName = try c.decodeIfPresent(String.self, forKey: .streamName) ?? ""
        isFisheye = try c.decodeIfPresent(Bool.self, forKey: .isFisheye) ?? false
        startMuted = try c.decodeIfPresent(Bool.self, forKey: .startMuted) ?? false
        crySensitivity = try c.decodeIfPresent(Double.self, forKey: .crySensitivity) ?? 0.6
        dewarp = try c.decodeIfPresent(DewarpParams.self, forKey: .dewarp) ?? DewarpParams()
        presets = try c.decodeIfPresent([ViewPreset].self, forKey: .presets) ?? []
        isOwletBridge = try c.decodeIfPresent(Bool.self, forKey: .isOwletBridge) ?? false
        owletSockDSN = try c.decodeIfPresent(String.self, forKey: .owletSockDSN)
        hudFields = try c.decodeIfPresent([VitalsField].self, forKey: .hudFields) ?? VitalsField.defaultFields
    }
}

extension ViewPreset {
    /// Quick aims for the immersive virtual-PTZ (the only fisheye mode the app exposes).
    static var defaults: [ViewPreset] {
        [
            ViewPreset(name: "Overview", systemImage: "viewfinder",
                       mode: .perspective,
                       orientation: ViewOrientation(pan: 0, tilt: 0.9, zoom: 1.2)),
            ViewPreset(name: "Crib A", systemImage: "bed.double",
                       mode: .perspective,
                       orientation: ViewOrientation(pan: -0.7, tilt: 1.0, zoom: 1.8)),
            ViewPreset(name: "Crib B", systemImage: "bed.double.fill",
                       mode: .perspective,
                       orientation: ViewOrientation(pan: 0.7, tilt: 1.0, zoom: 1.8))
        ]
    }
}
