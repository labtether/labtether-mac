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
        case .connected:                 return "LabTether connected"
        case .disconnected:              return "LabTether stopped"
        case .enrolled:                  return "LabTether enrolled"
        case .connectionLost:            return "Hub connection lost"
        case .screenSharingDisabled:     return "Screen Sharing is off"
        case .screenSharingObserveOnly:  return "Screen Sharing is observe only"
        case .crashRestart:              return "LabTether agent restarting"
        case .crashLoopDetected:         return "LabTether agent stopped"
        case .alertFiring(let title, _): return title
        case .alertResolved:             return "Alert resolved"
        }
    }

    var body: String {
        switch self {
        case .connected:                return "Connected to the Hub."
        case .disconnected:             return "The agent process stopped."
        case .enrolled:                 return "This Mac is enrolled with the Hub."
        case .connectionLost:           return "Reconnecting."
        case .screenSharingDisabled:    return "Remote View needs Screen Sharing. Turn it on in System Settings > General > Sharing."
        case .screenSharingObserveOnly: return "Remote mouse and keyboard input is off."
        case .crashRestart(let n):      return "The agent quit unexpectedly. Restart \(n) is starting."
        case .crashLoopDetected:        return "The agent quit several times in a row, so it was not restarted."
        case .alertFiring(_, let severity): return "\(Self.severityWord(severity)) alert"
        case .alertResolved(let title): return title
        }
    }

    private static func severityWord(_ severity: String) -> String {
        let word = severity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = word.first else { return "New" }
        return first.uppercased() + word.dropFirst().lowercased()
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

    init(requestAuthorization: Bool = true, allowSystemIntegration: Bool = true) {
        self.available = allowSystemIntegration && Bundle.main.bundleIdentifier != nil && !Bundle.main.bundleIdentifier!.isEmpty
        if available && requestAuthorization {
            self.requestAuthorization()
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
