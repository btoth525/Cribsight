import Foundation

/// Talks to Frigate's authenticated API (port 8971): logs in for a JWT and
/// lists the cameras/streams. The token is reused as a bearer credential for
/// config requests and handed to `WebSocketSignaling` for the live WebRTC.
final class FrigateClient {
    /// e.g. `https://192.168.1.50:8971`
    let apiBase: String
    private(set) var token: String?

    private let session: URLSession

    init(apiBase: String) {
        self.apiBase = apiBase
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpShouldSetCookies = true
        cfg.timeoutIntervalForRequest = 12
        self.session = URLSession(configuration: cfg)
    }

    var isLoggedIn: Bool { token != nil }

    func login(username: String, password: String,
               completion: @escaping (Result<Void, Error>) -> Void) {
        guard let url = URL(string: apiBase + "/api/login") else {
            completion(.failure(SignalingError.badURL)); return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["user": username, "password": password])

        session.dataTask(with: req) { [weak self] _, response, error in
            guard let self = self else { return }
            if let error = error {
                completion(.failure(SignalingError.network(error.localizedDescription))); return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(SignalingError.empty)); return
            }
            guard (200..<300).contains(http.statusCode) else {
                completion(.failure(http.statusCode == 401 ? SignalingError.auth
                                                            : SignalingError.http(http.statusCode)))
                return
            }
            self.token = self.extractToken(from: http, url: url)
            completion(.success(()))
        }.resume()
    }

    /// Camera/stream names from the authenticated config. We prefer go2rtc stream
    /// keys (the ones playable over WebRTC), falling back to the camera list.
    func streamNames(completion: @escaping (Result<[String], Error>) -> Void) {
        guard let url = URL(string: apiBase + "/api/config") else {
            completion(.failure(SignalingError.badURL)); return
        }
        var req = URLRequest(url: url)
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        session.dataTask(with: req) { data, response, error in
            if let error = error {
                completion(.failure(SignalingError.network(error.localizedDescription))); return
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                completion(.failure(http.statusCode == 401 ? SignalingError.auth
                                                           : SignalingError.http(http.statusCode)))
                return
            }
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(SignalingError.empty)); return
            }
            var names: [String] = []
            if let go2 = obj["go2rtc"] as? [String: Any],
               let streams = go2["streams"] as? [String: Any] {
                names = Array(streams.keys)
            }
            if names.isEmpty, let cams = obj["cameras"] as? [String: Any] {
                names = Array(cams.keys)
            }
            // Collapse a camera's secondary/sub feeds so each camera shows once.
            names = FrigateClient.collapseSubStreams(names)
            names.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            completion(.success(names))
        }.resume()
    }

    /// Collapse secondary/sub streams: if both "X" and "X_sub" exist, drop the
    /// "X_sub" so each physical camera is represented once.
    static func collapseSubStreams(_ keys: [String]) -> [String] {
        let set = Set(keys)
        let suffixes = ["_sub", "_substream", "_lowres", "_low", "_lq", "_sd",
                        "_secondary", "_record", "_detect", "_audio", "_mini", "_2"]
        return keys.filter { key in
            !suffixes.contains { suf in
                key.lowercased().hasSuffix(suf) && set.contains(String(key.dropLast(suf.count)))
            }
        }
    }

    private func extractToken(from http: HTTPURLResponse, url: URL) -> String? {
        if let fields = http.allHeaderFields as? [String: String] {
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
            if let jwt = cookies.first(where: { $0.name == "frigate_token" })?.value { return jwt }
        }
        return session.configuration.httpCookieStorage?.cookies?
            .first(where: { $0.name == "frigate_token" })?.value
    }
}
