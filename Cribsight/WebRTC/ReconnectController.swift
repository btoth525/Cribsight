import Foundation

/// Keeps a pane connected: reconnects with exponential backoff on failure and
/// force-reconnects on silent stalls (a "live" connection that stops delivering
/// frames). This is what makes the monitor feel like it "never disconnects".
final class ReconnectController {
    private weak var client: WebRTCClient?

    /// Age, in seconds, of the most recent decoded video frame. Used by the
    /// watchdog. Defaults to "infinitely old".
    var lastFrameAge: () -> TimeInterval = { .infinity }

    var watchdogTimeout: TimeInterval = 8
    var maxBackoff: TimeInterval = 10
    /// Grace before a hard reconnect after a transient ICE drop — WebRTC often
    /// recovers a `.disconnected` pair on its own, so don't tear down instantly.
    var recoveryGrace: TimeInterval = 3

    private(set) var isActive = false
    private var attempt = 0
    /// Consecutive watchdog stalls (live but no frames). Drives a growing backoff so
    /// a stream that connects but never delivers media doesn't thrash live↔off.
    private var stallCount = 0
    private var lastState: PaneConnectionState = .idle
    private var retryTimer: Timer?
    private var watchdogTimer: Timer?

    init(client: WebRTCClient) {
        self.client = client
    }

    /// Begin maintaining the connection.
    func start() {
        guard !isActive else { return }
        isActive = true
        attempt = 0
        stallCount = 0
        client?.connect()
        startWatchdog()
    }

    /// Stop maintaining and tear down.
    func stop() {
        isActive = false
        retryTimer?.invalidate(); retryTimer = nil
        watchdogTimer?.invalidate(); watchdogTimer = nil
        client?.disconnect()
    }

    /// Force an immediate reconnect (e.g. when settings change).
    func reconnectNow() {
        guard isActive else { return }
        attempt = 0
        stallCount = 0
        retryTimer?.invalidate(); retryTimer = nil
        client?.connect()
    }

    /// Feed connection-state changes from the client.
    func noteState(_ state: PaneConnectionState) {
        lastState = state
        switch state {
        case .live:
            attempt = 0
            retryTimer?.invalidate(); retryTimer = nil
        case .failed:
            scheduleReconnect(initialDelay: backoffDelay())
        case .reconnecting:
            // Transient ICE drop: give it a moment to self-heal. If it recovers to
            // .live the retry timer is cancelled before it ever fires.
            scheduleReconnect(initialDelay: max(recoveryGrace, backoffDelay()))
        case .idle, .connecting:
            break
        }
    }

    // MARK: - Private

    private func scheduleReconnect(initialDelay: TimeInterval) {
        guard isActive, retryTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: initialDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.retryTimer = nil
            guard self.isActive else { return }
            self.attempt += 1
            self.client?.connect()
        }
        retryTimer = timer
    }

    private func backoffDelay() -> TimeInterval {
        let base = min(pow(2.0, Double(attempt)) * 0.5, maxBackoff)
        return base + Double.random(in: 0...0.5)
    }

    private func startWatchdog() {
        watchdogTimer?.invalidate()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            guard let self = self, self.isActive else { return }
            // Only police a connection we believe is live; otherwise the backoff
            // path already owns recovery.
            guard self.lastState.isLive else { return }
            if self.lastFrameAge() > self.watchdogTimeout {
                // Live but no frames: a stalled/half-open stream. Grow the backoff
                // with each consecutive stall so we don't flap live↔off forever.
                self.stallCount += 1
                self.attempt = self.stallCount
                self.client?.disconnect()
                self.lastState = .reconnecting
                self.scheduleReconnect(initialDelay: self.backoffDelay())
            } else {
                // Frames are flowing again — genuinely healthy, reset the stall count.
                self.stallCount = 0
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdogTimer = timer
    }
}
