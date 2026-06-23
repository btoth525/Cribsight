import SwiftUI

// MARK: - Liquid Glass surfaces with a graceful fallback
//
// On iOS 26+ these use the native Liquid Glass material (`.glassEffect`).
// On iOS 18–25 they fall back to `.ultraThinMaterial` with a hairline stroke so
// the app still looks polished on every device the project supports.

struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = Theme.cardCornerRadius
    var tint: Color? = nil

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            content.glassEffect(tintedGlass(tint), in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 1))
        }
    }

    @available(iOS 26.0, *)
    private func tintedGlass(_ tint: Color?) -> Glass {
        if let tint { return Glass.regular.tint(tint) }
        return Glass.regular
    }
}

struct GlassPillModifier: ViewModifier {
    var tint: Color? = nil

    func body(content: Content) -> some View {
        let shape = Capsule(style: .continuous)
        if #available(iOS 26.0, *) {
            content.glassEffect(tint.map { Glass.regular.tint($0) } ?? Glass.regular, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 1))
        }
    }
}

extension View {
    /// Rounded-rectangle glass surface (cards, sheets, control bars).
    func glassCard(cornerRadius: CGFloat = Theme.cardCornerRadius, tint: Color? = nil) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, tint: tint))
    }

    /// Capsule glass surface (badges, pills, floating buttons).
    func glassPill(tint: Color? = nil) -> some View {
        modifier(GlassPillModifier(tint: tint))
    }
}

// MARK: - Glass-aware button styles

/// Fallback button style approximating Liquid Glass on pre-iOS 26 systems.
struct FallbackGlassButtonStyle: ButtonStyle {
    var prominent: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(prominent ? Color.black : Theme.textPrimary)
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .background {
                if prominent {
                    Capsule().fill(Theme.accent)
                } else {
                    Capsule().fill(.ultraThinMaterial)
                        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
                }
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension View {
    /// Applies the native `.glass` / `.glassProminent` button style on iOS 26,
    /// otherwise a close-matching fallback.
    @ViewBuilder
    func glassButton(prominent: Bool = false, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent).tint(tint ?? Theme.accent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            self.buttonStyle(FallbackGlassButtonStyle(prominent: prominent))
        }
    }
}
