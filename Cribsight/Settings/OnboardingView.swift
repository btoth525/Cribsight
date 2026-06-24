import SwiftUI
import UIKit

/// First-run setup: log in to Frigate, discover cameras, and assign them.
struct OnboardingView: View {
    @ObservedObject var config: AppConfig
    @StateObject private var catalog = StreamCatalog()
    @State private var password: String = ""
    @State private var didPrepare = false
    var onDone: () -> Void

    private var connection: ConnectionSettings { config.settings.connection }

    private var canStart: Bool {
        guard connection.isComplete else { return false }
        if connection.mode == .frigate && password.isEmpty { return false }
        return config.settings.cameras.contains { !$0.streamName.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
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
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .onAppear {
            config.settings.connection.mode = .frigate
            password = config.frigatePassword ?? ""
            if !didPrepare {
                didPrepare = true
                // Fresh setup: drop the placeholder seed cameras so the list stays
                // empty until Frigate hands back the real ones.
                config.settings.cameras = []
            }
        }
        .onChange(of: catalog.names) { _, names in
            // As soon as Frigate hands back the camera list, build the cameras
            // automatically — the user never types a stream name.
            config.autoPopulateCameras(from: names)
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.brandGradient)
                    .frame(width: 84, height: 84)
                Image(systemName: "eye.fill")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)
            }
            .shadow(color: Theme.accent.opacity(0.4), radius: 18, y: 8)
            Text("Cribsight")
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.textPrimary)
            Text("Your multi-camera nursery monitor")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 24)
    }

    // MARK: Server / connection

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

    // MARK: Cameras

    private var camerasCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cameras").font(.headline).foregroundStyle(Theme.textPrimary)

            if config.settings.cameras.isEmpty {
                Text("Connect to Frigate above — your cameras will appear here automatically.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Found these. Tap a name to rename it, and flag any ceiling fisheye cameras so they get the live dewarp.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach($config.settings.cameras) { $cam in
                    cameraRow($cam)
                    if cam.id != config.settings.cameras.last?.id {
                        Divider().overlay(Theme.hairline)
                    }
                }
            }
        }
        .padding(18)
        .glassCard()
    }

    private func cameraRow(_ cam: Binding<CameraSettings>) -> some View {
        HStack(spacing: 10) {
            TextField("Camera name", text: cam.displayName)
                .font(.subheadline.weight(.medium))
                .textInputAutocapitalization(.words)
            Spacer(minLength: 8)
            Toggle(isOn: cam.isFisheye) {
                Label("Fisheye", systemImage: "circle.circle")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
            }
            .toggleStyle(.button)
            .tint(Theme.accent)
            Button {
                config.removeCamera(cam.wrappedValue.id)
                Haptics.rigid()
            } label: {
                Image(systemName: "trash").font(.caption).foregroundStyle(Theme.danger)
            }
        }
    }

    private var startButton: some View {
        Button {
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
