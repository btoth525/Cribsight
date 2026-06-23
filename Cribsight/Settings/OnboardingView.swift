import SwiftUI
import UIKit

/// First-run setup: choose how to connect (Direct go2rtc or Frigate login),
/// discover cameras, and assign them.
struct OnboardingView: View {
    @ObservedObject var config: AppConfig
    @StateObject private var catalog = StreamCatalog()
    @State private var password: String = ""
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
        .onAppear { password = config.frigatePassword ?? "" }
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
            Text("Connection")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            Picker("Mode", selection: $config.settings.connection.mode) {
                ForEach(ConnectionMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            Text(connection.mode.blurb)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            field("Server IP / host", text: $config.settings.connection.host,
                  placeholder: "192.168.1.50", keyboard: .URL)

            HStack {
                Text("Port").foregroundStyle(Theme.textSecondary)
                Spacer()
                TextField(connection.mode == .frigate ? "8971" : "1984", value: portBinding,
                          format: .number.grouping(.never))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
            }

            if connection.mode == .frigate {
                field("Username", text: $config.settings.connection.username, placeholder: "admin")
                secureField("Password", text: $password)
            }

            Toggle("Use HTTPS / WSS", isOn: $config.settings.connection.useTLS)
                .font(.subheadline)

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
            .disabled(!connection.isComplete || catalog.isLoading
                      || (connection.mode == .frigate && password.isEmpty))
            .opacity(connection.isComplete ? 1 : 0.5)

            DiscoveryStatusLabel(state: catalog.state)

            Text("For sub-second video, port 8555 (TCP+UDP) must be reachable on your LAN, and go2rtc needs `webrtc.candidates: [\"\(connection.hostTrimmed.isEmpty ? "<server-ip>" : connection.hostTrimmed):8555\"]`.")
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
            HStack {
                Text("Cameras").font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    config.addCamera(.blank())
                    Haptics.tap()
                } label: {
                    Label("Add", systemImage: "plus").font(.subheadline.weight(.semibold))
                }
            }

            ForEach($config.settings.cameras) { $cam in
                cameraRow($cam)
                if cam.id != config.settings.cameras.last?.id {
                    Divider().overlay(Theme.hairline)
                }
            }
        }
        .padding(18)
        .glassCard()
    }

    private func cameraRow(_ cam: Binding<CameraSettings>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(cam.wrappedValue.displayName.isEmpty ? "Camera" : cam.wrappedValue.displayName)
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.textTertiary)
                Spacer()
                if config.settings.cameras.count > 1 {
                    Button {
                        config.removeCamera(cam.wrappedValue.id)
                        Haptics.rigid()
                    } label: {
                        Image(systemName: "trash").font(.caption).foregroundStyle(Theme.danger)
                    }
                }
            }
            field("Display name", text: cam.displayName, placeholder: "Nursery")
            field("Stream name", text: cam.streamName, placeholder: "reolink")
            if !catalog.names.isEmpty {
                StreamChips(streamName: cam.streamName, available: catalog.names)
            }
            Toggle("Fisheye (dewarp)", isOn: cam.isFisheye).font(.caption)
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

    private var portBinding: Binding<Int> {
        Binding(
            get: { connection.mode == .frigate ? connection.frigatePort : connection.go2rtcPort },
            set: {
                if connection.mode == .frigate { config.settings.connection.frigatePort = $0 }
                else { config.settings.connection.go2rtcPort = $0 }
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
