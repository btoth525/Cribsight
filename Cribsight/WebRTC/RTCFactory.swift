import Foundation
import WebRTC

/// Shared WebRTC peer-connection factory. Creating the factory is expensive and
/// libwebrtc expects a single instance per process, so we keep one.
enum RTCFactory {
    static let shared: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let encoder = RTCDefaultVideoEncoderFactory()
        let decoder = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: encoder, decoderFactory: decoder)
    }()
}

/// UI-facing connection state for a single camera pane.
enum PaneConnectionState: Equatable {
    case idle
    case connecting
    case live
    case reconnecting
    case failed(String)

    var isLive: Bool { if case .live = self { return true } else { return false } }

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .connecting: return "Connecting…"
        case .live: return "Live"
        case .reconnecting: return "Reconnecting…"
        case .failed: return "Offline"
        }
    }
}
