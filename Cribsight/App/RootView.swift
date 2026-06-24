import SwiftUI

/// Switches between first-run onboarding and the live monitor.
struct RootView: View {
    @ObservedObject var config: AppConfig
    @ObservedObject var monitor: MonitorViewModel
    @State private var showTour = false

    var body: some View {
        Group {
            if config.settings.hasCompletedOnboarding && config.isConfigured {
                MonitorView(vm: monitor)
                    .onAppear {
                        monitor.start()
                        if !config.settings.hasSeenTour { showTour = true }
                    }
            } else {
                OnboardingView(config: config) {
                    config.settings.hasCompletedOnboarding = true
                    config.ensureDefaultLayout()
                    monitor.rebuildPanes()
                    monitor.start()
                    showTour = !config.settings.hasSeenTour
                }
            }
        }
        .fullScreenCover(isPresented: $showTour) {
            TourView {
                config.settings.hasSeenTour = true
                showTour = false
            }
        }
        .preferredColorScheme(.dark)
    }
}
