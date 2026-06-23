import Foundation
import Combine

/// Queries go2rtc's `/api/streams` endpoint so the user can pick a camera by
/// name instead of typing it. Works against a standalone go2rtc **or** the one
/// embedded in Frigate (API on port 1984 by default).
///
/// Frigate keeps a single connection open to each physical camera and fans it
/// out to detection, recording, and any WebRTC client — so pointing Cribsight
/// here adds zero extra load on the cameras.
struct StreamDiscovery {
    /// e.g. `http://192.168.1.50:1984`
    let apiBase: String

    enum DiscoveryError: LocalizedError {
        case badURL
        case http(Int)
        case decode
        case network(String)

        var errorDescription: String? {
            switch self {
            case .badURL: return "That server address doesn't look right."
            case .http(let code):
                if code == 404 {
                    return "No go2rtc API here (HTTP 404). On Frigate, expose port 1984."
                }
                return "Server returned HTTP \(code)."
            case .decode: return "Couldn't read the stream list from go2rtc."
            case .network(let msg): return msg
            }
        }
    }

    func loadStreamNames(completion: @escaping (Result<[String], Error>) -> Void) {
        guard let url = URL(string: apiBase + "/api/streams") else {
            completion(.failure(DiscoveryError.badURL)); return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(DiscoveryError.network(error.localizedDescription))); return
            }
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                completion(.failure(DiscoveryError.http(http.statusCode))); return
            }
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(DiscoveryError.decode)); return
            }
            // go2rtc returns a JSON object keyed by stream name.
            let names = obj.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            completion(.success(names))
        }.resume()
    }
}

/// Observable state for the "Connect & find cameras" UI shared by onboarding and
/// settings. Holds the discovered stream names plus a simple load state.
final class StreamCatalog: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded([String])
        case failed(String)
    }

    @Published private(set) var state: LoadState = .idle

    /// Discovered stream names (empty until a successful load).
    var names: [String] {
        if case .loaded(let names) = state { return names }
        return []
    }

    var isLoading: Bool { state == .loading }

    func discover(apiBase: String) {
        state = .loading
        StreamDiscovery(apiBase: apiBase).loadStreamNames { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let names): self?.state = .loaded(names)
                case .failure(let error): self?.state = .failed(error.localizedDescription)
                }
            }
        }
    }

    func reset() { state = .idle }
}
