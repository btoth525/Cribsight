import SwiftUI

/// The floating, glass global control bar at the bottom of the monitor.
struct ControlBar: View {
    @ObservedObject var vm: MonitorViewModel
    var onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            GlassIconButton(systemName: "gearshape.fill") { onOpenSettings() }

            if vm.panes.count == 2 {
                GlassIconButton(systemName: "rectangle.2.swap") { vm.toggleSwap() }
            }

            GlassIconButton(systemName: vm.nightActive ? "moon.fill" : "moon",
                            active: vm.nightActive,
                            tint: Theme.accentWarm) {
                vm.toggleNight()
            }

            GlassIconButton(systemName: "lock.fill") {
                vm.setLocked(true)
                vm.showToast("Locked · long-press to unlock")
            }
        }
        .padding(8)
        .glassCard(cornerRadius: 30)
    }
}
