import SwiftUI

// MARK: - LTStatusDot

/// A small glowing status dot with a dual shadow halo.
///
/// Prefer `LTStatusDot` over a plain filled `Circle` wherever a semantic
/// status colour needs to be communicated, as the glow layers convey urgency.
struct LTStatusDot: View {
    let color: Color
    let size: CGFloat
    var pulsing: Bool
    var pulseSpeed: Double

    @State private var pulse = false
    @Environment(\.animationsActive) private var animationsActive

    /// Creates an `LTStatusDot`.
    /// - Parameters:
    ///   - color:      The semantic colour for this status indicator.
    ///   - size:       Diameter of the dot. Defaults to 8 pt.
    ///   - pulsing:    When `true`, a radiating ring expands outward to signal activity.
    ///   - pulseSpeed: Duration in seconds for one pulse cycle. Defaults to 2 s.
    init(color: Color, size: CGFloat = 8, pulsing: Bool = false, pulseSpeed: Double = 2.0) {
        self.color = color
        self.size = size
        self.pulsing = pulsing
        self.pulseSpeed = pulseSpeed
    }

    var body: some View {
        ZStack {
            // Radiating pulse ring
            if pulsing {
                Circle()
                    .stroke(color.opacity(pulse ? 0 : 0.4), lineWidth: 1)
                    .frame(width: size * (pulse ? 2.5 : 1.0), height: size * (pulse ? 2.5 : 1.0))
                    .animation(
                        .easeOut(duration: pulseSpeed).repeatForever(autoreverses: false),
                        value: pulse
                    )
            }

            // Core dot
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .shadow(color: color.opacity(0.7), radius: 3)
                .shadow(color: color.opacity(0.35), radius: 6)
        }
        .onAppear {
            if pulsing && animationsActive { pulse = true }
        }
        .onChange(of: pulsing) { active in
            pulse = active && animationsActive
        }
        .onChange(of: animationsActive) { active in
            pulse = active && pulsing
        }
    }
}

// MARK: - LTSeverityEdge

/// A 3pt colored leading edge bar for list rows, signaling severity via color.
/// Matches the iOS/web pattern of scanning severity down the left edge.
struct LTSeverityEdge: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(color)
            .frame(width: 3)
            .shadow(color: color.opacity(0.4), radius: 3)
    }
}

// MARK: - LTCapsuleBadge

/// A premium capsule badge with optional border glow, used for PID tags,
/// status labels, and inline metadata.
struct LTCapsuleBadge: View {
    let text: String
    var color: Color = LT.accent
    var withGlow: Bool = false

    var body: some View {
        Text(text)
            .font(LT.mono(9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, LT.space6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.3), lineWidth: 0.5))
            .shadow(color: withGlow ? color.opacity(0.2) : .clear, radius: 4)
    }
}
