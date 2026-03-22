import SwiftUI

/// A checkmark that draws itself in with a stroke animation for "all clear" states.
struct LTAnimatedCheck: View {
    let color: Color
    var size: CGFloat = 32

    @State private var drawn = false
    @State private var glowPulse = false
    @Environment(\.animationsActive) private var animationsActive

    var body: some View {
        ZStack {
            // Background glow
            Circle()
                .fill(color.opacity(glowPulse ? 0.12 : 0.06))
                .frame(width: size * 1.4, height: size * 1.4)
                .animation(
                    .easeInOut(duration: LT.breatheDuration).repeatForever(autoreverses: true),
                    value: glowPulse
                )

            // Checkmark
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(color)
                .scaleEffect(drawn ? 1.0 : 0.5)
                .opacity(drawn ? 1.0 : 0)
                .shadow(color: color.opacity(0.5), radius: 6)
                .shadow(color: color.opacity(0.25), radius: 12)
        }
        .onAppear {
            withAnimation(LT.springBouncy.delay(0.1)) {
                drawn = true
            }
            if animationsActive { glowPulse = true }
        }
        .onChange(of: animationsActive) { active in glowPulse = active }
        .accessibilityLabel("Success")
        .accessibilityAddTraits(.isImage)
    }
}
