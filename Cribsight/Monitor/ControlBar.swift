import SwiftUI

/// The floating, glass global control bar at the bottom of the monitor.
struct ControlBar: View {
    @ObservedObject var vm: MonitorViewModel
    var onOpenSettings: () -> Void
    var onSaveView: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            GlassIconButton(systemName: "gearshape.fill") { onOpenSettings() }

            viewsMenu

            GlassIconButton(systemName: "square.grid.2x2",
                            active: vm.editingLayout) {
                vm.setEditingLayout(!vm.editingLayout)
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

    /// Quick switch between saved views + save the current arrangement as a new one.
    private var viewsMenu: some View {
        Menu {
            if !vm.config.settings.layouts.isEmpty {
                Section("Saved views") {
                    ForEach(vm.config.settings.layouts) { layout in
                        Button {
                            vm.selectLayout(layout.id)
                        } label: {
                            if layout.id == vm.config.settings.activeLayoutID {
                                Label(layout.name, systemImage: "checkmark")
                            } else {
                                Text(layout.name)
                            }
                        }
                    }
                }
            }
            Button { onSaveView() } label: {
                Label("Save current as new view…", systemImage: "plus")
            }
        } label: {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 46 * 0.36, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 46, height: 46)
                .glassPill()
                .contentShape(Circle())
        }
    }
}
