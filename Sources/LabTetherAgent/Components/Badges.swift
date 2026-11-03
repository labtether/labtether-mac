import SwiftUI

// MARK: - LTStatusDot

/// A plain status dot. Colour carries the state; there is no glow or pulse.
struct LTStatusDot: View {
    let color: Color
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

// MARK: - Severity

/// Colours for an alert severity, as the Hub console draws them.
enum LTSeverity {
    /// Dot colour: critical is red, every other firing severity is amber.
    static func dotColor(for severity: String) -> Color {
        severity == "critical" ? LT.bad : (severity == "low" ? LT.text3 : LT.warn)
    }
}
