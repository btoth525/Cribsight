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
                if !availableSocks.isEmpty || config.settings.cameras[idx].babyMode {
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

    @ViewBuilder
    private func babyVitalsSection(_ idx: Int) -> some View {
        let cam = camBinding(idx)
        Section {
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

        if config.settings.cameras[idx].babyMode {
            hudFieldsSection(idx)
        }
    }

    /// Editor for which vitals appear on the live HUD — drag to reorder, swipe to
    /// remove, tap Add to include more.
    private func hudFieldsSection(_ idx: Int) -> some View {
        let fields = config.settings.cameras[idx].hudFields
        let remaining = VitalsField.allCases.filter { !fields.contains($0) }
        return Section {
            if fields.isEmpty {
                Text("No metrics — the HUD is hidden. Add one below.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            ForEach(fields) { field in
                Label(field.label, systemImage: field.icon)
                    .foregroundStyle(Theme.textPrimary)
            }
            .onMove { offsets, dest in
                mutateHud { $0.move(fromOffsets: offsets, toOffset: dest) }
            }
            .onDelete { offsets in
                mutateHud { $0.remove(atOffsets: offsets) }
            }
            if !remaining.isEmpty {
                Menu {
                    ForEach(remaining) { field in
                        Button {
                            mutateHud { $0.append(field) }
                        } label: {
                            Label(field.label, systemImage: field.icon)
                        }
                    }
                } label: {
                    Label("Add metric", systemImage: "plus.circle.fill")
                }
            }
        } header: {
            HStack {
                Text("HUD metrics")
                Spacer()
                EditButton().font(.subheadline)
            }
        } footer: {
            Text("These show on the camera's live overlay, in this order. Drag to reorder, swipe left to remove.")
        }
    }

    private func sockLabel(_ s: VitalsDevice) -> String {
        // The bridge often reports the sock's name as its DSN; prefer the model
        // ("SS3-Sleep") for a friendly label, tagged with the last 4 of the DSN.
        let base = (s.name == s.dsn || s.name.isEmpty) ? (s.model ?? "Owlet sock")
                                                       : AppConfig.prettify(s.name)
        return base + " · " + String(s.dsn.suffix(4))
    }

    // MARK: Helpers

    /// Mutate this camera's HUD fields by looking the camera up by id at call time,
    /// so a stale captured index can never subscript out of bounds.
    private func mutateHud(_ body: (inout [VitalsField]) -> Void) {
        guard let i = config.settings.cameras.firstIndex(where: { $0.id == cameraID }) else { return }
        body(&config.settings.cameras[i].hudFields)
    }

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
