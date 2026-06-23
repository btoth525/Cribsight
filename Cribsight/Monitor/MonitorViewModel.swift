import Foundation
import SwiftUI
import UIKit
import Combine

/// Top-level monitor state: the dynamic set of camera panes, the active layout,
/// Frigate login, fullscreen, kiosk lock, control-bar auto-hide, night-mode
/// evaluation, and transient toasts.
final class MonitorViewModel: ObservableObject {
    @Published private(set) var panes: [PaneViewModel] = []
    @Published private(set) var activeLayout: PaneLayout
    @Published var fullscreenPaneID: UUID?
    @Published var controlsVisible = true
    @Published var locked = false
    @Published var nightActive = false
    @Published var editingLayout = false
    @Published var toast: String?

    let config: AppConfig

    /// Frigate auth session (nil in Direct mode). Recreated on each login.
    private var frigateClient: FrigateClient?

    private var nightTimer: Timer?
    private var controlsHideWork: DispatchWorkItem?
    private var toastWork: DispatchWorkItem?

    init(config: AppConfig) {
        self.config = config
        self.activeLayout = config.activeLayout
        rebuildPanes()
        evaluateNightMode()
    }

    /// Pane driving a given camera (a camera may appear in several layout slots).
    func pane(for cameraID: UUID) -> PaneViewModel? {
        panes.first { $0.camera.id == cameraID }
    }

    var fisheyePanes: [PaneViewModel] { panes.filter { $0.camera.isFisheye } }

    // MARK: Lifecycle

    func start() {
        AudioController.shared.activate()
        UIApplication.shared.isIdleTimerDisabled = config.settings.keepAwake
        connectThenStartPanes()
        startNightTimer()
        scheduleControlsHide()
    }

    func stop() {
        panes.forEach { $0.stop() }
        nightTimer?.invalidate(); nightTimer = nil
        UIApplication.shared.isIdleTimerDisabled = false
        AudioController.shared.deactivate()
    }

    func pauseForBackground() {
        panes.forEach { $0.stop() }
        nightTimer?.invalidate(); nightTimer = nil
    }

    func resumeFromForeground() {
        guard config.settings.hasCompletedOnboarding, config.isConfigured else { return }
        AudioController.shared.activate()
        UIApplication.shared.isIdleTimerDisabled = config.settings.keepAwake
        connectThenStartPanes()
        startNightTimer()
        evaluateNightMode()
    }

