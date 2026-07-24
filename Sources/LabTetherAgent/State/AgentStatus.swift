import Foundation
import SwiftUI

/// Connection states for the agent process.
enum ConnectionState: String {
    case stopped = "Stopped"
    case starting = "Starting"
    case connected = "Connected"
    case reconnecting = "Reconnecting"
    case enrolling = "Enrolling"
    case authFailed = "Auth Failed"
    case error = "Error"

    var sfSymbol: String {
        switch self {
        case .connected:    return "antenna.radiowaves.left.and.right"
        case .reconnecting: return "arrow.triangle.2.circlepath"
        case .enrolling:    return "arrow.triangle.2.circlepath"
        case .authFailed:   return "lock.slash.fill"
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
        case .authFailed:   return LT.bad
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

        case .authenticationFailed(let error):
            assignIfChanged(\.state, .authFailed)
            assignIfChanged(\.lastError, error)
            setLastEvent("Hub authentication failed")

        case .enrolled(let id):
            assignIfChanged(\.assetID, id)
            setLastEvent("Enrolled as \(id)")

        case .enrollmentTokenConsumed:
            setLastEvent("Enrollment token consumed")

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

    /// Reconciles wrapper state with the authenticated child API, which is the
    /// authoritative source once the child process is running. Log parsing is
    /// still used for immediate transitions and rich event text, but it must
    /// not leave Settings or Logs stuck on "Starting" while the menu panel is
    /// already showing a newer Hub connection state.
    func reconcileRuntime(_ snapshot: LocalAPIRuntimeSnapshot, processIsRunning: Bool) {
        guard processIsRunning else { return }

        let hubConnectionState = snapshot.hubConnectionState
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if snapshot.isReachable,
           hubConnectionState == "connected",
           let assetID = snapshot.assetID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !assetID.isEmpty {
            assignIfChanged(\.assetID, assetID)
        }

        switch hubConnectionState {
        case "connected" where snapshot.isReachable:
            assignIfChanged(\.state, .connected)
            assignIfChanged(\.lastError, "")

        case "connecting":
            assignIfChanged(\.state, .reconnecting)
            if let error = snapshot.lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
               !error.isEmpty {
                assignIfChanged(\.lastError, error)
            }

        case "auth_failed":
            assignIfChanged(\.state, .authFailed)
            let error = snapshot.lastError?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let error, !error.isEmpty {
                assignIfChanged(\.lastError, error)
            } else {
                assignIfChanged(\.lastError, "Hub authentication failed")
            }

        case "disconnected" where snapshot.isReachable:
            assignIfChanged(\.state, .reconnecting)
            if let error = snapshot.lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
               !error.isEmpty {
                assignIfChanged(\.lastError, error)
            }

        default:
            // A reset/unreachable local API is not enough evidence to replace a
            // richer log-derived state such as enrolling or auth failed.
            break
        }
    }

    /// Resets Hub-scoped identity before launching a new child process.
    ///
    /// A restart may target a different Hub or request a different asset
    /// identity. Keep the configured endpoint visible immediately, but do not
    /// expose the previous Hub's asset link until the new child reports a
    /// connected, authoritative asset ID.
    func prepareForLaunch(hubURL: String) {
        assignIfChanged(\.hubURL, hubURL)
        assignIfChanged(\.assetID, "")
        markStarting()
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
