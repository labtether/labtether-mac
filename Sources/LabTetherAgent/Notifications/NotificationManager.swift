import Foundation
import UserNotifications

/// Notification events for agent state transitions.
enum AgentNotification {
    case connected
    case disconnected
    case enrolled
    case connectionLost
    case screenSharingDisabled
    case screenSharingObserveOnly
    case crashRestart(attempt: Int)
    case crashLoopDetected
    case alertFiring(title: String, severity: String)
    case alertResolved(title: String)

    var title: String {
        switch self {
        case .connected:              return "LabTether Agent Connected"
        case .disconnected:           return "LabTether Agent Disconnected"
        case .enrolled:               return "LabTether Agent Enrolled"
        case .connectionLost:         return "LabTether Connection Lost"
        case .screenSharingDisabled:  return "Screen Sharing Not Enabled"
        case .screenSharingObserveOnly: return "Screen Sharing: Observe Only"
        case .crashRestart:           return "LabTether Agent Restarting"
        case .crashLoopDetected:      return "LabTether Agent Crash Loop"
        case .alertFiring(let title, _): return "Alert: \(title)"
        case .alertResolved:          return "Alert Resolved"
        }
    }

    var body: String {
        switch self {
        case .connected:              return "Successfully connected to the hub."
        case .disconnected:           return "Agent process has stopped."
        case .enrolled:               return "Agent has been enrolled with the hub."
        case .connectionLost:         return "Connection to hub lost. Attempting to reconnect..."
        case .screenSharingDisabled:  return "Enable Screen Sharing in System Settings to allow remote desktop access from the web console."
        case .screenSharingObserveOnly: return "Screen Sharing is in observe-only mode. Remote mouse and keyboard input will not work. Grant control access to fix this."
        case .crashRestart(let n):    return "Agent crashed unexpectedly. Auto-restarting (attempt \(n))..."
        case .crashLoopDetected:      return "Agent has crashed repeatedly. Auto-restart disabled. Check logs and restart manually."
        case .alertFiring(let title, let severity): return "[\(severity.uppercased())] \(title)"
        case .alertResolved(let title): return "\(title) is back to normal."
        }
    }
}

/// Manages macOS notifications for agent state transitions.
final class NotificationManager {
    private var authorized = false
    /// UNUserNotificationCenter requires a valid app bundle. When running
    /// as a bare executable (e.g. `swift run` or `.build/debug/`), the
    /// bundle proxy is nil and calling `.current()` crashes. We detect
    /// this and silently disable notifications instead.
    private let available: Bool

    init() {
        self.available = Bundle.main.bundleIdentifier != nil && !Bundle.main.bundleIdentifier!.isEmpty
        if available {
            requestAuthorization()
        }
    }

    func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            self.authorized = granted
        }
    }

    func notify(_ event: AgentNotification) {
        guard available, authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "labtether-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
