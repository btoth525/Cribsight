import SwiftUI

/// Dims the screen and adds a warm/red wash so the monitor's glow does not light
/// up the nursery. Purely an overlay — it never blocks touches.
struct NightModeOverlay: ViewModifier {
    var enabled: Bool
    /// 0 = no dimming, 0.85 = very dark.
    var dim: Double
    /// 0 = neutral, 1 = strongly warm/red.
    var warmth: Double

    func body(content: Content) -> some View {
        content.overlay {
            if enabled {
                ZStack {
                    Color.black.opacity(min(max(dim, 0), 0.92))
                    Color(red: 0.62, green: 0.16, blue: 0.0)
                        .opacity(0.22 * min(max(warmth, 0), 1))
                        .blendMode(.multiply)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: enabled)
    }
}

extension View {
    func nightMode(enabled: Bool, dim: Double, warmth: Double) -> some View {
        modifier(NightModeOverlay(enabled: enabled, dim: dim, warmth: warmth))
    }
}
