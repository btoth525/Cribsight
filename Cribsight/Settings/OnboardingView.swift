import SwiftUI
import UIKit

/// First-run setup: a welcome walkthrough, then Frigate login, then a checklist
/// of the cameras to use.
struct OnboardingView: View {
    @ObservedObject var config: AppConfig
    @StateObject private var catalog = StreamCatalog()
    @State private var password: String = ""
    @State private var didPrepare = false
    @State private var showWelcome = true
    /// Streams the user ticked, and which of those are fisheye.
    @State private var selected: Set<String> = []
    @State private var fisheyeStreams: Set<String> = []
    var onDone: () -> Void

    private var connection: ConnectionSettings { config.settings.connection }

    private var canStart: Bool {
        connection.isComplete && !password.isEmpty && !selected.isEmpty
    }

    var body: some View {
        Group {
            if showWelcome {
                TourView {
                    config.settings.hasSeenTour = true
                    withAnimation { showWelcome = false }
                }
            } else {
                setup
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .onAppear {
            config.settings.connection.mode = .frigate
            password = config.frigatePassword ?? ""
            if !didPrepare {
                didPrepare = true
                // Cameras are built from the checklist on Start; clear any seeds.
                config.settings.cameras = []
            }
        }
    }

    private var setup: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            RadialGradient(colors: [Theme.accent.opacity(0.25), .clear],
                           center: .topLeading, startRadius: 20, endRadius: 520)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    header
                    serverCard
                    camerasCard
                    startButton
                    Text("Everything stays on your local network. No cloud, no accounts.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.brandGradient)
                    .frame(width: 72, height: 72)
                Image(systemName: "eye.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
            }
            .shadow(color: Theme.accent.opacity(0.4), radius: 18, y: 8)
            Text("Set up Cribsight")
                .font(.title.bold())
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.top, 16)
    }

    // MARK: Connection

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect to Frigate")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("Enter your Frigate address and login. Cribsight signs in and finds your cameras for you.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            field("Frigate IP / host", text: $config.settings.connection.host,
                  placeholder: "192.168.1.50", keyboard: .URL)
            field("Username", text: $config.settings.connection.username, placeholder: "admin")
            secureField("Password", text: $password)

            HStack(spacing: 16) {
                HStack {
                    Text("Port").foregroundStyle(Theme.textSecondary)
                    Spacer()
                    TextField("8971", value: $config.settings.connection.frigatePort,
                              format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 72)
                }
                Toggle("HTTPS", isOn: $config.settings.connection.useTLS)
                    .font(.subheadline)
                    .fixedSize()
            }

            Button {
                Haptics.tap()
                config.frigatePassword = password
                catalog.discover(connection: config.settings.connection, password: password)
            } label: {
                HStack(spacing: 8) {
                    if catalog.isLoading { ProgressView().tint(Theme.textPrimary) }
                    else { Image(systemName: "antenna.radiowaves.left.and.right") }
                    Text(catalog.isLoading ? "Connecting…" : "Connect & find cameras")
                }
                .frame(maxWidth: .infinity)
            }
            .glassButton()
            .disabled(!connection.isComplete || catalog.isLoading || password.isEmpty)
            .opacity(connection.isComplete && !password.isEmpty ? 1 : 0.5)

            DiscoveryStatusLabel(state: catalog.state)

            Text("Tip: for smooth video, make sure port 8555 (TCP + UDP) is open on your network.")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .glassCard()
    }

    // MARK: Camera checklist

    private var camerasCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Choose cameras").font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                if !catalog.names.isEmpty {
                    Text("\(selected.count) selected")
                        .font(.caption).foregroundStyle(Theme.textTertiary)
                }
            }

            if catalog.names.isEmpty {
                Text("Connect to Frigate above and your cameras will appear here to pick from.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Tap the cameras you want to watch. Flag any ceiling fisheye so it gets the live dewarp.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(catalog.names, id: \.self) { name in
                    cameraPickRow(name)
                    if name != catalog.names.last {
                        Divider().overlay(Theme.hairline)
                    }
                }
            }
        }
        .padding(18)
        .glassCard()
    }

    private func cameraPickRow(_ name: String) -> some View {
        let isOn = selected.contains(name)
        return HStack(spacing: 12) {
            Button {
                toggleSelected(name)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isOn ? Theme.accent : Theme.textTertiary)
                    Text(AppConfig.prettify(name))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            if isOn {
                Toggle(isOn: fisheyeBinding(name)) {
                    Label("Fisheye", systemImage: "circle.circle").font(.caption)
                }
                .toggleStyle(.button)
                .tint(Theme.accent)
            }
        }
    }

    private var startButton: some View {
        Button {
            config.setSelectedCameras(streams: catalog.names.filter { selected.contains($0) },
                                      fisheye: fisheyeStreams)
            config.frigatePassword = password
            onDone()
        } label: {
            Text("Start Monitoring").frame(maxWidth: .infinity)
        }
        .glassButton(prominent: true)
        .disabled(!canStart)
        .opacity(canStart ? 1 : 0.5)
    }

    // MARK: Helpers

    private func toggleSelected(_ name: String) {
        if selected.contains(name) {
            selected.remove(name)
            fisheyeStreams.remove(name)
        } else {
            selected.insert(name)
        }
        Haptics.tap()
    }

    private func fisheyeBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { fisheyeStreams.contains(name) },
            set: { on in
                if on { fisheyeStreams.insert(name) } else { fisheyeStreams.remove(name) }
            }
        )
    }

    private func field(_ label: String, text: Binding<String>,
                       placeholder: String, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboard)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1))
        }
    }

    private func secureField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
            SecureField("••••••••", text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1))
        }
    }
}
