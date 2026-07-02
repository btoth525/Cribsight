import Foundation
import WebRTC

/// go2rtc WebSocket signaling, used in Frigate mode because Frigate proxies
/// go2rtc's `/api/ws` (at `/live/webrtc/api/ws`) but **not** the WHEP endpoint.
///
/// Flow: open the socket (with the Frigate JWT as a bearer token + cookie) →
/// send `{"type":"webrtc/offer"}` → read back `{"type":"webrtc/answer"}` (plus
/// any trickle `webrtc/candidate` messages).
final class WebSocketSignaling: NSObject, Signaling {
    private let wsBase: String
    /// Read fresh on each exchange so reconnects use a refreshed Frigate token.
    private let tokenProvider: () -> String?

    private var task: URLSessionWebSocketTask?
    private var completion: ((Result<String, Error>) -> Void)?
    private var onRemoteCandidate: ((RTCIceCandidate) -> Void)?
    private var answered = false
    private var timeoutTimer: Timer?
    /// Bumped on every exchange/cancel (main thread only). Late callbacks from a
    /// cancelled socket carry the old generation, so they can never resolve — or
    /// fail — the exchange that replaced them.
    private var generation = 0

    init(wsBase: String, tokenProvider: @escaping () -> String?) {
        self.wsBase = wsBase
        self.tokenProvider = tokenProvider
    }

    func exchange(offer: String,
                  streamName: String,
                  onRemoteCandidate: @escaping (RTCIceCandidate) -> Void,
                  completion: @escaping (Result<String, Error>) -> Void) {
        // Reset one-shot state so the same instance works across reconnects.
        // (Called from the client's main-thread signaling flow.)
        generation += 1
        let gen = generation
        answered = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        self.completion = completion
        self.onRemoteCandidate = onRemoteCandidate

        guard var comps = URLComponents(string: wsBase + "/live/webrtc/api/ws") else {
            resolve(gen, .failure(SignalingError.badURL)); return
        }
        comps.queryItems = [URLQueryItem(name: "src", value: streamName)]
        guard let url = comps.url else { resolve(gen, .failure(SignalingError.badURL)); return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        if let token = tokenProvider(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("frigate_token=\(token)", forHTTPHeaderField: "Cookie")
        }

        let task = URLSession.shared.webSocketTask(with: request)
        self.task = task
        task.resume()
        receiveLoop(gen)
        send(["type": "webrtc/offer", "value": offer], gen)

        DispatchQueue.main.async { [weak self] in
            guard let self, gen == self.generation else { return }
            self.timeoutTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in
                self?.resolve(gen, .failure(SignalingError.empty))
            }
        }
    }

    func cancel() {
        generation += 1
        DispatchQueue.main.async { [weak self] in
            self?.timeoutTimer?.invalidate(); self?.timeoutTimer = nil
        }
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    // MARK: - Internals

    private func send(_ obj: [String: Any], _ gen: Int) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let str = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(str)) { [weak self] error in
            if let error = error {
                self?.resolve(gen, .failure(SignalingError.network(error.localizedDescription)))
            }
        }
    }

    private func receiveLoop(_ gen: Int) {
        task?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                self.resolve(gen, .failure(SignalingError.network(error.localizedDescription)))
            case .success(let message):
                self.handle(message, gen)
                self.receiveLoop(gen)
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message, _ gen: Int) {
        let text: String?
        switch message {
        case .string(let s): text = s
        case .data(let d): text = String(data: d, encoding: .utf8)
        @unknown default: text = nil
        }
        guard let text,
              let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }

        switch type {
        case "webrtc/answer":
            if let sdp = obj["value"] as? String { resolve(gen, .success(sdp)) }
        case "webrtc/candidate":
            if let cand = obj["value"] as? String, !cand.isEmpty {
                let candidate = RTCIceCandidate(sdp: cand, sdpMLineIndex: 0, sdpMid: nil)
                DispatchQueue.main.async { [weak self] in
                    guard let self, gen == self.generation else { return }
                    self.onRemoteCandidate?(candidate)
                }
            }
        case "error":
            resolve(gen, .failure(SignalingError.network((obj["value"] as? String) ?? "go2rtc error")))
        default:
            break
        }
    }

    /// Resolves the offer/answer exchange exactly once. The socket stays open
    /// after a successful answer so late trickle candidates still arrive; it's
    /// closed by `cancel()` when the client tears down. Runs on main so the
    /// receive thread and the timeout timer can't both fire it (double
    /// completion), and drops callbacks from a superseded exchange.
    private func resolve(_ gen: Int, _ result: Result<String, Error>) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, gen == self.generation, !self.answered else { return }
            self.answered = true
            self.timeoutTimer?.invalidate(); self.timeoutTimer = nil
            let done = self.completion
            self.completion = nil
            done?(result)
        }
    }
}
