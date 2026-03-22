import SwiftUI

/// A lightweight sparkline tuned for frequent metric updates.
struct LTSparkline: View {
    let series: SparklineSeries
    var color: Color = LT.accent
    var height: CGFloat = 24

    var body: some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
            guard series.normalizedValues.count > 1 else { return }

            let linePath = sparklineLinePath(size: size)
            let areaPath = sparklineAreaPath(size: size, linePath: linePath)

            context.fill(
                areaPath,
                with: .linearGradient(
                    Gradient(colors: [color.opacity(0.10), color.opacity(0.0)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )
            context.stroke(
                linePath,
                with: .color(color.opacity(0.95)),
                style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func sparklineLinePath(size: CGSize) -> Path {
        Path { path in
            for (index, value) in series.normalizedValues.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(series.normalizedValues.count - 1)
                let y = size.height * (1 - CGFloat(value))
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
    }

    private func sparklineAreaPath(size: CGSize, linePath: Path) -> Path {
        var path = linePath
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        return path
    }
}
