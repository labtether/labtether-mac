import AppKit
import SwiftUI

/// High-level visual states for the compact menu bar glyph.
enum MenuBarIconKind: String, Equatable {
    case healthy
    case connecting
    case starting
    case warning
    case critical
    case alert
    case criticalAlert
    case offline
    case error
    case stopped

    var accessibilityLabel: String {
        switch self {
        case .healthy:       return "LabTether, connected"
        case .connecting:    return "LabTether, reconnecting"
        case .starting:      return "LabTether, starting"
        case .warning:       return "LabTether, high usage"
        case .critical:      return "LabTether, usage critical"
        case .alert:         return "LabTether, alert firing"
        case .criticalAlert: return "LabTether, critical alert firing"
        case .offline:       return "LabTether, disconnected"
        case .error:         return "LabTether, token refused or error"
        case .stopped:       return "LabTether, stopped"
        }
    }

    /// The attention dot drawn on the glyph. Only states that need the person get one.
    var dot: MenuBarIconDot {
        switch self {
        case .healthy, .connecting, .starting, .offline, .stopped: return .none
        case .warning, .alert: return .warn
        case .critical, .criticalAlert, .error: return .bad
        }
    }

    /// Starting, reconnecting, offline and stopped draw the glyph at 45 % with no dot.
    var isDimmed: Bool {
        switch self {
        case .connecting, .starting, .offline, .stopped: return true
        default: return false
        }
    }
}

enum MenuBarIconDot: Equatable {
    case none
    case warn
    case bad
}

enum MenuBarIconResolver {
    static func resolve(
        statusState: ConnectionState,
        hubConnectionState: String,
        isReachable: Bool,
        metrics: MetricsSnapshot?,
        hasFiringAlerts: Bool,
        hasCriticalAlert: Bool = false
    ) -> MenuBarIconKind {
        if hasFiringAlerts {
            return hasCriticalAlert ? .criticalAlert : .alert
        }

        if hubConnectionState == "auth_failed" {
            return .error
        }

        if let metrics, isReachable {
            if metrics.cpuPercent > 95 || metrics.memoryPercent > 95 || metrics.diskPercent > 95 {
                return .critical
            }
            if metrics.cpuPercent > 80 || metrics.memoryPercent > 85 || metrics.diskPercent > 90 {
                return .warning
            }

            switch hubConnectionState {
            case "connected":
                return .healthy
            case "connecting":
                return .connecting
            default:
                return .offline
            }
        }

        switch statusState {
        case .connected:
            return .healthy
        case .reconnecting, .enrolling:
            return .connecting
        case .starting:
            return .starting
        case .stopped:
            return .stopped
        case .authFailed, .error:
            return .error
        }
    }
}

// MARK: - Glyph

/// The menu bar glyph, drawn from the mascot: body, screen with a cut-out face,
/// slot and button. Plain states are template images so macOS tints them for the
/// menu bar; states with an attention dot draw the glyph in the label colour.
enum MenuBarGlyph {
    static let size = NSSize(width: 18, height: 18)
    private static var cache: [MenuBarIconKind: NSImage] = [:]

    static func image(for kind: MenuBarIconKind) -> NSImage {
        if let cached = cache[kind] { return cached }
        let dot = kind.dot
        let alpha: CGFloat = kind.isDimmed ? 0.45 : 1
        let image = NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let glyphColor = dot == .none ? NSColor.black : NSColor.labelColor
            draw(in: context, glyphColor: glyphColor.withAlphaComponent(alpha), dot: dot)
            return true
        }
        image.isTemplate = dot == .none
        image.accessibilityDescription = kind.accessibilityLabel
        cache[kind] = image
        return image
    }

    /// Draws in an 18 × 18 point space with y growing downwards.
    static func draw(in context: CGContext, glyphColor: NSColor, dot: MenuBarIconDot) {
        context.saveGState()
        context.beginTransparencyLayer(auxiliaryInfo: nil)

        glyphColor.setStroke()
        glyphColor.setFill()

        let body = NSBezierPath(roundedRect: NSRect(x: 2.25, y: 1.75, width: 13.5, height: 14.5), xRadius: 3.25, yRadius: 3.25)
        body.lineWidth = 1.5
        body.stroke()

        NSBezierPath(roundedRect: NSRect(x: 4.5, y: 4.25, width: 9, height: 6.75), xRadius: 1.5, yRadius: 1.5).fill()

        let slot = NSBezierPath()
        slot.move(to: NSPoint(x: 5.5, y: 13.4))
        slot.line(to: NSPoint(x: 8, y: 13.4))
        slot.lineWidth = 1.5
        slot.lineCapStyle = .round
        slot.stroke()

        NSBezierPath(ovalIn: NSRect(x: 12.3 - 1.05, y: 13.4 - 1.05, width: 2.1, height: 2.1)).fill()

        // The face is cut out of the screen. At @1x the three small arcs blur
        // together, so the glyph keeps only slightly heavier eyes there.
        let isLowResolution = abs(context.userSpaceToDeviceSpaceTransform.a) < 1.5
        let eyeWidth: CGFloat = isLowResolution ? 1.3 : 1.1
        setClear(true, context: context)
        strokeQuad(from: NSPoint(x: 6.4, y: 7.55), control: NSPoint(x: 7.3, y: 6.15), to: NSPoint(x: 8.2, y: 7.55), width: eyeWidth)
        strokeQuad(from: NSPoint(x: 9.8, y: 7.55), control: NSPoint(x: 10.7, y: 6.15), to: NSPoint(x: 11.6, y: 7.55), width: eyeWidth)
        if !isLowResolution {
            strokeQuad(from: NSPoint(x: 7.7, y: 9.05), control: NSPoint(x: 9.0, y: 10.15), to: NSPoint(x: 10.3, y: 9.05), width: 1.0)
        }

        if dot != .none {
            // A clear ring keeps the dot readable on top of the body outline.
            NSBezierPath(ovalIn: NSRect(x: 15 - 3.6, y: 3 - 3.6, width: 7.2, height: 7.2)).fill()
            setClear(false, context: context)
            NSColor(dot == .bad ? LT.bad : LT.warn).setFill()
            NSBezierPath(ovalIn: NSRect(x: 15 - 2.3, y: 3 - 2.3, width: 4.6, height: 4.6)).fill()
        }

        setClear(false, context: context)
        context.endTransparencyLayer()
        context.restoreGState()
    }

    private static func setClear(_ clear: Bool, context: CGContext) {
        NSGraphicsContext.current?.compositingOperation = clear ? .clear : .sourceOver
        context.setBlendMode(clear ? .clear : .normal)
    }

    private static func strokeQuad(from start: NSPoint, control: NSPoint, to end: NSPoint, width: CGFloat) {
        let path = NSBezierPath()
        path.move(to: start)
        // A quadratic curve written as the equivalent cubic (macOS 13 has no quadratic API).
        path.curve(
            to: end,
            controlPoint1: NSPoint(x: start.x + (control.x - start.x) * 2 / 3, y: start.y + (control.y - start.y) * 2 / 3),
            controlPoint2: NSPoint(x: end.x + (control.x - end.x) * 2 / 3, y: end.y + (control.y - end.y) * 2 / 3)
        )
        path.lineWidth = width
        path.lineCapStyle = .round
        path.stroke()
    }
}
