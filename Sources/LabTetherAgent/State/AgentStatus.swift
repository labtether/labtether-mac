import Foundation
import SwiftUI

/// Connection states for the agent process.
enum ConnectionState: String {
    case stopped = "Stopped"
    case starting = "Starting"
    case connected = "Connected"
    case reconnecting = "Reconnecting"
    case enrolling = "Enrolling"
    case error = "Error"

    var sfSymbol: String {
        switch self {
        case .connected:    return "antenna.radiowaves.left.and.right"
        case .reconnecting: return "arrow.triangle.2.circlepath"
        case .enrolling:    return "arrow.triangle.2.circlepath"
        case .starting:     return "circle.dotted"
        case .stopped:      return "poweroff"
        case .error:        return "antenna.radiowaves.left.and.right.slash"
        }
    }

    var color: Color {
        switch self {
        case .connected:    return LT.ok
        case .reconnecting: return LT.warn
        case .enrolling:    return LT.warn
        case .starting:     return LT.accent
        case .stopped:      return LT.textMuted
        case .error:        return LT.bad
        }
    }
}

/// Observable state machine driven by AgentEvents from the LogParser.
@MainActor
final class AgentStatus: ObservableObject {
    @Published var state: ConnectionState = .stopped
    @Published var hubURL: String = ""
    @Published var assetID: String = ""
    @Published var lastEvent: String = ""
    @Published var lastError: String = ""
    @Published var pid: Int32? = nil
    @Published var startedAt: Date? = nil
    private var latestLastEvent: String = ""
    private let visibility = VisibilityGate()

    var uptime: String? {
        guard let start = startedAt else { return nil }
        let interval = Date().timeIntervalSince(start)
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    private func assignIfChanged<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<AgentStatus, T>, _ value: T) {
        if self[keyPath: keyPath] != value {
            self[keyPath: keyPath] = value
        }
    }

    private func setLastEvent(_ message: String) {
        latestLastEvent = message
        guard surfaceVisible else { return }
        assignIfChanged(\.lastEvent, message)
    }

    private func isRoutineEvent(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("heartbeat") ||
            lower.contains(" ping") ||
            lower.hasSuffix("ping") ||
            lower.contains(" pong") ||
            lower.hasSuffix("pong") ||
            lower.contains("sent ok")
    }

    private var surfaceVisible: Bool {
        visibility.anySurfaceVisible
    }

    /// Mirrors menu visibility so hidden status churn does not redraw the full menu tree.
    func setMenuVisible(_ visible: Bool) {
        guard visibility.setMenuVisible(visible) else { return }
        if visible {
            applyLatestVisibleState()
        }
    }

    /// Mirrors detached panel visibility to keep status details fresh when shown.
    func setPanelVisible(_ visible: Bool) {
        guard visibility.setPanelVisible(visible) else { return }
        if visible {
            applyLatestVisibleState()
        }
    }

    private func applyLatestVisibleState() {
        assignIfChanged(\.lastEvent, latestLastEvent)
    }

    func handleEvent(_ event: AgentEvent) {
        switch event {
        case .connected(let url):
            assignIfChanged(\.state, .connected)
            assignIfChanged(\.hubURL, url)
            setLastEvent("Connected to \(url)")
            assignIfChanged(\.lastError, "")

        case .reconnecting(let delay, let error):
            assignIfChanged(\.state, .reconnecting)
            setLastEvent("Reconnecting in \(delay)")
            assignIfChanged(\.lastError, error)

        case .enrolling:
            assignIfChanged(\.state, .enrolling)
            setLastEvent("Enrolling with hub...")

        case .enrolled(let id):
            assignIfChanged(\.assetID, id)
            setLastEvent("Enrolled as \(id)")

        case .tokenLoaded(let path):
            setLastEvent("Token loaded from \(path)")

        case .tokenPersisted(let path):
            setLastEvent("Token saved to \(path)")

        case .sshKeyInstalled(let user):
            setLastEvent("SSH key installed for \(user)")

        case .receiveError(let error):
            assignIfChanged(\.lastError, error)
            setLastEvent("Receive error")

        case .transportStopped(let name):
            setLastEvent("\(name) transport stopped")

        case .heartbeatStopped(let name):
            setLastEvent("\(name) heartbeat stopped")

        case .configUpdate(let collect, let heartbeat, let loglevel):
            setLastEvent("Config: collect=\(collect) heartbeat=\(heartbeat) loglevel=\(loglevel)")

        case .warning(let scope, let message):
            let text = "\(scope): \(message)"
            if !isRoutineEvent(text) {
                setLastEvent(text)
            }

        case .desktopSession(let detail):
            setLastEvent("Desktop: \(detail)")

        case .fileTransfer(let detail):
            setLastEvent("File: \(detail)")

        case .terminalSession(let detail):
            setLastEvent("Terminal: \(detail)")

        case .vncSession(let detail):
            setLastEvent("VNC: \(detail)")

        case .heartbeat(let detail):
            let text = "Heartbeat: \(detail)"
            if !isRoutineEvent(text) {
                setLastEvent(text)
            }

        case .info(let scope, let message):
            let text = "\(scope): \(message)"
            if !isRoutineEvent(text) {
                setLastEvent(text)
            }

        case .unknown:
            break
        }
    }

    func markStarting(pid: Int32? = nil) {
        assignIfChanged(\.state, .starting)
        assignIfChanged(\.pid, pid)
        if let pid {
            assignIfChanged(\.startedAt, Date())
            setLastEvent("Process started (PID \(pid))")
        } else {
            assignIfChanged(\.startedAt, nil)
            setLastEvent("Starting agent...")
        }
        assignIfChanged(\.lastError, "")
    }

    func markStopped() {
        assignIfChanged(\.state, .stopped)
        assignIfChanged(\.pid, nil)
        assignIfChanged(\.startedAt, nil)
        setLastEvent("Process stopped")
    }

    func markError(_ message: String) {
        assignIfChanged(\.state, .error)
        assignIfChanged(\.lastError, message)
        setLastEvent("Error: \(message)")
    }
}
