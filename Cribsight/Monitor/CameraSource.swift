import Foundation
import Combine

/// One physical camera: a single WebRTC connection feeding a shared `FrameSink`,
/// plus its audio, cry detection, stats and reconnection. Several `PaneViewModel`s
/// (layout slots) can share one source, so a fisheye stream is decoded once and
/// rendered into many independently-aimed panes.
final class CameraSource: ObservableObject, Identifiable {
    let id: UUID

    @Published private(set) var camera: CameraSettings
    @Published private(set) var connectionState: PaneConnectionState = .idle
    @Published private(set) var stats = PaneStats()
    @Published private(set) var isMuted: Bool
    @Published private(set) var cryActive = false

    /// Shared decoded-frame source. Renderers read `latest` from here.
    let sink = FrameSink()

    /// Called (with the camera display name) when a cry/sound alert fires.
    var onCry: ((String) -> Void)?

    private var connection: ConnectionSettings
    private let tokenProvider: () -> String?
    private var cryAlertsEnabled: Bool
    private var cryChimeEnabled: Bool

    private var client: WebRTCClient?
    private var reconnect: ReconnectController?
    private var statsMonitor: StatsMonitor?
    private let cryDetector = CryDetector()
    private(set) var isRunning = false

    init(camera: CameraSettings,
         connection: ConnectionSettings,
         tokenProvider: @escaping () -> String?,
         cryAlertsEnabled: Bool,
         cryChimeEnabled: Bool) {
        self.id = camera.id
        self.camera = camera
        self.isMuted = camera.startMuted
        self.connection = connection
        self.tokenProvider = tokenProvider
        self.cryAlertsEnabled = cryAlertsEnabled
        self.cryChimeEnabled = cryChimeEnabled
        self.cryDetector.sensitivity = camera.crySensitivity

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

        let signaling = SignalingProvider(connection: connection,
                                          tokenProvider: tokenProvider).make()
        let client = WebRTCClient(streamName: camera.streamName,
                                  startMuted: isMuted,
                                  signaling: signaling)
        client.add(renderer: sink)
        client.onStateChange = { [weak self] state in
            guard let self = self else { return }
            self.connectionState = state
            self.reconnect?.noteState(state)
        }

        let reconnect = ReconnectController(client: client)
        reconnect.lastFrameAge = { [weak self] in self?.sink.ageSeconds ?? .infinity }

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

    // MARK: Config

    func updateConfig(camera: CameraSettings, connection: ConnectionSettings,
                      cryAlertsEnabled: Bool, cryChimeEnabled: Bool) {
        let needsReconnect = camera.streamName != self.camera.streamName || connection != self.connection
        self.camera = camera
        self.connection = connection
        self.cryAlertsEnabled = cryAlertsEnabled
        self.cryChimeEnabled = cryChimeEnabled
        self.cryDetector.sensitivity = camera.crySensitivity
        if needsReconnect && isRunning {
            stop()
            start()
        }
    }
}
