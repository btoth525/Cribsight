import UIKit

/// Lightweight haptic helpers. Generators are created on demand; UIKit pools the
/// underlying engine so this stays cheap for UI feedback.
enum Haptics {
    /// User preference (Settings ▸ Display ▸ Haptic feedback). Gates UI-feedback
    /// buzzes only — `alert()` always fires so a cry alert is never missed.
    static var isEnabled = true

    static func tap() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func soft() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func rigid() {
        guard isEnabled else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    static func selection() {
        guard isEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        guard isEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Used for cry / sound / battery alerts — intentionally NOT gated by
    /// `isEnabled`, so turning off UI buzzes never silences a real alert.
    static func alert() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
