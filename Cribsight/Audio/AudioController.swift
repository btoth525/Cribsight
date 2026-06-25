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
        let session = AVAudioSession.sharedInstance()
        do {
            // Mix with other audio so a white-noise / sound-machine app keeps
            // playing while you listen in (don't duck it for hours).
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // Non-fatal; video still works without audio.
        }
        installObservers()
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
        if type == .ended {
            try? AVAudioSession.sharedInstance().setActive(true)
        }
    }

    @objc private func handleRouteChange(_ note: Notification) {
        // Re-assert the session after the route changes (headphones, etc.).
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}
