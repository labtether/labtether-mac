import SwiftUI

/// A three-layer breathing health orb with specular highlight and variable pulse rate.
///
/// Use this to represent the overall health of a system or service at a glance.
/// The outer glow breathes; the mid ring adds depth; the inner dot features a
/// specular highlight at UnitPoint(0.35, 0.35) matching the iOS app's premium orb.
struct LTHealthOrb: View {
    let color: Color
    let size: CGFloat
    var animated: Bool
    /// Breathing cycle duration. Defaults to `LT.breatheDuration` (3 s).
    /// Use shorter durations (e.g. 2 s for warnings, 1.5 s for critical) to
    /// convey urgency through visual cadence.
    var breatheDuration: Double = LT.breatheDuration
    var accessibilityDescription: String = "Connection health"

    @State private var breathe = false
    @Environment(\.animationsActive) private var animationsActive

    init(color: Color, size: CGFloat, animated: Bool = true, breatheDuration: Double = LT.breatheDuration) {
        self.color = color
        self.size = size
        self.animated = animated
        self.breatheDuration = breatheDuration
    }

    var body: some View {
        ZStack {
            // Outer glow — breathing opacity (dim at rest, bright at peak)
            RadialGradient(
                colors: [color.opacity(0.18), Color.clear],
                center: .center,
                startRadius: 0,
                endRadius: size
            )
            .frame(width: size * 2.2, height: size * 2.2)
            .opacity(animated ? (breathe ? 0.7 : 0.2) : 0.32)
            .animation(
                animated ? .easeInOut(duration: breatheDuration).repeatForever(autoreverses: true) : nil,
                value: breathe
            )

            // Mid ring — breathing shadow radius
            RadialGradient(
                colors: [color.opacity(0.3), color.opacity(0.05)],
                center: .center,
                startRadius: 0,
                endRadius: size * 0.55
            )
            .frame(width: size, height: size)

            // Inner dot with specular highlight at upper-left
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.35), color.opacity(0.95), color.opacity(0.7)],
                        center: UnitPoint(x: 0.3, y: 0.3),
                        startRadius: 0,
                        endRadius: size * 0.22
                    )
                )
                .frame(width: size * 0.38, height: size * 0.38)
                .shadow(color: color.opacity(0.45), radius: 6)
        }
        .onAppear { breathe = animated && animationsActive }
        .onChange(of: animationsActive) { active in
            breathe = animated && active
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
