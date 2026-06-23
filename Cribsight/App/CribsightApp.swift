import SwiftUI

@main
struct CribsightApp: App {
    @StateObject private var config: AppConfig
    @StateObject private var monitor: MonitorViewModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let config = AppConfig()
        _config = StateObject(wrappedValue: config)
        _monitor = StateObject(wrappedValue: MonitorViewModel(config: config))
    }

    var body: some Scene {
        WindowGroup {
            RootView(config: config, monitor: monitor)
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        monitor.resumeFromForeground()
                    case .background:
                        monitor.pauseForBackground()
                    default:
                        break
                    }
                }
        }
    }
}
