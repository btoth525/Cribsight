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

/// The full persisted settings blob.
struct AppSettings: Codable, Equatable {
    var serverHost: String = ""
    var serverPort: Int = 1984
    var useTLS: Bool = false
    var cameraA: CameraSettings = .owlet()
    var cameraB: CameraSettings = .reolink()
    var nightMode: NightModeSettings = NightModeSettings()
    var cryAlertsEnabled: Bool = true
    var cryChimeEnabled: Bool = false
    var keepAwake: Bool = true
    var hasCompletedOnboarding: Bool = false

    static let `default` = AppSettings()
}

/// App-wide configuration store. Persists to UserDefaults as JSON and republishes
/// changes to SwiftUI. Bindings into nested fields (e.g. `$config.settings.cameraB.dewarp.radius`)
/// work because `settings` is a published mutable value.
final class AppConfig: ObservableObject {
    @Published var settings: AppSettings {
        didSet { persist() }
    }

    private let storageKey = "cribsight.settings.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = .default
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: storageKey)
    }

    // MARK: Derived

    var isConfigured: Bool {
        !settings.serverHost.trimmingCharacters(in: .whitespaces).isEmpty
            && !settings.cameraA.streamName.isEmpty
            && !settings.cameraB.streamName.isEmpty
    }

    var cameras: [CameraSettings] { [settings.cameraA, settings.cameraB] }

    var scheme: String { settings.useTLS ? "https" : "http" }
    var wsScheme: String { settings.useTLS ? "wss" : "ws" }

    /// `http://host:port` base for the go2rtc API.
    func apiBase() -> String {
        "\(scheme)://\(settings.serverHost):\(settings.serverPort)"
    }
}
