import Foundation

enum AgentHeroTone: Equatable {
    case ok
    case warn
    case accent
    case muted
    case bad
}

/// The status word and the one line under it, shared by the menu bar window,
/// the pop-out and Settings ("Connected" / "hub.lan · up 12h 28m").
struct AgentHeroPresentation: Equatable {
    let label: String
    let subtitle: String
    let tone: AgentHeroTone

    static func resolve(
        processIsRunning: Bool,
        processIsStarting: Bool,
        statusState: ConnectionState,
        statusLastError: String,
        statusUptime: String?,
        apiUptime: String?,
        apiLastError: String?,
        hubConnectionState: String,
        isReachable: Bool,
        apiLastErrorReason: String? = nil,
        hubHost: String? = nil,
        stoppedAt: Date? = nil,
        enrollmentError: String? = nil
    ) -> AgentHeroPresentation {
        let statusError = trimmed(statusLastError)
        // "transient" is the agent's retry class, not text for people.
        let apiError = trimmed(apiLastError).flatMap { $0 == "transient" ? nil : $0 }
        let reason = HubConnectReason(code: apiLastErrorReason)?.summary
        let host = trimmed(hubHost)

        // The wrapper marks the process as `.starting` immediately after launch
        // and log parsing may leave that state behind. Once the child process is
        // running and its authenticated local API is reachable, that API is the
        // fresher record of connected/auth-failed/disconnected state.
        if processIsStarting || (statusState == .starting && (!processIsRunning || !isReachable)) {
            return AgentHeroPresentation(label: "Starting", subtitle: host ?? "", tone: .muted)
        }

        if !processIsRunning {
            if statusState == .error {
                return AgentHeroPresentation(label: "Error", subtitle: statusError ?? "The agent stopped", tone: .bad)
            }
            let since = stoppedAt.map { "since \(clockTime($0))" }
            return AgentHeroPresentation(label: "Stopped", subtitle: joined(host, since), tone: .muted)
        }

        if statusState == .enrolling {
            return AgentHeroPresentation(label: "Enrolling", subtitle: host ?? "", tone: .warn)
        }

        // The Hub said no to the enrollment: its own words say why.
        if isReachable, hubConnectionState != "connected", let refusal = trimmed(enrollmentError) {
            return AgentHeroPresentation(label: "Enrollment refused", subtitle: refusal, tone: .bad)
        }

        if isReachable {
            switch hubConnectionState {
            case "connected":
                let uptime = (trimmed(apiUptime) ?? trimmed(statusUptime)).map { "up \($0)" }
                return AgentHeroPresentation(
                    label: "Connected",
                    subtitle: joined(host, apiError ?? statusError ?? uptime),
                    tone: .ok
                )
            case "connecting":
                return AgentHeroPresentation(
                    label: "Reconnecting",
                    subtitle: reason ?? apiError ?? statusError ?? host ?? "Waiting for the Hub",
                    tone: .warn
                )
            case "auth_failed":
                return AgentHeroPresentation(
                    label: "Token refused",
                    subtitle: reason ?? apiError ?? statusError ?? "The Hub refused the agent token",
                    tone: .bad
                )
            default:
                return AgentHeroPresentation(
                    label: "Disconnected",
                    subtitle: apiError ?? statusError ?? host ?? "No Hub connection",
                    tone: .muted
                )
            }
        }

        if hubConnectionState == "auth_failed" {
            // The agent's local API refused the app's own token.
            return AgentHeroPresentation(
                label: "Status unavailable",
                subtitle: statusError ?? "The agent refused this app's local token",
                tone: .bad
            )
        }

        if statusState == .authFailed {
            return AgentHeroPresentation(
                label: "Token refused",
                subtitle: statusError ?? "The Hub refused the agent token",
                tone: .bad
            )
        }

        if statusState == .error {
            return AgentHeroPresentation(label: "Error", subtitle: statusError ?? "The agent reported an error", tone: .bad)
        }

        if hubConnectionState == "connecting" || statusState == .reconnecting {
            return AgentHeroPresentation(
                label: "Reconnecting",
                subtitle: statusError ?? host ?? "Waiting for the Hub",
                tone: .warn
            )
        }

        return AgentHeroPresentation(
            label: "Status unavailable",
            subtitle: statusError ?? "Waiting for the agent",
            tone: .warn
        )
    }

    @MainActor static func resolve(
        agentProcess: AgentProcess,
        status: AgentStatus,
        runtime: LocalAPIRuntimeStore,
        settings: AgentSettings? = nil,
        includeHost: Bool = true
    ) -> AgentHeroPresentation {
        if let settings, !settings.isConfigured, !agentProcess.isRunning, !agentProcess.isStarting {
            return AgentHeroPresentation(label: "Not set up", subtitle: "Add the Hub address and a token", tone: .warn)
        }
        return resolve(
            processIsRunning: agentProcess.isRunning,
            processIsStarting: agentProcess.isStarting,
            statusState: status.state,
            statusLastError: status.lastError,
            statusUptime: status.uptime,
            apiUptime: runtime.snapshot.uptime,
            apiLastError: runtime.snapshot.lastError,
            hubConnectionState: runtime.snapshot.hubConnectionState,
            isReachable: runtime.snapshot.isReachable,
            apiLastErrorReason: runtime.snapshot.lastErrorReason,
            hubHost: includeHost ? hubHost(from: status.hubURL.isEmpty ? (settings?.hubURL ?? "") : status.hubURL) : nil,
            stoppedAt: status.stoppedAt,
            enrollmentError: runtime.snapshot.enrollmentError
        )
    }

    /// The Hub's host name for the status line ("hub.lan"), from any accepted address form.
    static func hubHost(from address: String) -> String? {
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let withScheme = value.contains("://") ? value : "wss://\(value)"
        if let host = URLComponents(string: withScheme)?.host, !host.isEmpty {
            return host
        }
        return nil
    }

    /// "21:12" in the user's locale.
    static func clockTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private static func joined(_ parts: String?...) -> String {
        parts.compactMap { $0 }.joined(separator: " · ")
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
