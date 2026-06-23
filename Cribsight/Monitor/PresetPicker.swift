import SwiftUI

/// Glass segmented control of saved fisheye framings (Panorama / Crib A / …).
struct PresetPicker: View {
    @ObservedObject var pane: PaneViewModel

    var body: some View {
        HStack(spacing: 5) {
            ForEach(pane.camera.presets) { preset in
                Button {
                    pane.apply(preset: preset)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: preset.systemImage)
                            .font(.system(size: 12, weight: .semibold))
                        Text(preset.name)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(isSelected(preset) ? Color.black : Theme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background {
                        if isSelected(preset) {
                            Capsule(style: .continuous).fill(Theme.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .glassPill()
    }

    private func isSelected(_ preset: ViewPreset) -> Bool {
        pane.mode == preset.mode && orientationsMatch(pane.orientation, preset.orientation)
    }

    private func orientationsMatch(_ a: ViewOrientation, _ b: ViewOrientation) -> Bool {
        abs(a.pan - b.pan) < 0.02 && abs(a.tilt - b.tilt) < 0.02 && abs(a.zoom - b.zoom) < 0.02
    }
}
