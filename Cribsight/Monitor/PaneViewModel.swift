import Foundation
import SwiftUI
import UIKit

/// Drives a single camera pane: owns the WebRTC client, the Metal renderer,
/// stats, reconnection and cry detection, and publishes UI state.
final class PaneViewModel: ObservableObject, Identifiable {
    let id: UUID

    @Published var camera: CameraSettings
    @Published private(set) var connectionState: PaneConnectionState = .idle
    @Published private(set) var stats = PaneStats()
    @Published private(set) var isMuted: Bool
    @Published private(set) var cryActive = false
    @Published var orientation: ViewOrientation
    @Published var mode: FisheyeProjectionMode

    /// Owned here so it survives SwiftUI view rebuilds.
    let renderer = DewarpRenderer()

    /// Called (with the camera display name) when a cry/sound alert fires.
    var onCry: ((String) -> Void)?

    private var client: WebRTCClient?
    private var reconnect: ReconnectController?
    private var statsMonitor: StatsMonitor?
    private let cryDetector = CryDetector()

    private var apiBase: String
    private var cryAlertsEnabled: Bool
    private var cryChimeEnabled: Bool
    private(set) var isRunning = false

    init(camera: CameraSettings, apiBase: String, cryAlertsEnabled: Bool, cryChimeEnabled: Bool) {
        self.id = camera.id
        self.camera = camera
        self.isMuted = camera.startMuted
        self.orientation = camera.dewarp.defaultOrientation
        self.mode = camera.dewarp.mode
        self.apiBase = apiBase
        self.cryAlertsEnabled = cryAlertsEnabled
        self.cryChimeEnabled = cryChimeEnabled
        self.cryDetector.sensitivity = camera.crySensitivity
        updateUniforms()

        cryDetector.onActiveChanged = { [weak self] active in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.cryActive = active
                if active {
                    Haptics.alert()
                    if self.cryChimeEnabled { AudioController.shared.playChime() }
                    self.onCry?(self.camera.displayName)
                }
            }
        }
    }

    // MARK: Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let signaling = WHEPSignaling(apiBase: apiBase)
        let client = WebRTCClient(streamName: camera.streamName,
                                  startMuted: isMuted,
                                  signaling: signaling)
        client.add(renderer: renderer.sink)
        client.onStateChange = { [weak self] state in
            guard let self = self else { return }
            self.connectionState = state
            self.reconnect?.noteState(state)
        }

        let reconnect = ReconnectController(client: client)
        reconnect.lastFrameAge = { [weak self] in self?.renderer.sink.ageSeconds ?? .infinity }

        let stats = StatsMonitor(client: client)
        stats.onUpdate = { [weak self] snapshot in
            guard let self = self else { return }
            self.stats = snapshot
            if self.cryAlertsEnabled && !self.isMuted {
                self.cryDetector.ingest(level: snapshot.audioLevel)
            }
        }

        self.client = client
        self.reconnect = reconnect
        self.statsMonitor = stats

        reconnect.start()
        stats.start()
        client.setMuted(isMuted)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        statsMonitor?.stop()
        reconnect?.stop()
        cryDetector.reset()
        client = nil
        reconnect = nil
        statsMonitor = nil
        connectionState = .idle
    }

    // MARK: Audio

    func toggleMute() {
        setMuted(!isMuted)
        Haptics.tap()
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        client?.setMuted(muted)
        if muted { cryDetector.reset() }
    }

    // MARK: Gestures / framing

    func applyDrag(dx: Float, dy: Float) {
        guard camera.isFisheye else { return }
        if mode == .panorama {
            orientation.pan -= dx
        } else {
            orientation.pan += dx
            orientation.tilt = min(max(orientation.tilt + dy, -1.45), 1.45)
        }
        updateUniforms()
    }

    func applyZoom(_ scale: Float) {
        guard camera.isFisheye else { return }
        orientation.zoom = min(max(orientation.zoom * scale, 0.4), 4.0)
        updateUniforms()
    }

    func apply(preset: ViewPreset) {
        mode = preset.mode
        orientation = preset.orientation
        updateUniforms()
        Haptics.selection()
    }

    func resetView() {
        orientation = camera.dewarp.defaultOrientation
        mode = camera.dewarp.mode
        updateUniforms()
        Haptics.tap()
    }

    func snapshot(size: CGSize) -> UIImage? {
        renderer.snapshot(size: size)
    }

    // MARK: Config updates

    func updateConfig(camera: CameraSettings, apiBase: String, cryAlertsEnabled: Bool, cryChimeEnabled: Bool) {
        let needsReconnect = camera.streamName != self.camera.streamName || apiBase != self.apiBase
        self.camera = camera
        self.apiBase = apiBase
        self.cryAlertsEnabled = cryAlertsEnabled
        self.cryChimeEnabled = cryChimeEnabled
        self.cryDetector.sensitivity = camera.crySensitivity
        updateUniforms()
        if needsReconnect && isRunning {
            stop()
            start()
        }
    }

    private func updateUniforms() {
        renderer.uniforms = DewarpUniformsData.make(isFisheye: camera.isFisheye,
                                                    params: camera.dewarp,
                                                    orientation: orientation,
                                                    mode: mode)
    }
}
