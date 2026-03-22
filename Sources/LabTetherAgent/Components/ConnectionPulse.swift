import SwiftUI

/// A triple-ring radiating animation for active connection states.
/// Port of the iOS `LTConnectionPulse` pattern — outer ring fades while expanding,
/// core dot stays solid. Use for reconnecting/connecting states.
struct LTConnectionPulse: View {
    let color: Color
    var size: CGFloat = 8

    @State private var pulse = false
    @Environment(\.animationsActive) private var animationsActive

    var body: some View {
        ZStack {
            // Outer radiating ring
            Circle()
                .stroke(color.opacity(pulse ? 0 : 0.35), lineWidth: 0.5)
                .frame(
                    width: size * (pulse ? 3.0 : 1.0),
                    height: size * (pulse ? 3.0 : 1.0)
                )

            // Inner radiating ring (offset timing via opacity)
            Circle()
                .stroke(color.opacity(pulse ? 0.1 : 0.3), lineWidth: 0.5)
                .frame(
                    width: size * (pulse ? 2.0 : 1.0),
                    height: size * (pulse ? 2.0 : 1.0)
                )

            // Core dot
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .shadow(color: color.opacity(0.6), radius: 3)
        }
        .onAppear {
            guard animationsActive else { return }
            withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
        .onChange(of: animationsActive) { active in
            if !active { pulse = false }
        }
    }
}
