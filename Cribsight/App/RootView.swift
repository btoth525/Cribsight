import SwiftUI

/// Switches between first-run onboarding and the live monitor.
struct RootView: View {
    @ObservedObject var config: AppConfig
    @ObservedObject var monitor: MonitorViewModel

    var body: some View {
        Group {
            if config.settings.hasCompletedOnboarding && config.isConfigured {
                MonitorView(vm: monitor)
                    .onAppear { monitor.start() }
            } else {
                OnboardingView(config: config) {
                    config.settings.hasCompletedOnboarding = true
                    config.ensureDefaultLayout()
                    monitor.rebuildPanes()
                    monitor.start()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
