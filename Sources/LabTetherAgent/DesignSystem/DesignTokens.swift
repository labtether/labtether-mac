import SwiftUI

// MARK: - LT Design Token Namespace

/// Centralised design token namespace for the LabTether Mac Agent.
/// All colors, typography, spacing, and animation constants are defined here
/// so that visual changes propagate consistently across every view.
enum LT {

    // MARK: Colors

    /// OLED-black base background.
    static let bg = Color(hex: "#0a0a0c")

    /// Semi-transparent glass panel fill.
    static let panelGlass = Color.white.opacity(0.04)

    /// Subtle glass panel border.
    static let panelBorder = Color.white.opacity(0.07)

    /// Hover-state highlight.
    static let hover = Color.white.opacity(0.06)

    /// Elevated glass panel fill — slightly brighter for nested/prominent cards.
    static let panelGlassElevated = Color.white.opacity(0.06)

    /// Neon Rose primary accent.
    static let accent = Color(hex: "#ff0080")

    /// Neon Rose accent at low opacity for glow layers.
    static let accentGlow = Color(hex: "#ff0080").opacity(0.15)

    /// Emerald success/healthy colour.
    static let ok = Color(hex: "#00e68a")

    /// Emerald glow layer.
    static let okGlow = Color(hex: "#00e68a").opacity(0.15)

    /// Amber warning colour.
    static let warn = Color(hex: "#f0b429")

    /// Amber glow layer.
    static let warnGlow = Color(hex: "#f0b429").opacity(0.15)

    /// Red error/critical colour.
    static let bad = Color(hex: "#ff3355")

    /// Red glow layer.
    static let badGlow = Color(hex: "#ff3355").opacity(0.18)

    /// High-contrast primary text.
    static let textPrimary = Color.white.opacity(0.92)

    /// De-emphasised secondary text.
    static let textSecondary = Color.white.opacity(0.55)

    /// Muted tertiary text (labels, decorators).
    static let textMuted = Color.white.opacity(0.35)

    // MARK: Typography

    /// Returns a Sora font at the given size and weight.
    ///
    /// Weight mapping: `.regular` → Sora-Regular, `.medium` → Sora-Medium,
    /// `.semibold` → Sora-SemiBold, `.bold` → Sora-Bold.
    /// Any other weight falls back to Sora-Regular.
    static func sora(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .custom(soraName(for: weight), size: size)
    }

    /// Returns an Inter font at the given size and weight.
    ///
    /// Weight mapping: `.regular` → Inter-Regular, `.medium` → Inter-Medium,
    /// `.semibold` → Inter-SemiBold. Any other weight falls back to Inter-Regular.
    static func inter(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(interName(for: weight), size: size)
    }

    /// Returns a JetBrains Mono font at the given size and weight.
    ///
    /// Weight mapping: `.regular` → JetBrainsMono-Regular,
    /// `.medium` → JetBrainsMono-Medium, `.semibold` → JetBrainsMono-SemiBold.
    /// Any other weight falls back to JetBrainsMono-Regular.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(monoName(for: weight), size: size)
    }

    // MARK: Spacing

    /// 4 pt micro-spacing.
    static let space4: CGFloat = 4
    /// 6 pt compact spacing.
    static let space6: CGFloat = 6
    /// 8 pt small spacing.
    static let space8: CGFloat = 8
    /// 12 pt base spacing / inner padding.
    static let space12: CGFloat = 12
    /// 16 pt standard spacing.
    static let space16: CGFloat = 16
    /// 20 pt comfortable spacing.
    static let space20: CGFloat = 20
    /// 24 pt section spacing.
    static let space24: CGFloat = 24

    // MARK: Corner Radii

    /// Small radius (6 pt) for tags, badges, and compact elements.
    static let radiusSm: CGFloat = 6
    /// Medium radius (10 pt) for cards and panels.
    static let radiusMd: CGFloat = 10
    /// Large radius (14 pt) for modals and prominent containers.
    static let radiusLg: CGFloat = 14

    // MARK: Animation Durations

    /// 0.12 s fast transition — immediate feedback.
    static let animFast: Double = 0.12
    /// 0.2 s standard transition.
    static let animNormal: Double = 0.2
    /// 0.3 s slow transition — deliberate state changes.
    static let animSlow: Double = 0.3
    /// 0.6 s value-flash duration — accent glow on metric value changes.
    static let animFlash: Double = 0.6
    /// 3.0 s breathing animation cycle for health orbs.
    static let breatheDuration: Double = 3.0

    // MARK: Interaction Constants

    /// Hover-lift offset for cards — subtle upward shift on hover.
    static let hoverLift: CGFloat = -1.5
    /// Focus ring width for input fields — accent glow on focus.
    static let focusRingRadius: CGFloat = 3

    // MARK: Spring Animations

    /// Snappy spring for micro-interactions (press feedback, toggles).
    static let springSnappy = Animation.spring(response: 0.35, dampingFraction: 0.75)
    /// Smooth spring for entrance animations and layout changes.
    static let springSmooth = Animation.spring(response: 0.5, dampingFraction: 0.85)
    /// Bouncy spring for playful emphasis (orb pulses, badge pop-ins).
    static let springBouncy = Animation.spring(response: 0.4, dampingFraction: 0.6)

    /// Scale factor for button press-down feedback.
    static let pressScale: CGFloat = 0.97

    // MARK: Private Helpers

    private static func soraName(for weight: Font.Weight) -> String {
        switch weight {
        case .medium:   return "Sora-Medium"
        case .semibold: return "Sora-SemiBold"
        case .bold:     return "Sora-Bold"
        default:        return "Sora-Regular"
        }
    }

    private static func interName(for weight: Font.Weight) -> String {
        switch weight {
        case .medium:   return "Inter-Medium"
        case .semibold: return "Inter-SemiBold"
        default:        return "Inter-Regular"
        }
    }

    private static func monoName(for weight: Font.Weight) -> String {
        switch weight {
        case .medium:   return "JetBrainsMono-Medium"
        case .semibold: return "JetBrainsMono-SemiBold"
        default:        return "JetBrainsMono-Regular"
        }
    }
}

// MARK: - Color Hex Extension

extension Color {
    /// Initialises a `Color` from a CSS-style hex string (e.g. `"#ff0080"` or `"ff0080"`).
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))

        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)

        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
