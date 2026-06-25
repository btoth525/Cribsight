import Foundation
import Combine

/// Connection to the Owlet → RTSP bridge's sensor API (separate from Frigate).
/// The bridge serves live sock + room vitals at `GET http://host:port/api/vitals`.
struct OwletBridgeSettings: Codable, Equatable {
    // Pre-set for this nursery's bridge so it works out of the box; all editable
    // in Settings → Owlet bridge.
    var enabled: Bool = true
    var host: String = "192.168.1.204"
    /// REST API port (/api/vitals, /api/talk, /api/sounds…). Direct, not remapped.
    var vitalsPort: Int = 8088
    /// go2rtc control/WHEP port for direct video. The bridge's Docker maps host
    /// 1985 → container 1984, so the reachable port is 1985.
    var controlPort: Int = 1985

    var hostTrimmed: String { host.trimmingCharacters(in: .whitespaces) }
    var isComplete: Bool { enabled && !hostTrimmed.isEmpty }
    var vitalsURL: String { "http://\(hostTrimmed):\(vitalsPort)/api/vitals" }
}

/// Sensor values for one device (sock or cam). Every field is optional — the sock
/// reports null while charging / off-foot. Parsed with lenient coercion.
struct Vitals: Equatable {
    // Sock
    var heartRate: Int?        // bpm
    var oxygen: Int?           // SpO2 %
    var oxygenAvg: Int?        // SpO2 % (10-min avg)
    var skinTemp: Double?      // °F (bridge default)
    var sleepCode: Int?        // 1=awake, 8=light, 15=deep, 0=unknown
    var movement: Int?
    var battery: Int?          // %
    var batteryMinutes: Int?
    var signalStrength: Int?   // dBm
    var baseStationOn: Bool?
    var charging: Bool?
    // Room / camera
    var roomTemp: Double?       // °F
    var humidity: Double?       // % RH
    var noise: Double?          // dB
    var brightness: Double?     // lux
    var motion: Bool?
    var sound: Bool?
    var wifiRSSI: Int?          // dBm

    var sockActive: Bool { heartRate != nil || oxygen != nil }

    var sleepLabel: String? {
        switch sleepCode {
        case 1: return "Awake"
        case 8: return "Light sleep"
        case 15: return "Deep sleep"
        default: return nil
        }
    }

    /// Short form for the compact HUD ("Awake" / "Light" / "Deep").
    var sleepShort: String? {
        switch sleepCode {
        case 1: return "Awake"
        case 8: return "Light"
        case 15: return "Deep"
        default: return nil
        }
    }

    /// Overlay room/camera sensors (temp, humidity, noise, brightness…) from the
    /// bridge cam device onto these sock vitals, so one HUD can show both the baby's
    /// vitals and the nursery's environment.
    func merging(room: Vitals?) -> Vitals {
        guard let room else { return self }
        var v = self
        v.roomTemp   = room.roomTemp ?? v.roomTemp
        v.humidity   = room.humidity ?? v.humidity
        v.noise      = room.noise ?? v.noise
        v.brightness = room.brightness ?? v.brightness
        v.motion     = room.motion ?? v.motion
        v.sound      = room.sound ?? v.sound
        v.wifiRSSI   = room.wifiRSSI ?? v.wifiRSSI
        return v
    }

    init() {}

    init(sensors d: [String: Any]) {
        heartRate      = Coerce.int(d["heart_rate"])
        oxygen         = Coerce.int(d["oxygen"])
        oxygenAvg      = Coerce.int(d["oxygen_avg"])
        skinTemp       = Coerce.double(d["skin_temperature"])
        sleepCode      = Coerce.int(d["sleep_state"])
        movement       = Coerce.int(d["movement"])
        battery        = Coerce.int(d["battery"])
        batteryMinutes = Coerce.int(d["battery_minutes"])
        signalStrength = Coerce.int(d["signal_strength"])
        baseStationOn  = Coerce.bool(d["base_station_on"])
        charging       = Coerce.bool(d["charging"])
        roomTemp       = Coerce.double(d["temperature"])
        humidity       = Coerce.double(d["humidity"])
        noise          = Coerce.double(d["noise"])
        brightness     = Coerce.double(d["brightness"])
        motion         = Coerce.bool(d["motion"])
        sound          = Coerce.bool(d["sound"])
        wifiRSSI       = Coerce.int(d["wifi_rssi"])
    }
}

/// One device from `/api/vitals` (`kind` is "sock", "cam", or "device").
struct VitalsDevice: Equatable, Identifiable {
    var id: String { dsn }
    let dsn: String
    let name: String
    let kind: String
    let model: String?
    let sensors: Vitals

    var isSock: Bool { kind == "sock" }
    var isCamera: Bool { kind == "cam" }
}

/// A full `/api/vitals` response: all paired devices at one moment.
struct VitalsSnapshot: Equatable {
    let devices: [VitalsDevice]

