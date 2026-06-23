import Foundation
import QuartzCore

/// Detects sustained loud audio (a crying baby / room noise) from the WebRTC
/// audio level, with smoothing + hysteresis so brief blips don't trigger it and
/// it doesn't flicker on the boundary.
///
/// `audioLevel` from WebRTC inbound-rtp is roughly 0…1 but usually small; the
/// trigger threshold is derived from the user's per-camera sensitivity and can
/// be tuned in Settings.
final class CryDetector {
    /// 0 = least sensitive (only very loud), 1 = most sensitive.
    var sensitivity: Double = 0.6
    var onActiveChanged: ((Bool) -> Void)?

    private(set) var isActive = false
    private var smoothed: Double = 0
    private var aboveSince: CFTimeInterval?
    private var belowSince: CFTimeInterval?

    private let attack: CFTimeInterval = 0.5   // sustained-loud time before triggering
    private let release: CFTimeInterval = 2.5  // sustained-quiet time before clearing

    func reset() {
        smoothed = 0
        aboveSince = nil
        belowSince = nil
        if isActive {
            isActive = false
            onActiveChanged?(false)
        }
    }

    func ingest(level: Double) {
        smoothed = smoothed * 0.82 + max(0, level) * 0.18

        // More sensitive → lower trigger threshold.
        let high = lerp(0.22, 0.03, sensitivity)
        let low = high * 0.55
        let now = CACurrentMediaTime()

        if smoothed >= high {
            belowSince = nil
            if aboveSince == nil { aboveSince = now }
            if !isActive, let since = aboveSince, now - since >= attack {
                isActive = true
                onActiveChanged?(true)
            }
        } else if smoothed <= low {
            aboveSince = nil
            if isActive {
                if belowSince == nil { belowSince = now }
                if let since = belowSince, now - since >= release {
                    isActive = false
                    onActiveChanged?(false)
                }
            }
        } else {
            aboveSince = nil
            belowSince = nil
        }
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * min(max(t, 0), 1)
    }
}
