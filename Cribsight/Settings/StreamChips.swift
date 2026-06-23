import SwiftUI

/// A horizontal row of the stream names discovered from Frigate/go2rtc. Tapping
/// one fills in the bound stream name — so the user picks their camera instead of
/// typing it (and typos, the #1 setup mistake, go away). Manual entry still works
/// via the text field this sits next to.
struct StreamChips: View {
    @Binding var streamName: String
    let available: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(available, id: \.self) { name in
                    chip(name)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(_ name: String) -> some View {
        let selected = name == streamName
        return Button {
            streamName = name
            Haptics.tap()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: selected ? "checkmark.circle.fill" : "video.fill")
                    .font(.caption2)
                Text(name)
                    .font(.caption.weight(.medium))
            }
            .foregroundStyle(selected ? Color.black : Theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                Capsule(style: .continuous)
                    .fill(selected ? Theme.accent : Color.white.opacity(0.06))
                    .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: selected ? 0 : 1))
            }
        }
        .buttonStyle(.plain)
    }
}

/// Compact result line for a discovery attempt (shared by onboarding + settings).
struct DiscoveryStatusLabel: View {
    let state: StreamCatalog.LoadState

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .loading:
            label("Looking for cameras…", system: "antenna.radiowaves.left.and.right", tint: Theme.textSecondary)
        case .loaded(let names):
            if names.isEmpty {
                label("Connected, but no streams are defined in go2rtc yet.",
                      system: "exclamationmark.triangle.fill", tint: Theme.warn)
            } else {
                label("Found \(names.count) camera\(names.count == 1 ? "" : "s"). Tap one for each pane.",
                      system: "checkmark.circle.fill", tint: Theme.live)
            }
        case .failed(let message):
            label(message, system: "xmark.octagon.fill", tint: Theme.danger)
        }
    }

    private func label(_ text: String, system: String, tint: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: system).foregroundStyle(tint)
            Text(text)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.caption)
    }
}
