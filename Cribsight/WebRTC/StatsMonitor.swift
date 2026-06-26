import Foundation
import WebRTC

/// Decoded health/audio snapshot for a pane, derived from getStats().
struct PaneStats: Equatable {
    var audioLevel: Double = 0     // 0…1, post jitter-buffer
    var fps: Double = 0
    var bitrateKbps: Double = 0
    var width: Int = 0
    var height: Int = 0

    var resolutionText: String {
        width > 0 && height > 0 ? "\(width)×\(height)" : "—"
    }
}

/// Polls a WebRTCClient's statistics and publishes a decoded `PaneStats`.
/// Drives both the VU meter and cry detection.
final class StatsMonitor {
    private weak var client: WebRTCClient?
    private var timer: Timer?

    var onUpdate: ((PaneStats) -> Void)?

    private var lastBytes: Double = 0
    private var lastTimestampUs: Double = 0
    /// Last published snapshot — carried forward so a poll that omits a field
    /// (common at 5 Hz) doesn't blink fps/resolution to 0 or feed a false-quiet
    /// sample into cry detection.
    private var last = PaneStats()

    init(client: WebRTCClient) {
        self.client = client
    }

    func start(interval: TimeInterval = 0.2) {
        stop()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastBytes = 0
        lastTimestampUs = 0
        last = PaneStats()
    }

    private func poll() {
        client?.statistics { [weak self] report in
            // The stats callback fires on a WebRTC thread; do all `last`/byte-counter
            // work on main so it can't race `stop()` (which resets them on main).
            DispatchQueue.main.async { self?.process(report) }
        }
    }

    private func process(_ report: RTCStatisticsReport) {
        var stats = self.last   // carry forward; only overwrite fields present this tick

            for (_, s) in report.statistics where s.type == "inbound-rtp" {
                let kind = (s.values["kind"] as? String) ?? (s.values["mediaType"] as? String)
                if kind == "audio" {
                    if let level = s.values["audioLevel"] as? Double {
                        stats.audioLevel = level
                    }
                } else if kind == "video" {
                    if let fps = s.values["framesPerSecond"] as? Double { stats.fps = fps }
                    if let w = s.values["frameWidth"] as? Int { stats.width = w }
                    if let h = s.values["frameHeight"] as? Int { stats.height = h }

                    if let bytes = s.values["bytesReceived"] as? Double {
                        let nowUs = report.timestamp_us
                        if self.lastTimestampUs > 0, nowUs > self.lastTimestampUs {
                            let deltaBytes = max(0, bytes - self.lastBytes)
                            let deltaSec = (nowUs - self.lastTimestampUs) / 1_000_000.0
                            if deltaSec > 0 {
                                stats.bitrateKbps = (deltaBytes * 8.0 / 1000.0) / deltaSec
                            }
                        }
                        self.lastBytes = bytes
                        self.lastTimestampUs = nowUs
                    }
                }
            }

        self.last = stats
        self.onUpdate?(stats)
    }
}
