import Foundation
import SwiftUI
import UIKit
import Combine

/// Top-level monitor state: per-camera sources, per-slot panes for the active
/// layout, Frigate login, fullscreen, kiosk lock, control auto-hide, night mode
/// and toasts.
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

    /// One source per distinct camera used by the active layout.
    private var sources: [UUID: CameraSource] = [:]
    /// Frigate auth session (nil in Direct mode).
    private var frigateClient: FrigateClient?
    private lazy var tokenProvider: () -> String? = { [weak self] in self?.frigateClient?.token }

    private var nightTimer: Timer?
    private var controlsHideWork: DispatchWorkItem?
    private var toastWork: DispatchWorkItem?

    init(config: AppConfig) {
        self.config = config
        self.activeLayout = config.activeLayout
        rebuildPanes()
        evaluateNightMode()
    }

    func pane(forSlot slotID: UUID) -> PaneViewModel? {
        panes.first { $0.id == slotID }
    }

    var fisheyePanes: [PaneViewModel] { panes.filter { $0.camera.isFisheye } }

    // MARK: Lifecycle

    func start() {
        AudioController.shared.activate()
        UIApplication.shared.isIdleTimerDisabled = config.settings.keepAwake
        connectThenStartSources()
        startNightTimer()
        scheduleControlsHide()
    }

    func stop() {
        sources.values.forEach { $0.stop() }
        nightTimer?.invalidate(); nightTimer = nil
        UIApplication.shared.isIdleTimerDisabled = false
        AudioController.shared.deactivate()
    }

    func pauseForBackground() {
        sources.values.forEach { $0.stop() }
        nightTimer?.invalidate(); nightTimer = nil
    }

    func resumeFromForeground() {
        guard config.settings.hasCompletedOnboarding, config.isConfigured else { return }
        AudioController.shared.activate()
        UIApplication.shared.isIdleTimerDisabled = config.settings.keepAwake
        connectThenStartSources()
        startNightTimer()
        evaluateNightMode()
    }

    /// In Frigate mode, log in for a JWT before starting the sources (their
    /// WebSocket signaling reads the token via `frigateClient`). Direct mode
    /// starts immediately. `CameraSource.start()` is guarded against double-start.
    private func connectThenStartSources() {
        guard config.settings.connection.mode == .frigate else {
            sources.values.forEach { $0.start() }
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
                    self.sources.values.forEach { $0.start() }
                case .failure(let error):
                    self.showToast("Frigate login failed · \(error.localizedDescription)")
                }
            }
        }
    }

    private func startIdleSources() {
        if config.settings.connection.mode == .frigate && frigateClient?.token == nil {
            connectThenStartSources()
        } else {
            sources.values.forEach { if !$0.isRunning { $0.start() } }
        }
    }

    // MARK: Sources & panes

    /// Create/refresh/remove `CameraSource`s so exactly the cameras used by the
    /// active layout have a live connection.
    private func ensureSources() {
        let conn = config.settings.connection
        let neededIDs = Set(config.activeLayout.slots.map { $0.cameraID })

        for (id, source) in sources where !neededIDs.contains(id) {
            source.stop()
            sources[id] = nil
        }
        for id in neededIDs {
            guard let cam = config.camera(for: id) else { continue }
            if let existing = sources[id] {
                existing.updateConfig(camera: cam, connection: conn,
                                      cryAlertsEnabled: config.settings.cryAlertsEnabled,
                                      cryChimeEnabled: config.settings.cryChimeEnabled)
            } else {
                let source = CameraSource(camera: cam, connection: conn, tokenProvider: tokenProvider,
                                          cryAlertsEnabled: config.settings.cryAlertsEnabled,
                                          cryChimeEnabled: config.settings.cryChimeEnabled)
                source.onCry = { [weak self] name in self?.showToast("Sound detected · \(name)") }
                sources[id] = source
            }
        }
    }

    /// Rebuild the per-slot panes to match the active layout, reusing sources and
    /// (when the slot set is unchanged) the existing panes.
    func rebuildPanes() {
        ensureSources()
        let existing = Dictionary(panes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        panes = config.activeLayout.slots.compactMap { slot in
            guard let source = sources[slot.cameraID] else { return nil }
            // Reuse the pane for this slot if its camera is unchanged, so the
            // Metal view and current aim survive add/remove of other panes.
            if let pane = existing[slot.id], pane.source.id == slot.cameraID {
                return pane
            }
            let pane = PaneViewModel(slotID: slot.id, source: source, initialView: slot.view)
            pane.onAimChanged = { [weak self] sid, view in
                self?.persistSlotAim(slotID: sid, view: view)
            }
            return pane
        }
        activeLayout = config.activeLayout
    }

    /// Apply edited settings coming back from the Settings sheet.
    func applySettingsChange() {
        rebuildPanes()
        connectThenStartSources()
        UIApplication.shared.isIdleTimerDisabled = config.settings.keepAwake
        evaluateNightMode()
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

    /// Persist a layout edited in the canvas (drag/resize/add/remove) and rebuild
    /// panes if its slot set changed.
    func commitLayout(_ layout: PaneLayout) {
        config.saveLayout(layout)
        rebuildPanes()
        startIdleSources()
    }

    func selectLayout(_ id: UUID) {
        config.selectLayout(id)
        rebuildPanes()
        startIdleSources()
        Haptics.selection()
    }

    /// Save a slot's fisheye framing without rebuilding panes.
    private func persistSlotAim(slotID: UUID, view: SlotView) {
        var layout = config.activeLayout
        guard let i = layout.slots.firstIndex(where: { $0.id == slotID }) else { return }
        layout.slots[i].view = view
        config.saveLayout(layout)
        activeLayout = config.activeLayout
    }

    // MARK: Controls

    func toggleFullscreen(_ id: UUID) {
        guard !editingLayout else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            fullscreenPaneID = (fullscreenPaneID == id) ? nil : id
        }
        Haptics.tap()
    }

    func revealControls() {
        withAnimation(.easeOut(duration: 0.25)) { controlsVisible = true }
        scheduleControlsHide()
    }

    func toggleControls() {
        if editingLayout { return }
        // When locked, a tap just briefly re-shows the "Locked" hint, then it fades.
        if locked { revealControls(); return }
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
            guard let self = self, !self.editingLayout else { return }
            withAnimation(.easeIn(duration: 0.4)) { self.controlsVisible = false }
        }
        controlsHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func setLocked(_ locked: Bool) {
        self.locked = locked
        if locked { editingLayout = false }
        // Show the hint/controls briefly, then they fade for a clean full-bleed view.
        withAnimation(.easeInOut(duration: 0.3)) { controlsVisible = true }
        scheduleControlsHide()
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
