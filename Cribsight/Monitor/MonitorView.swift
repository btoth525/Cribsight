import SwiftUI

/// The main monitor screen: the active layout of camera panes positioned by
/// normalized frames, glass controls, preset picker, night mode, kiosk lock,
/// and toasts.
struct MonitorView: View {
    @ObservedObject var vm: MonitorViewModel
    @State private var showSettings = false

    private var fisheyePane: PaneViewModel? {
        vm.panes.first(where: { $0.camera.isFisheye })
    }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            paneLayer

            bottomControls

            if vm.locked { lockChip }

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
    }

    // MARK: Panes

    @ViewBuilder
    private var paneLayer: some View {
        GeometryReader { geo in
            if let id = vm.fullscreenPaneID,
               let pane = vm.panes.first(where: { $0.id == id }) {
                CameraPaneView(pane: pane,
                               isFullscreen: true,
                               controlsVisible: vm.controlsVisible,
                               onToggleFullscreen: { vm.toggleFullscreen(pane.id) },
                               onToast: { vm.showToast($0) })
                    .ignoresSafeArea()
            } else {
                LayoutCanvas(vm: vm, size: geo.size)
            }
        }
    }

    // MARK: Controls

    @ViewBuilder
    private var bottomControls: some View {
        if vm.editingLayout {
            VStack {
                Spacer()
                LayoutEditorBar(vm: vm)
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
                ControlBar(vm: vm, onOpenSettings: { showSettings = true })
            }
            .padding(.bottom, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
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
