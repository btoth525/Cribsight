import SwiftUI

/// The main monitor screen: the active layout of camera panes positioned by
/// normalized frames, glass controls, preset picker, night mode, kiosk lock,
/// and toasts.
struct MonitorView: View {
    @ObservedObject var vm: MonitorViewModel
    @State private var showSettings = false
    @State private var showSaveView = false
    @State private var newViewName = ""
    @State private var vitalsSheet: VitalsSheet?

    private struct VitalsSheet: Identifiable {
        let id = UUID()
        let dsn: String
        let title: String
    }

    private func showVitals(_ camera: CameraSettings) {
        guard let dsn = camera.owletSockDSN else { return }
        vitalsSheet = VitalsSheet(dsn: dsn, title: camera.displayName)
    }

    private var fisheyePane: PaneViewModel? {
        vm.panes.first(where: { $0.camera.isFisheye })
    }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            paneLayer

            if vm.panes.isEmpty {
                emptyState
            }

            bottomControls

            if vm.locked && vm.controlsVisible {
                lockChip
                    .transition(.opacity)
            }

            if let toast = vm.toast {
                VStack {
                    ToastView(message: toast)
                        .padding(.top, 14)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { vm.toggleControls() }
        .onLongPressGesture(minimumDuration: 0.7) {
            if vm.locked {
                vm.setLocked(false)
                vm.showToast("Unlocked")
            }
        }
        .nightMode(enabled: vm.nightActive, dim: vm.nightDim, warmth: vm.nightWarmth)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $showSettings, onDismiss: { vm.applySettingsChange() }) {
            SettingsView(config: vm.config)
        }
        .sheet(item: $vitalsSheet) { sheet in
            VitalsHistoryView(service: vm.vitals, dsn: sheet.dsn, title: sheet.title)
        }
        .alert("Save view", isPresented: $showSaveView) {
            TextField("View name", text: $newViewName)
            Button("Save") {
                vm.config.saveCurrentAsNewLayout(name: newViewName)
                vm.rebuildPanes()
                newViewName = ""
                vm.showToast("View saved")
            }
            Button("Cancel", role: .cancel) { newViewName = "" }
        } message: {
            Text("Name this camera arrangement so you can switch back to it anytime from the Views menu.")
        }
    }

    // MARK: Panes

    @ViewBuilder
    private var paneLayer: some View {
        GeometryReader { geo in
            if let id = vm.fullscreenPaneID,
               let pane = vm.panes.first(where: { $0.id == id }) {
                CameraPaneView(pane: pane,
                               isFullscreen: true,
                               controlsVisible: vm.controlsVisible && !vm.locked,
                               interactive: !vm.locked,
                               vitals: vm.sockVitals(for: pane.camera),
                               onToggleFullscreen: { vm.toggleFullscreen(pane.id) },
                               onToast: { vm.showToast($0) },
                               onShowVitals: { showVitals(pane.camera) })
                    .ignoresSafeArea()
            } else {
                LayoutCanvas(vm: vm, size: geo.size, onShowVitals: { showVitals($0) })
            }
        }
    }

    // MARK: Controls

    @ViewBuilder
    private var bottomControls: some View {
        if vm.editingLayout {
            VStack {
                Spacer()
                LayoutEditorBar(vm: vm, onSaveView: { showSaveView = true })
            }
            .padding(.bottom, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if !vm.locked && vm.controlsVisible {
            VStack(spacing: 12) {
                Spacer()
                if let fisheye = fisheyePane,
                   vm.fullscreenPaneID == nil || vm.fullscreenPaneID == fisheye.id {
                    PresetPicker(pane: fisheye)
                }
                ControlBar(vm: vm,
                           onOpenSettings: { showSettings = true },
                           onSaveView: { showSaveView = true })
            }
            .padding(.bottom, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "video.slash")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            Text("No cameras yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Open Settings to connect to Frigate and add your cameras.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button { showSettings = true } label: {
                Label("Open Settings", systemImage: "gearshape.fill")
            }
            .glassButton(prominent: true)
            .padding(.top, 4)
        }
        .padding(40)
    }

    private var lockChip: some View {
        VStack {
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("Locked · long-press to unlock")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .glassPill()
            .padding(.bottom, 18)
        }
    }
}
