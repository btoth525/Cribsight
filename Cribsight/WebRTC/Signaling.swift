import Foundation
import WebRTC

/// Abstracts the offer/answer exchange so `WebRTCClient` doesn't care whether it
/// talks to go2rtc over WHEP (direct mode) or over go2rtc's WebSocket signaling
/// proxied by Frigate's authenticated port (Frigate mode).
protocol Signaling: AnyObject {
    /// Send our local `offer` for `streamName`, get back the remote answer SDP.
    /// `onRemoteCandidate` may fire for trickle ICE (WebSocket transport); WHEP
    /// embeds candidates in the answer and never calls it.
    func exchange(offer: String,
                  streamName: String,
                  onRemoteCandidate: @escaping (RTCIceCandidate) -> Void,
                  completion: @escaping (Result<String, Error>) -> Void)
    func cancel()
}

enum SignalingError: LocalizedError {
    case badURL
    case http(Int)
    case empty
    case auth
    case network(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid server address."
        case .http(let code): return "Server returned HTTP \(code)."
        case .empty: return "Server returned an empty answer."
        case .auth: return "Login required or token expired."
        case .network(let msg): return msg
        }
    }
}

/// Builds the right `Signaling` for the current connection mode.
struct SignalingProvider {
    let connection: ConnectionSettings
    /// Latest Frigate JWT (nil in direct mode / before login).
    let tokenProvider: () -> String?

    func make() -> Signaling {
        switch connection.mode {
        case .go2rtc:
            return WHEPSignaling(apiBase: connection.apiBase)
        case .frigate:
            return WebSocketSignaling(wsBase: connection.wsBase,
                                      tokenProvider: tokenProvider)
        }
    }
}
