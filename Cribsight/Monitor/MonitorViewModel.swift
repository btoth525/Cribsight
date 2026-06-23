import Foundation
import SwiftUI
import UIKit
import Combine

/// Top-level monitor state: the two panes, layout (fullscreen / swap), kiosk
/// lock, control-bar auto-hide, night-mode evaluation, and transient toasts.
final class MonitorViewModel: ObservableObject {
    @Published private(set) var panes: [PaneViewModel] = []
    @Published var fullscreenPaneID: UUID?
    @Published var swapped = false
    @Published var controlsVisible = true
    @Published var locked = false
    @Published var nightActive = false
    @Published var toast: String?

    let config: AppConfig

    private var nightTimer: Timer?
    private var controlsHideWork: DispatchWorkItem?
    private var toastWork: DispatchWorkItem?

    init(config: AppConfig) {
        self.config = config
        rebuildPanes()
        evaluateNightMode()
    }

    var orderedPanes: [PaneViewModel] {
        guard panes.count == 2, swapped else { return panes }
        return [panes[1], panes[0]]
    }

    // MARK: Lifecycle

    func start() {
        AudioController.shared.activate()
        UIApplication.shared.isIdleTimerDisabled = config.settings.keepAwake
        panes.forEach { $0.start() }
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
        panes.forEach { $0.start() }
        startNightTimer()
        evaluateNightMode()
    }

    // MARK: Panes

    func rebuildPanes() {
        let base = config.apiBase()
        let cams = [config.settings.cameraA, config.settings.cameraB]
        if panes.count == cams.count {
            for (index, cam) in cams.enumerated() {
                panes[index].updateConfig(camera: cam, apiBase: base,
                                          cryAlertsEnabled: config.settings.cryAlertsEnabled,
                                          cryChimeEnabled: config.settings.cryChimeEnabled)
            }
        } else {
            panes.forEach { $0.stop() }
            panes = cams.map { cam in makePane(cam, base: base) }
        }
    }

    private func makePane(_ cam: CameraSettings, base: String) -> PaneViewModel {
        let vm = PaneViewModel(camera: cam, apiBase: base,
                               cryAlertsEnabled: config.settings.cryAlertsEnabled,
                               cryChimeEnabled: config.settings.cryChimeEnabled)
        vm.onCry = { [weak self] name in
            self?.showToast("Sound detected · \(name)")
        }
        return vm
    }

    /// Apply edited settings coming back from the Settings sheet.
    func applySettingsChange() {
        rebuildPanes()
        UIApplication.shared.isIdleTimerDisabled = config.settings.keepAwake
        evaluateNightMode()
    }

    // MARK: Layout / controls

    func toggleFullscreen(_ id: UUID) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            fullscreenPaneID = (fullscreenPaneID == id) ? nil : id
        }
        Haptics.tap()
    }

    func toggleSwap() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { swapped.toggle() }
        Haptics.tap()
    }

    func revealControls() {
        guard !locked else { return }
        withAnimation(.easeOut(duration: 0.25)) { controlsVisible = true }
        scheduleControlsHide()
    }

    func toggleControls() {
        if locked { return }
        if controlsVisible {
            withAnimation(.easeIn(duration: 0.25)) { controlsVisible = false }
            controlsHideWork?.cancel()
        } else {
            revealControls()
        }
    }

    func scheduleControlsHide(after seconds: TimeInterval = 4) {
        controlsHideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, !self.locked else { return }
            withAnimation(.easeIn(duration: 0.4)) { self.controlsVisible = false }
        }
        controlsHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func setLocked(_ locked: Bool) {
        self.locked = locked
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
    /// The scheduled option remains available in Settings.
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
