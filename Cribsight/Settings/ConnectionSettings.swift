import Foundation

/// How Cribsight reaches the streams.
enum ConnectionMode: Int, Codable, CaseIterable, Identifiable {
    /// Talk straight to go2rtc's API (no auth) — WHEP on port 1984.
    case go2rtc
    /// Go through Frigate's authenticated port (login → JWT), using go2rtc's
    /// WebSocket signaling that Frigate proxies at `/live/webrtc/api/ws`.
    case frigate

    var id: Int { rawValue }
    var label: String { self == .go2rtc ? "Direct (go2rtc)" : "Frigate login" }
    var blurb: String {
        self == .go2rtc
            ? "Point at go2rtc's API port (1984). No username/password. Lowest-latency, simplest."
            : "Log in to Frigate's authenticated port (8971) with your username/password. Lists your cameras for you."
    }
}

/// Everything needed to reach the server. The Frigate password is **not** stored
/// here — it lives in the Keychain (`Keychain`), keyed by `keychainAccount`.
struct ConnectionSettings: Codable, Equatable {
    var mode: ConnectionMode = .go2rtc
    var host: String = ""
    var useTLS: Bool = false

    /// go2rtc API port (WHEP + `/api/streams`) for Direct mode.
    var go2rtcPort: Int = 1984
    /// Frigate authenticated UI/API port for Frigate mode.
    var frigatePort: Int = 8971
    /// go2rtc WebRTC media port. Informational — it must be reachable on the LAN
    /// for sub-second video in either mode, but the app never connects to it
    /// directly (libwebrtc negotiates it via ICE).
    var webrtcPort: Int = 8555

    /// Frigate username (password is in the Keychain).
    var username: String = ""

    // MARK: Derived

    var scheme: String { useTLS ? "https" : "http" }
    var wsScheme: String { useTLS ? "wss" : "ws" }

    /// The port the API/signaling lives behind for the current mode.
    var apiPort: Int { mode == .frigate ? frigatePort : go2rtcPort }

    var hostTrimmed: String { host.trimmingCharacters(in: .whitespaces) }

    /// `http(s)://host:port` — base for login, config, discovery and WHEP.
    var apiBase: String { "\(scheme)://\(hostTrimmed):\(apiPort)" }

    /// `ws(s)://host:port` — base for go2rtc WebSocket signaling (Frigate mode).
    var wsBase: String { "\(wsScheme)://\(hostTrimmed):\(apiPort)" }

    static let keychainAccount = "frigate.password"

    var isComplete: Bool {
        guard !hostTrimmed.isEmpty else { return false }
        if mode == .frigate {
            return !username.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return true
    }
}
