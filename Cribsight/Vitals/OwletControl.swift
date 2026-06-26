import Foundation
import AVFoundation

/// Talk + lullaby + sound-library actions against the Owlet bridge REST API
/// (`http://host:8088`). Stateless — built on demand from the bridge settings.
struct OwletControl {
    let base: String   // e.g. http://192.168.1.204:8088

    init?(settings: OwletBridgeSettings) {
        guard settings.isComplete else { return nil }
        base = "http://\(settings.hostTrimmed):\(settings.vitalsPort)"
    }

    /// A sound file in the bridge's library.
    struct Sound: Identifiable, Equatable {
        var id: String { name }
        let name: String          // file name used by /api/play (e.g. "lullaby.mp3")
        let displayName: String
    }

    // MARK: Lullabies / sounds

    /// `GET /api/sounds` — parsed leniently (array of strings, array of objects,
    /// or `{ "sounds": [...] }`).
    func listSounds(completion: @escaping ([Sound]) -> Void) {
        guard let url = URL(string: base + "/api/sounds") else { completion([]); return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let sounds = OwletControl.parseSounds(data)
            DispatchQueue.main.async { completion(sounds) }
        }.resume()
    }

    /// `POST /api/play/<camera>`  body `{"file": "<name>"}` — plays a sound on the
    /// camera speaker.
    func play(camera: String, file: String, completion: @escaping (Bool, String?) -> Void = { _, _ in }) {
        guard let url = URL(string: base + "/api/play/" + encode(camera)) else { completion(false, nil); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["file": file])
        send(req, completion)
    }

    /// `DELETE /api/sounds/<name>` (filename is URL-encoded into the path).
    func deleteSound(_ name: String, completion: @escaping (Bool, String?) -> Void = { _, _ in }) {
        guard let url = URL(string: base + "/api/sounds/" + encode(name)) else { completion(false, nil); return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        send(req, completion)
    }

    /// `POST /api/sounds` — multipart upload of a new sound file (field name `file`).
    func uploadSound(filename: String, data: Data, mime: String,
                     completion: @escaping (Bool, String?) -> Void = { _, _ in }) {
        guard let url = URL(string: base + "/api/sounds") else { completion(false, nil); return }
        let req = multipart(url: url, field: "file", filename: filename, data: data, mime: mime)
        send(req, completion)
    }

    // MARK: Two-way talk

    /// `POST /api/talk/<camera>` — multipart audio clip pushed to the speaker. The
    /// bridge transcodes any ffmpeg-readable input, so AAC/m4a is fine. The form
    /// field name is `audio`. Fails with 409 if the camera stream isn't live yet.
    func talk(camera: String, audio: Data, filename: String, mime: String,
              completion: @escaping (Bool, String?) -> Void = { _, _ in }) {
        guard let url = URL(string: base + "/api/talk/" + encode(camera)) else { completion(false, nil); return }
        let req = multipart(url: url, field: "audio", filename: filename, data: audio, mime: mime)
        send(req, completion)
    }

    /// `POST /api/talk/<camera>/stop`
    func stopTalk(camera: String, completion: @escaping (Bool, String?) -> Void = { _, _ in }) {
        guard let url = URL(string: base + "/api/talk/" + encode(camera) + "/stop") else { completion(false, nil); return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        send(req, completion)
    }

    // MARK: Helpers

    private func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
    }

    /// Run a request; report success plus, on failure, the bridge's own error
    /// message (it returns `{"ok":false,"error":"…"}` for cases like a stream that
    /// isn't live yet) so the UI can show something actionable.
    private func send(_ req: URLRequest, _ completion: @escaping (Bool, String?) -> Void) {
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion(false, error.localizedDescription) }
                return
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let ok = (200..<300).contains(code)
            var message: String?
            if !ok, let data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                message = (obj["error"] as? String) ?? (obj["message"] as? String)
            }
            DispatchQueue.main.async { completion(ok, message) }
        }.resume()
    }

    private func multipart(url: URL, field: String, filename: String, data: Data, mime: String) -> URLRequest {
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        let pre = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(field)\"; filename=\"\(filename)\"\r\nContent-Type: \(mime)\r\n\r\n"
        body.append(Data(pre.utf8))
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        req.httpBody = body
        return req
    }

    static func parseSounds(_ data: Data?) -> [Sound] {
        guard let data, let obj = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let array: [Any]
        if let a = obj as? [Any] { array = a }
        else if let d = obj as? [String: Any], let a = d["sounds"] as? [Any] { array = a }
        else { return [] }
        return array.compactMap { item -> Sound? in
            if let name = item as? String {
                return Sound(name: name, displayName: prettyName(name))
            }
            if let d = item as? [String: Any] {
                let name = (d["file"] as? String) ?? (d["name"] as? String) ?? (d["filename"] as? String)
                guard let name else { return nil }
                let display = (d["name"] as? String) ?? prettyName(name)
                return Sound(name: name, displayName: display)
            }
            return nil
        }
    }

    static func prettyName(_ file: String) -> String {
        let base = (file as NSString).deletingPathExtension
        return base.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}

/// Records a short clip from the mic for push-to-talk, then hands back the data.
final class TalkRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?

    func start() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .voiceChat,
                                 options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers])
        try? session.setActive(true)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("talk-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        recorder = try? AVAudioRecorder(url: url, settings: settings)
        fileURL = url
        if recorder?.record() == true {
            isRecording = true
            Haptics.rigid()
        }
    }

    /// Stops recording and returns the recorded clip (m4a/AAC).
    func stop() -> (data: Data, filename: String, mime: String)? {
        recorder?.stop()
        isRecording = false
        // Restore the shared listen-in playback session.
        AudioController.shared.activate()
        guard let url = fileURL, let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        try? FileManager.default.removeItem(at: url)
        return (data, url.lastPathComponent, "audio/m4a")
    }
}
