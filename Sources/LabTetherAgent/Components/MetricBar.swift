import SwiftUI

/// A low-cost horizontal metric fill intended for the live 5s polling path.
struct LTMetricBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 6
    var cornerRadius: CGFloat = 3
    var accessibilityName: String = "Metric"

    private var clampedFraction: CGFloat {
        CGFloat(min(max(fraction, 0), 1))
    }

    private var visibleScale: CGFloat {
        guard clampedFraction > 0 else { return 0 }
        return max(clampedFraction, 0.04)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.06))

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.8), color],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .scaleEffect(x: visibleScale, y: 1, anchor: .leading)
                .opacity(clampedFraction == 0 ? 0 : 1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue("\(Int(fraction * 100)) percent")
        .accessibilityAddTraits(.updatesFrequently)
    }
}
