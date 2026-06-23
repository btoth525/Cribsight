import SwiftUI

/// A circular, glass-backed icon button used across the monitor UI.
struct GlassIconButton: View {
    let systemName: String
    var active: Bool = false
    var tint: Color = Theme.accent
    var size: CGFloat = 46
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(active ? Color.black : Theme.textPrimary)
                .frame(width: size, height: size)
                .background {
                    if active { Circle().fill(tint) }
                }
        }
        .buttonStyle(.plain)
        .glassPill()
        .contentShape(Circle())
    }
}

/// A compact 5-segment VU meter. `level` is expected pre-scaled to 0…1.
struct VUMeter: View {
    var level: Double
    private let segments = 5

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<segments, id: \.self) { index in
                let lit = level >= Double(index + 1) / Double(segments) - 0.001
                Capsule()
                    .fill(lit ? color(for: index) : Color.white.opacity(0.14))
                    .frame(width: 4, height: 8 + CGFloat(index) * 3)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassPill()
    }

    private func color(for index: Int) -> Color {
        let frac = Double(index) / Double(segments - 1)
        if frac < 0.6 { return Theme.live }
        if frac < 0.85 { return Theme.warn }
        return Theme.danger
    }
}
