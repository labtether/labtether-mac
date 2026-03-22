import SwiftUI

// MARK: - LTEmptyState

/// A branded empty state with breathing glow icon, matching the iOS LTEmptyState pattern.
struct LTEmptyState: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var color: Color = LT.textMuted

    @State private var breathe = false
    @Environment(\.animationsActive) private var animationsActive

    var body: some View {
        VStack(spacing: LT.space16) {
            ZStack {
                Circle()
                    .fill(color.opacity(breathe ? 0.12 : 0.04))
                    .frame(width: 64, height: 64)

                Image(systemName: icon)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(color.opacity(breathe ? 0.6 : 0.4))
            }
            .animation(
                .easeInOut(duration: LT.breatheDuration).repeatForever(autoreverses: true),
                value: breathe
            )

            VStack(spacing: LT.space4) {
                Text(title)
                    .font(LT.inter(13, weight: .medium))
                    .foregroundStyle(LT.textSecondary)
                if let subtitle {
                    Text(subtitle)
                        .font(LT.inter(11))
                        .foregroundStyle(LT.textMuted)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LT.space24)
        .onAppear { if animationsActive { breathe = true } }
        .onChange(of: animationsActive) { active in breathe = active }
    }
}

// MARK: - LTShimmer

/// A shimmer loading placeholder that sweeps a light gradient horizontally,
/// matching the web console's `shimmer` keyframe (1.5s ease-in-out infinite).
struct LTShimmer: View {
    var height: CGFloat = 16
    var cornerRadius: CGFloat = LT.radiusSm

    @State private var phase: CGFloat = -1
    @Environment(\.animationsActive) private var animationsActive

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.04))
            .frame(height: height)
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: Color.white.opacity(0.06), location: 0.4),
                            .init(color: Color.white.opacity(0.10), location: 0.5),
                            .init(color: Color.white.opacity(0.06), location: 0.6),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: geo.size.width * phase)
                }
                .clipped()
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onAppear {
                guard animationsActive else { return }
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 2
                }
            }
            .onChange(of: animationsActive) { active in
                if !active { phase = -1 }
            }
    }
}

// MARK: - LTToast

/// A floating toast notification that slides in from the top with a glass background.
/// Used for copy-to-clipboard feedback and transient status messages.
struct LTToast: View {
    let text: String
    var icon: String = "checkmark.circle.fill"
    var color: Color = LT.ok

    var body: some View {
        HStack(spacing: LT.space6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.4), radius: 3)

            Text(text)
                .font(LT.inter(11, weight: .medium))
                .foregroundStyle(LT.textPrimary)
        }
        .padding(.horizontal, LT.space12)
        .padding(.vertical, LT.space6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.3), radius: 12, y: 4)
        )
        .overlay(
            Capsule()
                .strokeBorder(color.opacity(0.25), lineWidth: 0.5)
        )
    }
}
