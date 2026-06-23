import SwiftUI
import UIKit

/// First-run setup: capture the go2rtc server and the two stream names.
struct OnboardingView: View {
    @ObservedObject var config: AppConfig
    @StateObject private var catalog = StreamCatalog()
    var onDone: () -> Void

    private var canStart: Bool {
        !config.settings.serverHost.trimmingCharacters(in: .whitespaces).isEmpty
            && !config.settings.cameraA.streamName.isEmpty
            && !config.settings.cameraB.streamName.isEmpty
    }

    private var serverHostEmpty: Bool {
        config.settings.serverHost.trimmingCharacters(in: .whitespaces).isEmpty
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
            Text("Your split-screen nursery monitor")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 24)
    }

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Frigate / go2rtc server")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("Point Cribsight at your existing Frigate box. It already keeps one connection to each camera, so nothing extra hits the cameras.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            field("Server IP / host", text: $config.settings.serverHost,
                  placeholder: "192.168.1.50", keyboard: .URL)
            HStack {
                Text("Port")
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                TextField("1984", value: $config.settings.serverPort,
                          format: .number.grouping(.never))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
            }

            Button {
                Haptics.tap()
                catalog.discover(apiBase: config.apiBase())
            } label: {
                HStack(spacing: 8) {
                    if catalog.isLoading {
                        ProgressView().tint(Theme.textPrimary)
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                    }
                    Text(catalog.isLoading ? "Connecting…" : "Connect & find cameras")
                }
                .frame(maxWidth: .infinity)
            }
            .glassButton()
            .disabled(serverHostEmpty || catalog.isLoading)
            .opacity(serverHostEmpty ? 0.5 : 1)

            DiscoveryStatusLabel(state: catalog.state)
        }
        .padding(18)
        .glassCard()
    }

    private var camerasCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cameras")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 10) {
                Text("Camera A").font(.caption.weight(.semibold)).foregroundStyle(Theme.textTertiary)
                field("Display name", text: $config.settings.cameraA.displayName, placeholder: "Owlet")
                field("go2rtc stream name", text: $config.settings.cameraA.streamName, placeholder: "owlet")
                if !catalog.names.isEmpty {
                    StreamChips(streamName: $config.settings.cameraA.streamName, available: catalog.names)
                }
            }
            Divider().overlay(Theme.hairline)
            VStack(alignment: .leading, spacing: 10) {
                Text("Camera B · Fisheye").font(.caption.weight(.semibold)).foregroundStyle(Theme.textTertiary)
                field("Display name", text: $config.settings.cameraB.displayName, placeholder: "Nursery")
                field("go2rtc stream name", text: $config.settings.cameraB.streamName, placeholder: "reolink")
                if !catalog.names.isEmpty {
                    StreamChips(streamName: $config.settings.cameraB.streamName, available: catalog.names)
                }
            }
        }
        .padding(18)
        .glassCard()
    }

    private var startButton: some View {
        Button {
            onDone()
        } label: {
            Text("Start Monitoring")
                .frame(maxWidth: .infinity)
        }
        .glassButton(prominent: true)
        .disabled(!canStart)
        .opacity(canStart ? 1 : 0.5)
    }

    private func field(_ label: String, text: Binding<String>,
                       placeholder: String, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboard)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1))
        }
    }
}
