import Foundation
import Combine

/// How night mode is triggered.
enum NightModeTrigger: Int, Codable, CaseIterable, Identifiable {
    case off, on, scheduled
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .off: return "Off"
        case .on: return "On"
        case .scheduled: return "Scheduled"
        }
    }
}

struct NightModeSettings: Codable, Equatable {
    var trigger: NightModeTrigger = .scheduled
    var dim: Double = 0.4
    var warmth: Double = 0.7
    var startHour: Int = 19   // 7pm
    var endHour: Int = 7      // 7am

    /// Whether the dimming overlay should currently be shown.
    func isActive(hour: Int) -> Bool {
        switch trigger {
        case .off: return false
        case .on: return true
        case .scheduled:
            if startHour == endHour { return false }
            if startHour < endHour {
                return hour >= startHour && hour < endHour
            } else { // wraps past midnight
                return hour >= startHour || hour < endHour
            }
        }
    }
}

/// The full persisted settings blob (v2: dynamic cameras + layouts + connection).
struct AppSettings: Codable, Equatable {
    var connection: ConnectionSettings = ConnectionSettings()
    var cameras: [CameraSettings] = CameraSettings.defaults()
    var layouts: [PaneLayout] = []
    var activeLayoutID: UUID? = nil
    var nightMode: NightModeSettings = NightModeSettings()
    var cryAlertsEnabled: Bool = true
    var cryChimeEnabled: Bool = false
    /// Toasts + haptics when the charger disconnects or the battery runs low.
    var batteryAlertsEnabled: Bool = true
    /// UI-feedback haptics (taps, drags). Alert vibrations always play.
    var hapticsEnabled: Bool = true
    /// Seconds before the control bar auto-hides; 0 = never hide.
    var controlsHideSeconds: Double = 4
    var keepAwake: Bool = true
    var hasCompletedOnboarding: Bool = false
    var hasSeenTour: Bool = false
    var owlet: OwletBridgeSettings = OwletBridgeSettings()

    static let `default` = AppSettings()
}

// Tolerant decoding: start from defaults, override only keys present in the saved
// JSON. This is the fix for "settings don't save" — adding a new field no longer
// makes an older saved blob fail to decode and reset to defaults.
extension AppSettings {
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try c.decodeIfPresent(ConnectionSettings.self, forKey: .connection) { connection = v }
        if let v = try c.decodeIfPresent([CameraSettings].self, forKey: .cameras) { cameras = v }
        if let v = try c.decodeIfPresent([PaneLayout].self, forKey: .layouts) { layouts = v }
        if let v = try c.decodeIfPresent(UUID.self, forKey: .activeLayoutID) { activeLayoutID = v }
        if let v = try c.decodeIfPresent(NightModeSettings.self, forKey: .nightMode) { nightMode = v }
        if let v = try c.decodeIfPresent(Bool.self, forKey: .cryAlertsEnabled) { cryAlertsEnabled = v }
        if let v = try c.decodeIfPresent(Bool.self, forKey: .cryChimeEnabled) { cryChimeEnabled = v }
        if let v = try c.decodeIfPresent(Bool.self, forKey: .batteryAlertsEnabled) { batteryAlertsEnabled = v }
        if let v = try c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) { hapticsEnabled = v }
        if let v = try c.decodeIfPresent(Double.self, forKey: .controlsHideSeconds) { controlsHideSeconds = v }
        if let v = try c.decodeIfPresent(Bool.self, forKey: .keepAwake) { keepAwake = v }
        if let v = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) { hasCompletedOnboarding = v }
        if let v = try c.decodeIfPresent(Bool.self, forKey: .hasSeenTour) { hasSeenTour = v }
        if let v = try c.decodeIfPresent(OwletBridgeSettings.self, forKey: .owlet) { owlet = v }
    }
}

/// App-wide configuration store. Persists to UserDefaults as JSON and republishes
/// changes to SwiftUI. The Frigate password is kept in the Keychain, not here.
final class AppConfig: ObservableObject {
    @Published var settings: AppSettings {
        didSet { persist() }
    }

