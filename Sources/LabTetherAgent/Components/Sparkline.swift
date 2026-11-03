import SwiftUI

/// A lightweight sparkline tuned for frequent metric updates: one hue, flat fill.
struct LTSparkline: View {
    let series: SparklineSeries
    var color: Color = LT.chart
    var fill: Color? = LT.chartFill
    var height: CGFloat = 28

    var body: some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
            guard series.normalizedValues.count > 1 else { return }
            let line = linePath(size: size)
            if let fill {
                var area = line
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.addLine(to: CGPoint(x: 0, y: size.height))
                area.closeSubpath()
                context.fill(area, with: .color(fill))
            }
            context.stroke(
                line,
                with: .color(color),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A smooth line through the points (midpoint quadratic curves), inset so the stroke is not clipped.
    private func linePath(size: CGSize) -> Path {
        let values = series.normalizedValues
        let inset: CGFloat = 2
        let points = values.enumerated().map { index, value in
            CGPoint(
                x: size.width * CGFloat(index) / CGFloat(values.count - 1),
                y: inset + (size.height - inset * 2) * (1 - CGFloat(value))
            )
        }
        return Path { path in
            path.move(to: points[0])
            for index in 1..<points.count {
                let previous = points[index - 1]
                let current = points[index]
                let mid = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
                path.addQuadCurve(to: mid, control: previous)
                if index == points.count - 1 {
                    path.addQuadCurve(to: current, control: current)
                }
            }
        }
    }
}