    /// In Frigate mode, log in for a JWT before starting the panes (their
    /// WebSocket signaling reads the token via `frigateClient`). Direct mode
    /// starts immediately.
    private func connectThenStartPanes() {
        guard config.settings.connection.mode == .frigate else {
            panes.forEach { $0.start() }
            return
        }
        let conn = config.settings.connection
        let client = FrigateClient(apiBase: conn.apiBase)
        frigateClient = client
        client.login(username: conn.username, password: config.frigatePassword ?? "") { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success:
                    self.panes.forEach { $0.start() }
                case .failure(let error):
                    self.showToast("Frigate login failed · \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: Panes

    func rebuildPanes() {
        let conn = config.settings.connection
        let cams = config.settings.cameras
        let tokenProvider: () -> String? = { [weak self] in self?.frigateClient?.token }

        if panes.map({ $0.id }) == cams.map({ $0.id }) {
            for (index, cam) in cams.enumerated() {
                panes[index].updateConfig(camera: cam, connection: conn,
                                          cryAlertsEnabled: config.settings.cryAlertsEnabled,
                                          cryChimeEnabled: config.settings.cryChimeEnabled)
            }
        } else {
            panes.forEach { $0.stop() }
            panes = cams.map { makePane($0, connection: conn, tokenProvider: tokenProvider) }
        }
        activeLayout = config.activeLayout
    }

    private func makePane(_ cam: CameraSettings,
                          connection: ConnectionSettings,
                          tokenProvider: @escaping () -> String?) -> PaneViewModel {
        let vm = PaneViewModel(camera: cam, connection: connection, tokenProvider: tokenProvider,
                               cryAlertsEnabled: config.settings.cryAlertsEnabled,
                               cryChimeEnabled: config.settings.cryChimeEnabled)
        vm.onCry = { [weak self] name in
            self?.showToast("Sound detected · \(name)")
        }
        return vm
    }

    /// Apply edited settings coming back from the Settings sheet. `rebuildPanes`
    /// reconnects panes whose stream/connection changed and builds any new ones;
    /// `connectThenStartPanes` (re)logs into Frigate if needed and starts the
    /// rest. `start()` is guarded, so already-running panes are untouched.
    func applySettingsChange() {
        rebuildPanes()
        connectThenStartPanes()
        UIApplication.shared.isIdleTimerDisabled = config.settings.keepAwake
        evaluateNightMode()
    }

    func refreshLayout() {
        activeLayout = config.activeLayout
    }

    // MARK: Layout editing

    func setEditingLayout(_ editing: Bool) {
        withAnimation(.easeInOut(duration: 0.25)) { editingLayout = editing }
        if editing {
            fullscreenPaneID = nil
            controlsVisible = true
            controlsHideWork?.cancel()
        } else {
            scheduleControlsHide()
        }
        Haptics.tap()
    }

    /// Persist a layout edited in the canvas and re-publish it.
    func commitLayout(_ layout: PaneLayout) {
        config.saveLayout(layout)
        activeLayout = config.activeLayout
    }

    func selectLayout(_ id: UUID) {
        config.selectLayout(id)
        activeLayout = config.activeLayout
        Haptics.selection()
    }

    // MARK: Layout / controls

    func toggleFullscreen(_ id: UUID) {
        guard !editingLayout else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            fullscreenPaneID = (fullscreenPaneID == id) ? nil : id
        }
        Haptics.tap()
    }

    func revealControls() {
        guard !locked else { return }
        withAnimation(.easeOut(duration: 0.25)) { controlsVisible = true }
        scheduleControlsHide()
    }

    func toggleControls() {
        if locked || editingLayout { return }
        if controlsVisible {
            withAnimation(.easeIn(duration: 0.25)) { controlsVisible = false }
            controlsHideWork?.cancel()
        } else {
            revealControls()
        }
    }

    func scheduleControlsHide(after seconds: TimeInterval = 4) {
        guard !editingLayout else { return }
        controlsHideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, !self.locked, !self.editingLayout else { return }
            withAnimation(.easeIn(duration: 0.4)) { self.controlsVisible = false }
        }
        controlsHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func setLocked(_ locked: Bool) {
        self.locked = locked
        if locked { editingLayout = false }
        withAnimation(.easeInOut(duration: 0.3)) {
            controlsVisible = !locked
        }
        if !locked { scheduleControlsHide() }
        Haptics.rigid()
    }

    // MARK: Night mode

    private func startNightTimer() {
        nightTimer?.invalidate()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            self?.evaluateNightMode()
        }
        RunLoop.main.add(timer, forMode: .common)
        nightTimer = timer
    }

    func evaluateNightMode() {
        let hour = Calendar.current.component(.hour, from: Date())
        let active = config.settings.nightMode.isActive(hour: hour)
        if active != nightActive {
            withAnimation { nightActive = active }
        }
    }

    /// Quick toggle: forces night mode on or off (persists to settings).
    func toggleNight() {
        config.settings.nightMode.trigger = nightActive ? .off : .on
        evaluateNightMode()
        Haptics.tap()
    }

    var nightDim: Double { config.settings.nightMode.dim }
    var nightWarmth: Double { config.settings.nightMode.warmth }

    // MARK: Toast

    func showToast(_ message: String) {
        toastWork?.cancel()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { toast = message }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.4)) { self?.toast = nil }
        }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }
}
