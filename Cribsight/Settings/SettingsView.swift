import SwiftUI

/// Glass settings sheet. Edits the shared `AppConfig`; the monitor re-applies
/// changes when the sheet is dismissed.
struct SettingsView: View {
    @ObservedObject var config: AppConfig
    @StateObject private var catalog = StreamCatalog()
    @StateObject private var owletProbe = VitalsService()
    @State private var password: String = ""
    @State private var showTour = false
    @State private var renamingID: UUID? = nil
    @State private var renameText = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                camerasSection
                owletSection
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
        .fullScreenCover(isPresented: $showTour) {
            TourView {
                config.settings.hasSeenTour = true
                showTour = false
            }
        }
        .alert("Rename view", isPresented: Binding(
            get: { renamingID != nil },
            set: { if !$0 { renamingID = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let id = renamingID { config.renameLayout(id, to: renameText) }
                renamingID = nil
            }
            Button("Cancel", role: .cancel) { renamingID = nil }
        }
        .onAppear {
            config.settings.connection.mode = .frigate
            password = config.frigatePassword ?? ""
            // Refresh the available-cameras list so "Add camera" is ready to pick from.
            if catalog.names.isEmpty, config.settings.connection.isComplete, !password.isEmpty {
                catalog.discover(connection: config.settings.connection, password: password)
            }
            if config.settings.owlet.isComplete {
                owletProbe.update(settings: config.settings.owlet)
            }
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
                    CameraSettingsView(config: config, cameraID: cam.id,
                                       availableStreams: catalog.names, availableSocks: owletProbe.socks)
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
            Menu {
                let available = catalog.names.filter { name in
                    !config.settings.cameras.contains { $0.streamName == name }
                }
                if available.isEmpty {
                    if catalog.isLoading {
                        Text("Loading cameras…")
                    } else if catalog.names.isEmpty {
                        Text("Use Connect above to load cameras")
                    } else {
                        Text("All cameras added")
                    }
                } else {
                    ForEach(available, id: \.self) { name in
                        Button {
                            config.addCameraFromStream(name)
                            Haptics.tap()
                        } label: {
                            Label(AppConfig.prettify(name), systemImage: "video")
                        }
                    }
                }
            } label: {
                Label("Add camera", systemImage: "plus")
            }
        } header: {
            Text("Cameras")
        } footer: {
            Text("Adding a camera drops it straight into the grid. Swipe a camera to remove it.")
        }
    }

    // MARK: Owlet bridge (Baby Mode)

    private var owletSection: some View {
        Section {
            Toggle("Enable Owlet bridge", isOn: $config.settings.owlet.enabled)
            if config.settings.owlet.enabled {
                HStack {
                    Text("Bridge host"); Spacer()
                    TextField("192.168.1.50", text: $config.settings.owlet.host)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                HStack {
                    Text("Data port"); Spacer()
                    TextField("8088", value: $config.settings.owlet.vitalsPort, format: .number.grouping(.never))
                        .multilineTextAlignment(.trailing).keyboardType(.numberPad).frame(width: 80)
                }
                HStack {
                    Text("Video port"); Spacer()
                    TextField("1984", value: $config.settings.owlet.controlPort, format: .number.grouping(.never))
                        .multilineTextAlignment(.trailing).keyboardType(.numberPad).frame(width: 80)
                }
                Button {
                    Haptics.tap()
                    owletProbe.update(settings: config.settings.owlet)
                } label: {
                    Label("Test & find devices", systemImage: "antenna.radiowaves.left.and.right")
                }
                if owletProbe.reachable {
                    Label("Connected · \(owletProbe.socks.count) sock\(owletProbe.socks.count == 1 ? "" : "s"), \(owletProbe.snapshot?.cameras.count ?? 0) camera\((owletProbe.snapshot?.cameras.count ?? 0) == 1 ? "" : "s")",
                          systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(Theme.live)
                }
                ForEach(owletProbe.snapshot?.cameras ?? []) { cam in
                    let added = config.settings.cameras.contains { $0.isOwletBridge && $0.streamName == cam.name }
                    Button {
                        let sock = owletProbe.socks.count == 1 ? owletProbe.socks.first?.dsn : nil
                        config.addOwletCamera(streamName: cam.name,
                                              displayName: AppConfig.prettify(cam.name), sockDSN: sock)
                        Haptics.tap()
                    } label: {
                        HStack {
                            Label(AppConfig.prettify(cam.name), systemImage: "video.badge.waveform")
                            Spacer()
                            if added { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                            else { Text("Add").foregroundStyle(Theme.accent) }
                        }
                    }
                    .disabled(added)
                }
            }
        } header: {
            Text("Owlet Bridge · Baby Mode")
        } footer: {
            Text("Streams the Owlet camera directly (sub-second) and overlays live sock vitals. Pair a sock to any camera in its settings.")
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
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        config.deleteLayout(layout.id)
                    } label: { Label("Delete", systemImage: "trash") }
                    Button {
                        renameText = layout.name
                        renamingID = layout.id
                    } label: { Label("Rename", systemImage: "pencil") }
                    .tint(Theme.accent)
                }
            }
            Button {
                let layout = PaneLayout.auto(cameraIDs: config.settings.cameras.map { $0.id },
                                             name: "View \(config.settings.layouts.count + 1)")
                config.saveLayout(layout); Haptics.tap()
            } label: {
                Label("New view from all cameras", systemImage: "plus.rectangle.on.rectangle")
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
            Button {
                Haptics.tap()
                showTour = true
            } label: {
                Label("How to use Cribsight", systemImage: "questionmark.circle")
            }
            Label("Lock the app with iOS Guided Access (triple-click the side button) to use it as a kiosk.",
                  systemImage: "lock.shield")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
        } header: {
            Text("Help & Kiosk")
        } footer: {
            Text("Cribsight · v2 · LAN-only, no cloud.")
        }
    }

}
