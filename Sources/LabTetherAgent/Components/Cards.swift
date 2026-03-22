import SwiftUI

// MARK: - LTGlassCard

/// A premium glass-morphism card container.
///
/// Wrap any content in an `LTGlassCard` to apply the panel glass fill,
/// a thin border stroke, a specular top-edge highlight, and a subtle drop shadow.
/// Pass a `glowColor` to tint the border with the semantic accent of the content.
/// Hover lift is opt-in so large cards inside scroll views stay smooth on macOS.
struct LTGlassCard<Content: View>: View {
    let glowColor: Color?
    let hoverEffect: Bool
    @ViewBuilder let content: () -> Content

    @State private var isHovered = false

    /// Creates an `LTGlassCard`.
    /// - Parameters:
    ///   - glowColor: Optional tint applied to the border at 30 % opacity.
    ///                Defaults to `LT.panelBorder` when `nil`.
    ///   - hoverEffect: When `true`, enables the hover lift/shadow treatment.
    ///                  Defaults to `false` to avoid scroll-induced hover churn.
    ///   - content:   The view hierarchy to display inside the card.
    init(
        glowColor: Color? = nil,
        hoverEffect: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.glowColor = glowColor
        self.hoverEffect = hoverEffect
        self.content = content
    }

    var body: some View {
        let hovered = hoverEffect && isHovered
        content()
            .padding(LT.space12)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: LT.radiusMd, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(hovered ? 0.08 : 0.055),
                                    hovered ? LT.panelGlassElevated : LT.panelGlass,
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    // Inner glow when glowColor is set — subtle radial wash
                    if let glow = glowColor {
                        RadialGradient(
                            colors: [glow.opacity(hovered ? 0.07 : 0.05), Color.clear],
                            center: UnitPoint(x: 0.2, y: 0.1),
                            startRadius: 0,
                            endRadius: hovered ? 135 : 120
                        )
                        .clipShape(RoundedRectangle(cornerRadius: LT.radiusMd, style: .continuous))
                    }
                }
            )
            // Hairline border — 0.5pt for glass delicacy
            .overlay(
                RoundedRectangle(cornerRadius: LT.radiusMd, style: .continuous)
                    .strokeBorder(
                        glowColor.map { $0.opacity(hovered ? 0.45 : 0.3) } ?? LT.panelBorder,
                        lineWidth: glowColor != nil ? 0.75 : 0.5
                    )
            )
            .shadow(color: Color.black.opacity(hovered ? 0.26 : 0.18), radius: hovered ? 8 : 6, x: 0, y: hovered ? 4 : 3)
            .offset(y: hovered ? LT.hoverLift : 0)
            .onHover { hovering in
                guard hoverEffect else { return }
                isHovered = hovering
            }
            .animation(.easeInOut(duration: LT.animFast), value: isHovered)
    }
}

// MARK: - View Extensions

extension View {
    /// Applies the `LT.bg` OLED-black background with subtle noise texture.
    ///
    /// The noise is generated with a deterministic LCG so the output is stable
    /// across renders, allowing SwiftUI to cache it. `.drawingGroup()` rasterizes
    /// the Canvas to a Metal texture so it is not re-executed every frame.
    func ltGlassBackground() -> some View {
        background(
            ZStack {
                LT.bg
                // Deterministic noise texture — renders once, cacheable by SwiftUI
                Canvas { context, size in
                    let step: CGFloat = 6
                    var seed: UInt64 = 0x9E3779B97F4A7C15
                    let cols = Int(size.width / step) + 1
                    let rows = Int(size.height / step) + 1
                    for row in 0..<rows {
                        for col in 0..<cols {
                            seed = seed &* 6364136223846793005 &+ 1442695040888963407
                            let hash = Double((seed >> 33) & 0xFF) / 255.0
                            if hash < 0.15 {
                                let opacity = 0.01 + hash * 0.2
                                context.fill(
                                    Path(CGRect(
                                        x: CGFloat(col) * step + CGFloat(seed & 0x3),
                                        y: CGFloat(row) * step + CGFloat((seed >> 2) & 0x3),
                                        width: 1, height: 1
                                    )),
                                    with: .color(.white.opacity(opacity))
                                )
                            }
                        }
                    }
                }
                .drawingGroup()
            }
        )
    }
}
