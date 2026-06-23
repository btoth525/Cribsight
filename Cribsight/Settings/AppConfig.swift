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
    var dim: Double = 0.55
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
    var keepAwake: Bool = true
    var hasCompletedOnboarding: Bool = false

    static let `default` = AppSettings()
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

    /// Ensure there's at least one saved layout (used after onboarding).
    func ensureDefaultLayout() {
        guard settings.layouts.isEmpty else { return }
        let layout = PaneLayout.auto(cameraIDs: settings.cameras.map { $0.id }, name: "Default")
        settings.layouts = [layout]
        settings.activeLayoutID = layout.id
    }

    // MARK: Cameras

    func addCamera(_ camera: CameraSettings) {
        settings.cameras.append(camera)
    }

    func removeCamera(_ id: UUID) {
        settings.cameras.removeAll { $0.id == id }
        // Prune from every layout too.
        for i in settings.layouts.indices {
            settings.layouts[i].slots.removeAll { $0.cameraID == id }
        }
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
