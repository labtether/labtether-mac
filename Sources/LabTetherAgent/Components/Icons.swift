import SwiftUI

// MARK: - LTIcon

/// A 16 pt outlined icon. SF Symbols draw "display" and "doc.on.clipboard" with a
/// filled layer on current macOS, so those two are drawn here as outlines
/// ("lt.display", "lt.clipboard"); every other name is an SF Symbol.
struct LTIcon: View {
    let name: String
    var color: Color = LT.text3

    var body: some View {
        Group {
            switch name {
            case "lt.display":
                OutlineIconShape(kind: .display).stroke(color, style: Self.stroke)
            case "lt.clipboard":
                OutlineIconShape(kind: .clipboard).stroke(color, style: Self.stroke)
            default:
                Image(systemName: name)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(color)
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }

    private static let stroke = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
}

/// Outlines drawn in a 16 × 16 space, as in the 2.0 mockups.
private struct OutlineIconShape: Shape {
    enum Kind { case display, clipboard }
    let kind: Kind

    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 16
        var path = Path()
        switch kind {
        case .display:
            path.addRoundedRect(in: CGRect(x: 1.75, y: 2.75, width: 12.5, height: 8.5), cornerSize: CGSize(width: 1.5, height: 1.5))
            path.move(to: CGPoint(x: 5.5, y: 13.75)); path.addLine(to: CGPoint(x: 10.5, y: 13.75))
            path.move(to: CGPoint(x: 8, y: 11.25)); path.addLine(to: CGPoint(x: 8, y: 13.75))
        case .clipboard:
            path.move(to: CGPoint(x: 5.75, y: 2.75))
            path.addLine(to: CGPoint(x: 4.5, y: 2.75))
            path.addQuadCurve(to: CGPoint(x: 3.25, y: 4), control: CGPoint(x: 3.25, y: 2.75))
            path.addLine(to: CGPoint(x: 3.25, y: 13))
            path.addQuadCurve(to: CGPoint(x: 4.5, y: 14.25), control: CGPoint(x: 3.25, y: 14.25))
            path.addLine(to: CGPoint(x: 11.5, y: 14.25))
            path.addQuadCurve(to: CGPoint(x: 12.75, y: 13), control: CGPoint(x: 12.75, y: 14.25))
            path.addLine(to: CGPoint(x: 12.75, y: 4))
            path.addQuadCurve(to: CGPoint(x: 11.5, y: 2.75), control: CGPoint(x: 12.75, y: 2.75))
            path.addLine(to: CGPoint(x: 10.25, y: 2.75))
            path.addRoundedRect(in: CGRect(x: 5.75, y: 1.5, width: 4.5, height: 2.5), cornerSize: CGSize(width: 0.75, height: 0.75))
            path.move(to: CGPoint(x: 5.75, y: 8)); path.addLine(to: CGPoint(x: 10.25, y: 8))
            path.move(to: CGPoint(x: 5.75, y: 10.75)); path.addLine(to: CGPoint(x: 8.75, y: 10.75))
        }
        return path.applying(CGAffineTransform(scaleX: unit, y: unit).translatedBy(x: rect.minX / unit, y: rect.minY / unit))
    }
}