    private let storageKey = "cribsight.settings.v2"
    private let legacyKey = "cribsight.settings.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else if let migrated = AppConfig.migrateLegacy(defaults: defaults, key: legacyKey) {
            self.settings = migrated
        } else {
            self.settings = .default
        }
        applyOwletBridgeDefaults()
    }

    /// One-time correction so the pre-set bridge values reach existing installs too
    /// (UserDefaults survives an Xcode reinstall, so older saved blobs would keep the
    /// empty host / old port). Only touches an unconfigured or old-port bridge.
    private func applyOwletBridgeDefaults() {
        if settings.owlet.hostTrimmed.isEmpty {
            settings.owlet.enabled = true
            settings.owlet.host = "192.168.1.204"
            settings.owlet.vitalsPort = 8088
            settings.owlet.controlPort = 1985
        } else if settings.owlet.host == "192.168.1.204" && settings.owlet.controlPort == 1984 {
            settings.owlet.controlPort = 1985
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: storageKey)
    }

    // MARK: Credentials (Keychain)

    var frigatePassword: String? {
        get { Keychain.get(account: ConnectionSettings.keychainAccount) }
        set { Keychain.set(newValue, account: ConnectionSettings.keychainAccount) }
    }

    // MARK: Derived

    var connection: ConnectionSettings { settings.connection }

    var owlet: OwletBridgeSettings { settings.owlet }

    /// The Owlet bridge as a direct go2rtc connection (for the bridge camera video).
    var owletConnection: ConnectionSettings {
        var c = ConnectionSettings()
        c.mode = .go2rtc
        c.host = settings.owlet.hostTrimmed
        c.go2rtcPort = settings.owlet.controlPort
        c.useTLS = false
        return c
    }

    /// Which connection a camera streams from (the Owlet bridge or Frigate).
    func connection(for camera: CameraSettings) -> ConnectionSettings {
        camera.isOwletBridge ? owletConnection : settings.connection
    }

    var isConfigured: Bool {
        settings.connection.isComplete && !settings.cameras.isEmpty
            && settings.cameras.contains { !$0.streamName.isEmpty }
    }

    var cameras: [CameraSettings] { settings.cameras }

    var scheme: String { settings.connection.scheme }
    var wsScheme: String { settings.connection.wsScheme }

    /// API base for go2rtc/Frigate (login, config, discovery, WHEP).
    func apiBase() -> String { settings.connection.apiBase }

    func camera(for id: UUID) -> CameraSettings? {
        settings.cameras.first { $0.id == id }
    }

    // MARK: Layouts

    /// The currently selected layout, falling back to an auto grid of all cameras.
    var activeLayout: PaneLayout {
        if let id = settings.activeLayoutID,
           let layout = settings.layouts.first(where: { $0.id == id }) {
            return sanitized(layout)
        }
        if let first = settings.layouts.first { return sanitized(first) }
        return PaneLayout.auto(cameraIDs: settings.cameras.map { $0.id })
    }

    /// Drop slots whose camera no longer exists so we never render a dead pane.
    private func sanitized(_ layout: PaneLayout) -> PaneLayout {
        let ids = Set(settings.cameras.map { $0.id })
        var l = layout
        l.slots = layout.slots.filter { ids.contains($0.cameraID) }
        if l.slots.isEmpty {
            l.slots = PaneLayout.auto(cameraIDs: settings.cameras.map { $0.id }).slots
        }
        return l
    }

    /// Replace (or insert) a layout and make it active.
    func saveLayout(_ layout: PaneLayout) {
        if let idx = settings.layouts.firstIndex(where: { $0.id == layout.id }) {
            settings.layouts[idx] = layout
        } else {
            settings.layouts.append(layout)
        }
        settings.activeLayoutID = layout.id
    }

    func deleteLayout(_ id: UUID) {
        settings.layouts.removeAll { $0.id == id }
        if settings.activeLayoutID == id { settings.activeLayoutID = settings.layouts.first?.id }
    }

    func selectLayout(_ id: UUID) { settings.activeLayoutID = id }

    /// Save the current arrangement as a brand-new named view and make it active.
    @discardableResult
    func saveCurrentAsNewLayout(name: String) -> UUID {
        var layout = activeLayout
        layout.id = UUID()
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        layout.name = trimmed.isEmpty ? "View \(settings.layouts.count + 1)" : trimmed
        saveLayout(layout)
        return layout.id
    }

    /// Rename a saved view.
    func renameLayout(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let i = settings.layouts.firstIndex(where: { $0.id == id }) else { return }
        settings.layouts[i].name = trimmed
    }

    /// Ensure there's at least one saved layout (used after onboarding). Only
    /// cameras that actually have a stream become panes, so a one-camera setup
    /// opens as a single full-screen pane (not a dead second one).
    func ensureDefaultLayout() {
        guard settings.layouts.isEmpty else { return }
        var ids = settings.cameras
            .filter { !$0.streamName.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.id }
        if ids.isEmpty { ids = settings.cameras.map { $0.id } }
        let layout = PaneLayout.auto(cameraIDs: ids, name: "Default")
        settings.layouts = [layout]
        settings.activeLayoutID = layout.id
    }

    // MARK: Cameras

    func addCamera(_ camera: CameraSettings) {
        settings.cameras.append(camera)
    }

    /// Add a camera that streams directly from the Owlet bridge (not Frigate),
    /// optionally paired to a sock for the vitals overlay. Grows the grid.
    func addOwletCamera(streamName: String, displayName: String, sockDSN: String?) {
        guard !settings.cameras.contains(where: { $0.isOwletBridge && $0.streamName == streamName }) else { return }
        var cam = CameraSettings.blank()
        cam.streamName = streamName
        cam.displayName = displayName
        cam.isOwletBridge = true
        cam.owletSockDSN = sockDSN
        settings.cameras.append(cam)
        reflowActiveLayout()
    }

    /// Add a camera for a discovered stream and grow the grid to include it.
    func addCameraFromStream(_ stream: String, isFisheye: Bool = false) {
        guard !settings.cameras.contains(where: { $0.streamName == stream }) else { return }
        var cam = CameraSettings.blank()
        cam.streamName = stream
        cam.displayName = AppConfig.prettify(stream)
        cam.isFisheye = isFisheye
        settings.cameras.append(cam)
        reflowActiveLayout()
    }

    /// Re-flow the active layout into a balanced grid of all configured cameras,
    /// so adding/removing a camera expands/condenses the grid sensibly.
    func reflowActiveLayout() {
        let ids = settings.cameras
            .filter { !$0.streamName.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.id }
        guard !ids.isEmpty else { return }
        var layout = activeLayout
        layout.slots = PaneLayout.auto(cameraIDs: ids).slots
        saveLayout(layout)
    }

    /// Replace the camera list with the streams discovered from Frigate, so the
    /// user doesn't assign anything by hand. Existing cameras whose stream still
    /// exists keep their settings (display name, fisheye flag, calibration);
    /// brand-new streams get an auto-named camera.
    func autoPopulateCameras(from streams: [String]) {
        let names = streams.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !names.isEmpty else { return }
        settings.cameras = names.map { stream in
            settings.cameras.first { $0.streamName == stream }
                ?? {
                    var cam = CameraSettings.blank()
                    cam.streamName = stream
                    cam.displayName = AppConfig.prettify(stream)
                    return cam
                }()
        }
    }

    /// Set the cameras to exactly the chosen streams (onboarding checklist), in the
    /// given order, flagging which are fisheye. Reuses existing camera settings when
    /// the stream already exists so calibration/names are preserved.
    func setSelectedCameras(streams: [String], fisheye: Set<String>) {
        settings.cameras = streams.map { stream in
            var cam = settings.cameras.first { $0.streamName == stream }
                ?? {
                    var c = CameraSettings.blank()
                    c.streamName = stream
                    c.displayName = AppConfig.prettify(stream)
                    return c
                }()
            cam.isFisheye = fisheye.contains(stream)
            return cam
        }
    }

    /// "front_door" / "garage-cam" → "Front Door" / "Garage Cam".
    static func prettify(_ stream: String) -> String {
        stream
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { word -> String in
                guard let first = word.first else { return "" }
                return first.uppercased() + word.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }

    func removeCamera(_ id: UUID) {
        settings.cameras.removeAll { $0.id == id }
        // Prune from every layout too.
        for i in settings.layouts.indices {
            settings.layouts[i].slots.removeAll { $0.cameraID == id }
        }
        // Re-balance the visible grid so a removed camera doesn't leave a gap.
        if !settings.cameras.isEmpty { reflowActiveLayout() }
    }

    // MARK: Migration

    private struct LegacyV1: Codable {
        var serverHost: String?
        var serverPort: Int?
        var useTLS: Bool?
        var cameraA: CameraSettings?
        var cameraB: CameraSettings?
        var nightMode: NightModeSettings?
        var cryAlertsEnabled: Bool?
        var cryChimeEnabled: Bool?
        var keepAwake: Bool?
        var hasCompletedOnboarding: Bool?
    }

    private static func migrateLegacy(defaults: UserDefaults, key: String) -> AppSettings? {
        guard let data = defaults.data(forKey: key),
              let old = try? JSONDecoder().decode(LegacyV1.self, from: data) else { return nil }
        var s = AppSettings()
        s.connection.mode = .go2rtc
        s.connection.host = old.serverHost ?? ""
        s.connection.go2rtcPort = old.serverPort ?? 1984
        s.connection.useTLS = old.useTLS ?? false

        var cams: [CameraSettings] = []
        if let a = old.cameraA { cams.append(a) }
        if let b = old.cameraB { cams.append(b) }
        if cams.isEmpty { cams = CameraSettings.defaults() }
        s.cameras = cams

        s.nightMode = old.nightMode ?? NightModeSettings()
        s.cryAlertsEnabled = old.cryAlertsEnabled ?? true
        s.cryChimeEnabled = old.cryChimeEnabled ?? false
        s.keepAwake = old.keepAwake ?? true
        s.hasCompletedOnboarding = old.hasCompletedOnboarding ?? false

        let layout = PaneLayout.auto(cameraIDs: cams.map { $0.id }, name: "Default")
        s.layouts = [layout]
        s.activeLayoutID = layout.id
        return s
    }
}
