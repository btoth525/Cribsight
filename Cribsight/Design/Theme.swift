import SwiftUI

/// Central palette + spacing for Cribsight's dark-first nursery look.
enum Theme {
    // Canvas / surfaces
    static let canvas = Color(red: 0.039, green: 0.043, blue: 0.055)
    static let canvasElevated = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let hairline = Color.white.opacity(0.10)

    // Brand
    static let accent = Color(red: 0.388, green: 0.745, blue: 0.890)   // cool teal/blue
    static let accentWarm = Color(red: 0.98, green: 0.58, blue: 0.38)  // warm amber

    // Status
    static let live = Color(red: 0.30, green: 0.85, blue: 0.46)
    static let warn = Color(red: 0.98, green: 0.72, blue: 0.25)
    static let danger = Color(red: 0.96, green: 0.36, blue: 0.42)

    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.40)

    // Geometry
    static let paneCornerRadius: CGFloat = 26
    static let cardCornerRadius: CGFloat = 22
    static let controlCornerRadius: CGFloat = 18
    static let spacing: CGFloat = 12

    /// A soft brand gradient used for accents, the app icon and empty states.
    static let brandGradient = LinearGradient(
        colors: [Color(red: 0.30, green: 0.62, blue: 0.95),
                 Color(red: 0.49, green: 0.85, blue: 0.92),
                 Color(red: 0.62, green: 0.55, blue: 0.96)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