    var socks: [VitalsDevice] { devices.filter { $0.isSock } }
    var cameras: [VitalsDevice] { devices.filter { $0.isCamera } }

    func device(dsn: String?) -> VitalsDevice? {
        guard let dsn else { return nil }
        return devices.first { $0.dsn == dsn }
    }

    init(devices: [VitalsDevice]) { self.devices = devices }

    init(json: [String: Any]) {
        let raw = (json["devices"] as? [[String: Any]]) ?? []
        devices = raw.map { d in
            let sensorDict = (d["sensors"] as? [String: Any]) ?? [:]
            return VitalsDevice(
                dsn: (d["dsn"] as? String) ?? (d["name"] as? String) ?? UUID().uuidString,
                name: (d["name"] as? String) ?? "device",
                kind: VitalsSnapshot.normalizedKind(d["kind"] as? String,
                                                    model: d["model"] as? String,
                                                    sensors: sensorDict),
                model: d["model"] as? String,
                sensors: Vitals(sensors: sensorDict)
            )
        }
    }

    /// The bridge labels the sock `kind:"device"` (model e.g. "SS3-Sleep"), so
    /// normalize to "sock"/"cam"/"device" using the reported kind, model, and which
    /// sensors are present.
    static func normalizedKind(_ kind: String?, model: String?, sensors: [String: Any]) -> String {
        if kind == "cam" { return "cam" }
        if kind == "sock" { return "sock" }
        if sensors.keys.contains("heart_rate")
            || sensors.keys.contains("oxygen")
            || sensors.keys.contains("sleep_state") { return "sock" }
        let m = (model ?? "").lowercased()
        if m.contains("sleep") || m.contains("sock") { return "sock" }
        return kind ?? "device"
    }
}

/// Lenient value coercion (the bridge may send Int / Double / String / 0-1).
enum Coerce {
    static func int(_ v: Any?) -> Int? {
        switch v {
        case let n as Int: return n
        case let d as Double: return d.isFinite ? Int(d.rounded()) : nil
        case let n as NSNumber: return n.intValue
        case let s as String:
            if let i = Int(s) { return i }
            if let d = Double(s), d.isFinite { return Int(d.rounded()) }
            return nil
        default: return nil
        }
    }
    static func double(_ v: Any?) -> Double? {
        switch v {
        case let d as Double: return d.isFinite ? d : nil
        case let n as Int: return Double(n)
        case let n as NSNumber: return n.doubleValue.isFinite ? n.doubleValue : nil
        case let s as String: return Double(s).flatMap { $0.isFinite ? $0 : nil }
        default: return nil
        }
    }
    static func bool(_ v: Any?) -> Bool? {
        switch v {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        case let n as Int: return n != 0
        case let s as String: return ["true", "1", "on", "yes"].contains(s.lowercased())
        default: return nil
        }
    }
}

/// Polls the Owlet bridge's `/api/vitals` and publishes the latest snapshot plus a
/// short rolling history for the in-app charts. Shared by the monitor; starts and
/// stops with the app lifecycle.
final class VitalsService: ObservableObject {
    @Published private(set) var snapshot: VitalsSnapshot?
    @Published private(set) var reachable = false
    @Published private(set) var history: [Sample] = []

    struct Sample: Equatable {
        let date: Date
        let snapshot: VitalsSnapshot
    }

    private var settings = OwletBridgeSettings()
    private var timer: Timer?
    private let maxSamples = 600   // ~30 min @ 3s

    /// Discovered sock devices (for the per-camera pairing picker in Settings).
    var socks: [VitalsDevice] { snapshot?.socks ?? [] }

    func device(dsn: String?) -> VitalsDevice? { snapshot?.device(dsn: dsn) }

    /// Apply current bridge settings and start/stop polling to match.
    func update(settings: OwletBridgeSettings) {
        self.settings = settings
        if settings.isComplete { start() } else { stop(clear: true) }
    }

    func start(interval: TimeInterval = 3) {
        guard settings.isComplete else { return }
        timer?.invalidate()
        poll()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop(clear: Bool = false) {
        timer?.invalidate()
        timer = nil
        if clear {
            snapshot = nil
            reachable = false
            history = []
        }
    }

    private func poll() {
        guard let url = URL(string: settings.vitalsURL) else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        URLSession.shared.dataTask(with: req) { [weak self] data, response, _ in
            guard let self = self else { return }
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            let dict = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async {
                self.reachable = ok && dict != nil
                guard let dict else { return }
                let snap = VitalsSnapshot(json: dict)
                self.snapshot = snap
                self.history.append(Sample(date: Date(), snapshot: snap))
                if self.history.count > self.maxSamples {
                    self.history.removeFirst(self.history.count - self.maxSamples)
                }
            }
        }.resume()
    }
}
