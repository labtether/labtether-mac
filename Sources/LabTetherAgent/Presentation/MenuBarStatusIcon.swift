import SwiftUI

/// High-level visual states for the compact menu bar glyph.
enum MenuBarIconKind: String, Equatable {
    case healthy
    case connecting
    case starting
    case warning
    case critical
    case alert
    case offline
    case error
    case stopped

    var accessibilityLabel: String {
        switch self {
        case .healthy:    return "LabTether connected"
        case .connecting: return "LabTether reconnecting"
        case .starting:   return "LabTether starting"
        case .warning:    return "LabTether connected with warning"
        case .critical:   return "LabTether critical"
        case .alert:      return "LabTether alert"
        case .offline:    return "LabTether disconnected"
        case .error:      return "LabTether error"
        case .stopped:    return "LabTether stopped"
        }
    }

    var badgeColor: Color {
        switch self {
        case .healthy:    return LT.ok
        case .connecting: return LT.warn
        case .starting:   return LT.accent
        case .warning:    return LT.warn
        case .critical:   return LT.bad
        case .alert:      return LT.bad
        case .offline:    return LT.textSecondary
        case .error:      return LT.bad
        case .stopped:    return LT.textMuted
        }
    }

    var coreOpacity: Double {
        switch self {
        case .offline, .stopped: return 0.72
        default: return 0.92
        }
    }
}

enum MenuBarIconResolver {
    static func resolve(
        statusState: ConnectionState,
        hubConnectionState: String,
        isReachable: Bool,
        metrics: MetricsSnapshot?,
        hasFiringAlerts: Bool
    ) -> MenuBarIconKind {
        if hasFiringAlerts {
            return .alert
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
            case "auth_failed":
                return .error
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
        case .error:
            return .error
        }
    }
}

/// Small custom LabTether glyph for the menu bar that keeps a stable silhouette
/// and moves state changes into a badge instead of slashing the whole icon.
struct LTMenuBarStatusIcon: View {
    let kind: MenuBarIconKind

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            tetherGlyph
            badge
                .offset(x: 1, y: 1)
        }
        .frame(width: 18, height: 14)
        .accessibilityLabel(kind.accessibilityLabel)
        .accessibilityIdentifier("menubar-status-icon")
    }

    private var tetherGlyph: some View {
        let core = Color.primary.opacity(kind.coreOpacity)

        return Image(systemName: "point.3.filled.connected.trianglepath.dotted")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(core)
            .frame(width: 14, height: 10, alignment: .center)
    }

    @ViewBuilder
    private var badge: some View {
        switch kind {
        case .healthy:
            Circle()
                .fill(kind.badgeColor)
                .frame(width: 4.5, height: 4.5)

        case .connecting, .starting, .offline:
            Circle()
                .trim(from: kind == .offline ? 0 : 0.18, to: kind == .offline ? 1 : 0.88)
                .stroke(
                    kind.badgeColor,
                    style: StrokeStyle(lineWidth: 1.35, lineCap: .round)
                )
                .frame(width: 5.6, height: 5.6)
                .rotationEffect(.degrees(kind == .offline ? 0 : -48))

        case .warning:
            ZStack {
                Circle()
                    .fill(kind.badgeColor.opacity(0.18))
                Image(systemName: "exclamationmark")
                    .font(.system(size: 5, weight: .bold))
                    .foregroundStyle(kind.badgeColor)
            }
            .frame(width: 7, height: 7)

        case .critical:
            RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                .fill(kind.badgeColor)
                .frame(width: 5.8, height: 5.8)
                .rotationEffect(.degrees(45))

        case .alert:
            ZStack {
                Circle()
                    .fill(kind.badgeColor.opacity(0.18))
                Image(systemName: "bell.fill")
                    .font(.system(size: 4.6, weight: .semibold))
                    .foregroundStyle(kind.badgeColor)
            }
            .frame(width: 7, height: 7)

        case .error:
            ZStack {
                Circle()
                    .fill(kind.badgeColor.opacity(0.18))
                Image(systemName: "xmark")
                    .font(.system(size: 4.6, weight: .bold))
                    .foregroundStyle(kind.badgeColor)
            }
            .frame(width: 7, height: 7)

        case .stopped:
            Capsule(style: .continuous)
                .fill(kind.badgeColor)
                .frame(width: 6, height: 2.1)
        }
    }
}
