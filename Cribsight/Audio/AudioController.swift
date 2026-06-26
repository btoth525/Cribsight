import Foundation
import AVFoundation
import AudioToolbox

/// App-wide audio session for listen-in. Uses `.playback` so camera audio is
/// heard even when the device's silent switch is on, and recovers the session
/// after interruptions (e.g. a phone call) and route changes.
final class AudioController {
    static let shared = AudioController()

    private var observersInstalled = false

    private init() {}

    func activate() {
        reactivate(attempt: 0)
        installObservers()
    }

    /// (Re)assert the listen-in session. Retries with backoff because the previous
    /// audio owner (a phone call, Siri, an alarm, another app) may not have fully
    /// released the session yet — without this, an overnight interruption could
    /// leave the monitor silent until someone touches the phone.
    private func reactivate(attempt: Int) {
        let session = AVAudioSession.sharedInstance()
        do {
            // Mix with other audio so a white-noise / sound-machine app keeps
            // playing while you listen in (don't duck it for hours).
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            guard attempt < 4 else { return }
            let delay = 0.25 * pow(2.0, Double(attempt))   // 0.25, 0.5, 1, 2s
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.reactivate(attempt: attempt + 1)
            }
        }
    }

    func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// A short alert tone played when a cry/sound alert fires (if enabled).
    func playChime() {
        AudioServicesPlaySystemSound(1013)
    }

    private func installObservers() {
        guard !observersInstalled else { return }
        observersInstalled = true
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleInterruption(_:)),
                           name: AVAudioSession.interruptionNotification, object: nil)
        center.addObserver(self, selector: #selector(handleRouteChange(_:)),
                           name: AVAudioSession.routeChangeNotification, object: nil)
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        // On .ended iOS may hint .shouldResume, but for a baby monitor we always
        // try to bring listen-in back (with retries) regardless of the hint.
        if type == .ended {
            reactivate(attempt: 0)
        }
    }

    @objc private func handleRouteChange(_ note: Notification) {
        // Re-assert the session after the route changes (headphones unplugged,
        // Bluetooth dropped, etc.), retrying if the new route isn't ready yet.
        reactivate(attempt: 0)
    }
}
