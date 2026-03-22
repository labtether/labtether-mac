import SwiftUI

/// A circular progress ring with animated fill, matching the iOS `LTProgressRing` component.
struct LTProgressRing: View {
    let value: Double
    var color: Color = LT.ok
    var size: CGFloat = 44
    var lineWidth: CGFloat = 4
    var accessibilityName: String = "Progress"

    @State private var displayValue: Double = 0

    private var fraction: Double {
        guard displayValue.isFinite else { return 0 }
        return max(0, min(1, displayValue / 100.0))
    }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: lineWidth)

            // Fill
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.5), color],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.4), radius: 4)

            // Value
            Text("\(Int(displayValue.rounded()))%")
                .font(LT.mono(size * 0.22, weight: .semibold))
                .foregroundStyle(color)
                .contentTransition(.numericText())
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                displayValue = value
            }
        }
        .onChange(of: value) { newValue in
            withAnimation(.easeInOut(duration: 0.4)) {
                displayValue = newValue
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue("\(Int(value * 100)) percent")
        .accessibilityAddTraits(.updatesFrequently)
    }
}
