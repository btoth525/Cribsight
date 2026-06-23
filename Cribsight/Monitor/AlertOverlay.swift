import SwiftUI

/// Transient glass toast shown at the top of the monitor (cry alerts, snapshot
/// results, lock hints).
struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accentWarm)
            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .glassCard(cornerRadius: 22)
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
    }
}
