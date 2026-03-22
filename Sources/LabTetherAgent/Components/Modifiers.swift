import SwiftUI

// MARK: - LTStaggeredEntrance

/// A `ViewModifier` that animates a view in with a staggered spring slide-up + fade.
///
/// Apply via `.ltStaggered(_ index:)` on any view inside a list or stack
/// to create a cascading entrance effect when the parent appears.
/// Uses spring animation for a snappier, more premium feel than linear easing.
struct LTStaggeredEntrance: ViewModifier {
    let index: Int

    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .offset(y: appeared ? 0 : 12)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(
                    .spring(response: 0.5, dampingFraction: 0.85)
                    .delay(Double(min(index, 12)) * 0.04)
                ) {
                    appeared = true
                }
            }
    }
}

// MARK: - LTAnimatedBorder

/// A static gradient border that draws attention to urgent states.
///
/// Apply to glass cards or containers to signal critical alerts, pending restarts,
/// or active processes with subtle color emphasis.
struct LTAnimatedBorder: ViewModifier {
    let colors: [Color]
    let isActive: Bool
    var lineWidth: CGFloat = 1.5

    func body(content: Content) -> some View {
        let borderColors: [Color] = {
            if !isActive {
                return [Color.clear, Color.clear]
            }
            if colors.count >= 3 {
                return [colors[0].opacity(0.45), colors[1].opacity(0.2), colors[2].opacity(0.4)]
            }
            if colors.count == 2 {
                return [colors[0].opacity(0.45), colors[1].opacity(0.25), colors[0].opacity(0.35)]
            }
            if let only = colors.first {
                return [only.opacity(0.45), only.opacity(0.2)]
            }
            return [LT.accent.opacity(0.35), LT.accent.opacity(0.15)]
        }()

        content
            .overlay(
                RoundedRectangle(cornerRadius: LT.radiusMd, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: borderColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isActive ? lineWidth : 0
                    )
                    .opacity(isActive ? 1 : 0)
            )
    }
}

// MARK: - LTScanShimmer

/// A horizontal light-sweep overlay that plays once on appear, simulating a
/// scanner beam passing over the content. Port of the iOS `LTMetricCard` scan-line.
struct LTScanShimmer: ViewModifier {
    var color: Color = .white
    var delay: Double = 0.2

    @State private var swept = false

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: color.opacity(0.06), location: 0.4),
                            .init(color: color.opacity(0.10), location: 0.5),
                            .init(color: color.opacity(0.06), location: 0.6),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: swept ? geo.size.width * 1.2 : -geo.size.width * 0.6)
                }
                .clipped()
            )
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).delay(delay)) {
                    swept = true
                }
            }
    }
}

extension View {
    /// Applies a one-shot scan-line shimmer on appear.
    func ltScanShimmer(color: Color = .white, delay: Double = 0.2) -> some View {
        modifier(LTScanShimmer(color: color, delay: delay))
    }
}

// MARK: - LTValueFlash

/// A view modifier that flashes an accent-coloured glow when the watched value changes,
/// matching the web console's `value-flash` animation (600ms ease-out).
struct LTValueFlash<V: Equatable>: ViewModifier {
    let value: V
    let color: Color

    @State private var flash = false

    func body(content: Content) -> some View {
        content
            .shadow(color: flash ? color.opacity(0.6) : Color.clear, radius: flash ? 8 : 0)
            .overlay(
                RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous)
                    .fill(color.opacity(flash ? 0.08 : 0))
                    .allowsHitTesting(false)
            )
            .onChange(of: value) { _ in
                flash = true
                withAnimation(.easeOut(duration: LT.animFlash)) {
                    flash = false
                }
            }
    }
}

// MARK: - LTFocusRing

/// A view modifier that adds an accent-coloured focus glow around a field when focused,
/// matching the web console's `focus:shadow: 0 0 0 3px var(--accent-subtle)` pattern.
struct LTFocusRing: ViewModifier {
    let isFocused: Bool
    let color: Color

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous)
                    .strokeBorder(
                        isFocused ? color.opacity(0.5) : LT.panelBorder,
                        lineWidth: isFocused ? 1.5 : 1
                    )
            )
            .shadow(
                color: isFocused ? color.opacity(0.2) : Color.clear,
                radius: isFocused ? LT.focusRingRadius : 0
            )
            .animation(.easeInOut(duration: LT.animFast), value: isFocused)
    }
}

// MARK: - LTBorderTravel

/// A low-overhead gradient border inspired by the web `border-travel` style.
struct LTBorderTravel: ViewModifier {
    let isActive: Bool
    var color: Color = LT.accent

    func body(content: Content) -> some View {
        let borderOverlay = LinearGradient(
            colors: [
                color.opacity(0.25),
                color.opacity(0.05),
                color.opacity(0.18),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        return content
            .overlay(
                RoundedRectangle(cornerRadius: LT.radiusMd, style: .continuous)
                    .strokeBorder(borderOverlay, lineWidth: isActive ? 1 : 0)
                    .opacity(isActive ? 1 : 0)
            )
    }
}

// MARK: - View Extensions

extension View {
    /// Applies a staggered slide-up entrance animation with the given index offset.
    func ltStaggered(_ index: Int) -> some View {
        modifier(LTStaggeredEntrance(index: index))
    }

    /// Applies a gradient border for urgent states.
    func ltAnimatedBorder(colors: [Color], isActive: Bool, lineWidth: CGFloat = 1.5) -> some View {
        modifier(LTAnimatedBorder(colors: colors, isActive: isActive, lineWidth: lineWidth))
    }

    /// Applies a value-flash accent glow when the watched value changes.
    func ltValueFlash<V: Equatable>(watching value: V, color: Color = LT.accent) -> some View {
        modifier(LTValueFlash(value: value, color: color))
    }

    /// Applies a focus glow ring around an input field.
    func ltFocusRing(_ focused: Bool, color: Color = LT.accent) -> some View {
        modifier(LTFocusRing(isFocused: focused, color: color))
    }
}
