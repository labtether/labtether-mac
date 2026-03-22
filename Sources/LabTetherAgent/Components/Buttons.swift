import SwiftUI

// MARK: - LTPillButton

/// An accent-coloured capsule button with hover brightening, press-scale feedback, and glow shadow.
struct LTPillButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    @State private var isHovered = false

    init(_ title: String, icon: String, color: Color = LT.accent, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: LT.space4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(LT.inter(11, weight: .semibold))
            }
            .foregroundStyle(color)
            .padding(.horizontal, LT.space12)
            .padding(.vertical, LT.space4 + 2)
            .background(
                Capsule()
                    .fill(color.opacity(isHovered ? 0.22 : 0.14))
            )
            .overlay(
                Capsule()
                    .strokeBorder(color.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: color.opacity(isHovered ? 0.4 : 0.2), radius: isHovered ? 10 : 4)
        }
        .buttonStyle(LTPressButtonStyle())
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: LT.animFast), value: isHovered)
    }
}

/// Press-scale button style providing tactile press-down feedback.
struct LTPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? LT.pressScale : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(LT.springSnappy, value: configuration.isPressed)
    }
}

// MARK: - LTIconBox

/// A rounded-rect icon container with a tinted background, used for section heroes
/// and leading indicators in cards.
struct LTIconBox: View {
    let icon: String
    var color: Color = LT.accent
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.18), color.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: color.opacity(0.2), radius: 3, y: 1)
            Image(systemName: icon)
                .font(.system(size: size * 0.43, weight: .semibold))
                .foregroundStyle(color)
        }
    }
}

// MARK: - LTMiniActionButton

/// A compact circular icon button for inline agent controls (start/stop/restart).
/// Renders as a 28x28 tinted circle with hover brightening and press-scale feedback.
struct LTMiniActionButton: View {
    let icon: String
    let color: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(color.opacity(isHovered ? 0.22 : 0.12))
                )
                .overlay(
                    Circle()
                        .strokeBorder(color.opacity(0.3), lineWidth: 0.5)
                )
                .shadow(color: color.opacity(isHovered ? 0.35 : 0.15), radius: isHovered ? 6 : 3)
        }
        .buttonStyle(LTPressButtonStyle())
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: LT.animFast), value: isHovered)
    }
}
