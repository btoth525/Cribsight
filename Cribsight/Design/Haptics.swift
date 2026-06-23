import UIKit

/// Lightweight haptic helpers. Generators are created on demand; UIKit pools the
/// underlying engine so this stays cheap for UI feedback.
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func rigid() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Used for the cry / sound alert.
    static func alert() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
