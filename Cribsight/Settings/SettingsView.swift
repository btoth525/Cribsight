import SwiftUI

/// Glass settings sheet. Edits the shared `AppConfig`; the monitor re-applies
/// changes when the sheet is dismissed.
struct SettingsView: View {
    @ObservedObject var config: AppConfig
    @StateObject private var catalog = StreamCatalog()
    @State private var password: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                camerasSection
                layoutsSection
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
                    Button("Done") {
                        config.frigatePassword = password
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .onAppear {
            config.settings.connection.mode = .frigate
            password = config.frigatePassword ?? ""
        }
    }

    // MARK: Connection

    private var connectionSection: some View {
        Section {
            HStack {
                Text("Host"); Spacer()
                TextField("192.168.1.50", text: $config.settings.connection.host)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.URL)
            }
            HStack {
                Text("Username"); Spacer()
                TextField("admin", text: $config.settings.connection.username)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            HStack {
                Text("Password"); Spacer()
                SecureField("••••••••", text: $password).multilineTextAlignment(.trailing)
            }
            HStack {
                Text("Port"); Spacer()
                TextField("8971", value: $config.settings.connection.frigatePort,
                          format: .number.grouping(.never))
                    .multilineTextAlignment(.trailing).keyboardType(.numberPad).frame(width: 90)
            }
            Toggle("Use HTTPS / WSS", isOn: $config.settings.connection.useTLS)

            Button {
                Haptics.tap()
                config.frigatePassword = password
                catalog.discover(connection: config.settings.connection, password: password)
            } label: {
                HStack {
                    if catalog.isLoading { ProgressView() }
                    else { Image(systemName: "antenna.radiowaves.left.and.right") }
                    Text(catalog.isLoading ? "Connecting…" : "Connect & find cameras")
                }
            }
            .disabled(!config.settings.connection.isComplete || catalog.isLoading)

            if catalog.state != .idle {
                DiscoveryStatusLabel(state: catalog.state)
            }
        } header: {
            Text("Frigate")
        } footer: {
            Text("For smooth video, make sure port 8555 (TCP + UDP) is reachable on your LAN.")
        }
    }

    // MARK: Cameras

    private var camerasSection: some View {
        Section {
            ForEach($config.settings.cameras) { $cam in
                NavigationLink {
                    CameraSettingsView(config: config, cameraID: cam.id, availableStreams: catalog.names)
                } label: {
                    HStack {
                        Image(systemName: cam.isFisheye ? "circle.circle" : "video")
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cam.displayName.isEmpty ? "Camera" : cam.displayName)
                            Text(cam.streamName.isEmpty ? "no stream set" : cam.streamName)
                                .font(.caption).foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
            .onDelete { idx in
                idx.map { config.settings.cameras[$0].id }.forEach { config.removeCamera($0) }
            }
            Button {
                config.addCamera(.blank()); Haptics.tap()
            } label: {
                Label("Add camera", systemImage: "plus")
            }
        } header: {
            Text("Cameras")
        }
    }

    // MARK: Layouts

    private var layoutsSection: some View {
        Section {
            ForEach(config.settings.layouts) { layout in
                Button {
                    config.selectLayout(layout.id); Haptics.selection()
                } label: {
                    HStack {
                        Text(layout.name)
                        Spacer()
                        Text("\(layout.slots.count) pane\(layout.slots.count == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(Theme.textTertiary)
                        if config.settings.activeLayoutID == layout.id {
                            Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                        }
                    }
                }
                .foregroundStyle(Theme.textPrimary)
            }
            .onDelete { idx in
                idx.map { config.settings.layouts[$0].id }.forEach { config.deleteLayout($0) }
            }
            Button {
                let layout = PaneLayout.auto(cameraIDs: config.settings.cameras.map { $0.id },
                                             name: "Grid \(config.settings.layouts.count + 1)")
                config.saveLayout(layout); Haptics.tap()
            } label: {
                Label("New layout from all cameras", systemImage: "plus.rectangle.on.rectangle")
            }
        } header: {
            Text("Layouts")
        } footer: {
            Text("Tap the grid button on the monitor to drag, resize and rearrange panes.")
        }
    }

    // MARK: Other

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
                ForEach(NightModeTrigger.allCases) { Text($0.label).tag($0) }
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
                .font(.footnote).foregroundStyle(Theme.textSecondary)
        } header: {
            Text("Kiosk")
        } footer: {
            Text("Cribsight · v2 · LAN-only, no cloud.")
        }
    }

}
