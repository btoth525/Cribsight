import SwiftUI

/// Per-camera settings: identity, stream, audio, cry sensitivity, and — for
/// fisheye cameras — the full dewarp calibration.
struct CameraSettingsView: View {
    @ObservedObject var config: AppConfig
    let cameraID: UUID
    var availableStreams: [String]
    var availableSocks: [VitalsDevice] = []

    private var index: Int? { config.settings.cameras.firstIndex { $0.id == cameraID } }

    var body: some View {
        Form {
            if let idx = index {
                detailSection(idx)
                if config.settings.cameras[idx].isFisheye {
                    fisheyeSection(idx)
                }
                if !availableSocks.isEmpty || config.settings.cameras[idx].owletSockDSN != nil {
                    babyVitalsSection(idx)
                }
            } else {
                Text("This camera was removed.").foregroundStyle(Theme.textSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas.ignoresSafeArea())
        .navigationTitle(index.map { config.settings.cameras[$0].displayName } ?? "Camera")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailSection(_ idx: Int) -> some View {
        let cam = camBinding(idx)
        return Section("Camera") {
            HStack {
                Text("Display name"); Spacer()
                TextField("Name", text: cam.displayName).multilineTextAlignment(.trailing)
            }
            HStack {
                Text("Stream"); Spacer()
                TextField("stream", text: cam.streamName)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            if !availableStreams.isEmpty {
                StreamChips(streamName: cam.streamName, available: availableStreams)
            }
            Toggle("Fisheye (dewarp)", isOn: cam.isFisheye)
            Toggle("Start muted", isOn: cam.startMuted)
            VStack(alignment: .leading) {
                Text("Cry sensitivity: \(Int(config.settings.cameras[idx].crySensitivity * 100))%")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                Slider(value: cam.crySensitivity, in: 0...1)
            }
        }
    }

    private func fisheyeSection(_ idx: Int) -> some View {
        let cam = camBinding(idx)
        return Section {
            calibration("Center X", cam.dewarp.centerX, 0.3...0.7)
            calibration("Center Y", cam.dewarp.centerY, 0.3...0.7)
            calibration("Radius", cam.dewarp.radius, 0.2...0.7)
            calibration("Lens FOV°", cam.dewarp.lensFOVDegrees, 120...240, fmt: "%.0f")
            Toggle("Flip horizontally", isOn: cam.dewarp.flipHorizontal)
            Toggle("Invert pan (left / right)", isOn: cam.dewarp.invertPan)
            Toggle("Invert tilt (up / down)", isOn: cam.dewarp.invertTilt)
        } header: {
            Text("Fisheye calibration")
        } footer: {
            Text("Dial Center/Radius so the circular image fills the view, and Lens FOV to match your lens (≈180–200°). Pinch to zoom, drag to look around. If pan or tilt feels backwards, flip it here.")
        }
    }

    private func babyVitalsSection(_ idx: Int) -> some View {
        let cam = camBinding(idx)
        return Section {
            Picker("Owlet sock", selection: cam.owletSockDSN) {
                Text("None").tag(String?.none)
                ForEach(availableSocks) { sock in
                    Text(sockLabel(sock)).tag(Optional(sock.dsn))
                }
            }
        } header: {
            Text("Baby vitals")
        } footer: {
            Text("Pair an Owlet sock to overlay live heart rate, oxygen and sleep on this camera. Tap the overlay for history.")
        }
    }

    private func sockLabel(_ s: VitalsDevice) -> String {
        AppConfig.prettify(s.name) + " · " + String(s.dsn.suffix(4))
    }

    // MARK: Helpers

    private func camBinding(_ idx: Int) -> Binding<CameraSettings> {
        Binding(get: { config.settings.cameras[idx] },
                set: { config.settings.cameras[idx] = $0 })
    }

    private func calibration(_ title: String, _ value: Binding<Float>,
                             _ range: ClosedRange<Float>, fmt: String = "%.2f") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(String(format: fmt, value.wrappedValue))
                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.textTertiary)
            }
            Slider(value: value, in: range)
        }
    }
}
