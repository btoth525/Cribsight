import Foundation

/// Performs the WHEP SDP exchange against go2rtc: POST our offer, get the answer.
/// Tries the standard `/api/whep` endpoint first, then go2rtc's `/api/webrtc`
/// alias as a fallback.
struct WHEPSignaling {
    /// e.g. `http://192.168.1.50:1984`
    let apiBase: String

    enum SignalingError: LocalizedError {
        case badURL
        case http(Int)
        case empty
        case network(String)

        var errorDescription: String? {
            switch self {
            case .badURL: return "Invalid server address."
            case .http(let code): return "Server returned HTTP \(code)."
            case .empty: return "Server returned an empty answer."
            case .network(let msg): return msg
            }
        }
    }

    func exchange(offer: String,
                  streamName: String,
                  completion: @escaping (Result<String, Error>) -> Void) {
        post(path: "/api/whep", offer: offer, src: streamName) { result in
            switch result {
            case .success:
                completion(result)
            case .failure:
                // Fall back to go2rtc's WebRTC alias endpoint.
                self.post(path: "/api/webrtc", offer: offer, src: streamName, completion: completion)
            }
        }
    }

    private func post(path: String,
                      offer: String,
                      src: String,
                      completion: @escaping (Result<String, Error>) -> Void) {
        guard var comps = URLComponents(string: apiBase + path) else {
            completion(.failure(SignalingError.badURL)); return
        }
        comps.queryItems = [URLQueryItem(name: "src", value: src)]
        guard let url = comps.url else {
            completion(.failure(SignalingError.badURL)); return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
        request.setValue("application/sdp", forHTTPHeaderField: "Accept")
        request.httpBody = offer.data(using: .utf8)
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(SignalingError.network(error.localizedDescription))); return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(SignalingError.empty)); return
            }
            guard (200..<300).contains(http.statusCode) else {
                completion(.failure(SignalingError.http(http.statusCode))); return
            }
            guard let data = data,
                  let sdp = String(data: data, encoding: .utf8),
                  sdp.contains("v=0") else {
                completion(.failure(SignalingError.empty)); return
            }
            completion(.success(sdp))
        }.resume()
    }
}
