import SwiftUI

/// Glass settings sheet. Edits the shared `AppConfig`; the monitor re-applies
/// changes when the sheet is dismissed.
struct SettingsView: View {
    @ObservedObject var config: AppConfig
    @StateObject private var catalog = StreamCatalog()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                serverSection
                cameraSection(\.cameraA, title: "Camera A")
                cameraSection(\.cameraB, title: "Camera B (Fisheye)")
                fisheyeSection
                alertsSection
                displaySection
                helpSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    // MARK: Sections

    private var serverSection: some View {
        Section {
            HStack {
                Text("Host")
                Spacer()
                TextField("192.168.1.50", text: $config.settings.serverHost)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }
            HStack {
                Text("Port")
                Spacer()
                TextField("1984", value: $config.settings.serverPort, format: .number.grouping(.never))
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
                    .frame(width: 90)
            }
            Toggle("Use HTTPS / WSS", isOn: $config.settings.useTLS)

            Button {
                Haptics.tap()
                catalog.discover(apiBase: config.apiBase())
            } label: {
                HStack {
                    if catalog.isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                    }
                    Text(catalog.isLoading ? "Connecting…" : "Connect & find cameras")
                }
            }
            .disabled(config.settings.serverHost.trimmingCharacters(in: .whitespaces).isEmpty || catalog.isLoading)

            if catalog.state != .idle {
                DiscoveryStatusLabel(state: catalog.state)
            }
        } header: {
            Text("Frigate / go2rtc Server")
        } footer: {
            Text("Point this at your Frigate box (go2rtc API, normally port 1984) — one connection per camera is reused for every viewer. For WebRTC on your LAN, set `webrtc.candidates: [\"\(config.settings.serverHost.isEmpty ? "<server-ip>" : config.settings.serverHost):8555\"]` in the go2rtc config.")
        }
    }

    private func cameraSection(_ keyPath: WritableKeyPath<AppSettings, CameraSettings>, title: String) -> some View {
        Section(title) {
            HStack {
                Text("Display name")
                Spacer()
                TextField("Name", text: binding(keyPath, \.displayName))
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Text("go2rtc stream")
                Spacer()
                TextField("stream", text: binding(keyPath, \.streamName))
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            if !catalog.names.isEmpty {
                StreamChips(streamName: binding(keyPath, \.streamName), available: catalog.names)
            }
            Toggle("Start muted", isOn: binding(keyPath, \.startMuted))
            VStack(alignment: .leading) {
                Text("Cry sensitivity: \(Int(config.settings[keyPath: keyPath].crySensitivity * 100))%")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Slider(value: binding(keyPath, \.crySensitivity), in: 0...1)
            }
        }
    }

    private var fisheyeSection: some View {
        Section {
            Picker("Default mode", selection: $config.settings.cameraB.dewarp.mode) {
                ForEach(FisheyeProjectionMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            calibrationSlider("Center X", $config.settings.cameraB.dewarp.centerX, 0.3...0.7)
            calibrationSlider("Center Y", $config.settings.cameraB.dewarp.centerY, 0.3...0.7)
            calibrationSlider("Radius", $config.settings.cameraB.dewarp.radius, 0.2...0.7)
            calibrationSlider("Lens FOV°", $config.settings.cameraB.dewarp.lensFOVDegrees, 120...240, fmt: "%.0f")
            calibrationSlider("Zoom FOV°", $config.settings.cameraB.dewarp.outputFOVDegrees, 50...140, fmt: "%.0f")
            calibrationSlider("Pano top°", $config.settings.cameraB.dewarp.panoramaUpDegrees, -20...40, fmt: "%.0f")
            calibrationSlider("Pano bottom°", $config.settings.cameraB.dewarp.panoramaDownDegrees, 40...100, fmt: "%.0f")
            Toggle("Flip horizontally", isOn: $config.settings.cameraB.dewarp.flipHorizontal)
        } header: {
            Text("Fisheye Calibration")
        } footer: {
            Text("Dial these in so the circular image fills the dewarp. Changes apply when you close Settings.")
        }
    }

    private var alertsSection: some View {
        Section("Alerts") {
            Toggle("Cry / sound alerts", isOn: $config.settings.cryAlertsEnabled)
            Toggle("Play a chime on alert", isOn: $config.settings.cryChimeEnabled)
        }
    }

    private var displaySection: some View {
        Section("Display") {
            Toggle("Keep screen awake", isOn: $config.settings.keepAwake)
            Picker("Night mode", selection: $config.settings.nightMode.trigger) {
                ForEach(NightModeTrigger.allCases) { t in
                    Text(t.label).tag(t)
                }
            }
            VStack(alignment: .leading) {
                Text("Dim: \(Int(config.settings.nightMode.dim * 100))%")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                Slider(value: $config.settings.nightMode.dim, in: 0...0.9)
            }
            VStack(alignment: .leading) {
                Text("Warmth: \(Int(config.settings.nightMode.warmth * 100))%")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                Slider(value: $config.settings.nightMode.warmth, in: 0...1)
            }
            if config.settings.nightMode.trigger == .scheduled {
                Stepper("From \(config.settings.nightMode.startHour):00",
                        value: $config.settings.nightMode.startHour, in: 0...23)
                Stepper("Until \(config.settings.nightMode.endHour):00",
                        value: $config.settings.nightMode.endHour, in: 0...23)
            }
        }
    }

    private var helpSection: some View {
        Section {
            Label("Lock the app with iOS Guided Access (triple-click the side button) to use it as a kiosk.",
                  systemImage: "lock.shield")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        } header: {
            Text("Kiosk")
        } footer: {
            Text("Cribsight · v1.0 · LAN-only, no cloud.")
        }
    }

    // MARK: Helpers

    private func calibrationSlider(_ title: String,
                                   _ value: Binding<Float>,
                                   _ range: ClosedRange<Float>,
                                   fmt: String = "%.2f") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(String(format: fmt, value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
            }
            Slider(value: value, in: range)
        }
    }

    private func binding<Value>(_ camera: WritableKeyPath<AppSettings, CameraSettings>,
                                _ field: WritableKeyPath<CameraSettings, Value>) -> Binding<Value> {
        Binding(
            get: { config.settings[keyPath: camera][keyPath: field] },
            set: { config.settings[keyPath: camera][keyPath: field] = $0 }
        )
    }
}
