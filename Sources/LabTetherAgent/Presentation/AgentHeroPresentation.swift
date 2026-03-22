import Foundation

enum AgentHeroTone: Equatable {
    case ok
    case warn
    case accent
    case muted
    case bad
}

struct AgentHeroPresentation: Equatable {
    let label: String
    let subtitle: String
    let tone: AgentHeroTone
    let breatheDuration: Double

    static func resolve(
        processIsRunning: Bool,
        processIsStarting: Bool,
        statusState: ConnectionState,
        statusLastError: String,
        statusUptime: String?,
        apiUptime: String?,
        apiLastError: String?,
        hubConnectionState: String,
        isReachable: Bool
    ) -> AgentHeroPresentation {
        let trimmedStatusError = trimmed(statusLastError)
        let trimmedAPIError = trimmed(apiLastError)

        if processIsStarting || statusState == .starting {
            return AgentHeroPresentation(
                label: "Starting",
                subtitle: "Launching agent process...",
                tone: .accent,
                breatheDuration: 2.0
            )
        }

        if !processIsRunning {
            if statusState == .error {
                return AgentHeroPresentation(
                    label: "Error",
                    subtitle: trimmedStatusError ?? "Unknown error",
                    tone: .bad,
                    breatheDuration: 1.5
                )
            }
            return AgentHeroPresentation(
                label: "Stopped",
                subtitle: "Agent is not running",
                tone: .muted,
                breatheDuration: 4.0
            )
        }

        if statusState == .enrolling {
            return AgentHeroPresentation(
                label: "Enrolling",
                subtitle: "Registering with hub...",
                tone: .warn,
                breatheDuration: 2.5
            )
        }

        if isReachable {
            switch hubConnectionState {
            case "connected":
                var parts: [String] = []
                if let uptime = trimmed(apiUptime) ?? trimmed(statusUptime) {
                    parts.append(uptime)
                }
                if let error = trimmedAPIError ?? trimmedStatusError {
                    parts.append(error)
                } else {
                    parts.append("all clear")
                }
                return AgentHeroPresentation(
                    label: "Connected",
                    subtitle: parts.joined(separator: " · "),
                    tone: .ok,
                    breatheDuration: 3.0
                )
            case "connecting":
                return AgentHeroPresentation(
                    label: "Reconnecting",
                    subtitle: trimmedAPIError ?? trimmedStatusError ?? "Attempting to reconnect",
                    tone: .warn,
                    breatheDuration: 2.0
                )
            case "auth_failed":
                return AgentHeroPresentation(
                    label: "Auth Failed",
                    subtitle: trimmedAPIError ?? trimmedStatusError ?? "Hub authentication failed",
                    tone: .bad,
                    breatheDuration: 1.5
                )
            default:
                return AgentHeroPresentation(
                    label: "Disconnected",
                    subtitle: trimmedAPIError ?? trimmedStatusError ?? "Hub connection unavailable",
                    tone: .muted,
                    breatheDuration: 2.5
                )
            }
        }

        if hubConnectionState == "auth_failed" {
            return AgentHeroPresentation(
                label: "Auth Failed",
                subtitle: trimmedStatusError ?? "Local status authentication failed",
                tone: .bad,
                breatheDuration: 1.5
            )
        }

        if statusState == .error {
            return AgentHeroPresentation(
                label: "Error",
                subtitle: trimmedStatusError ?? "Unknown error",
                tone: .bad,
                breatheDuration: 1.5
            )
        }

        if hubConnectionState == "connecting" || statusState == .reconnecting {
            return AgentHeroPresentation(
                label: "Reconnecting",
                subtitle: trimmedStatusError ?? "Attempting to reconnect",
                tone: .warn,
                breatheDuration: 2.0
            )
        }

        return AgentHeroPresentation(
            label: "Status Unavailable",
            subtitle: trimmedStatusError ?? "Waiting for local status response",
            tone: .warn,
            breatheDuration: 2.5
        )
    }

    @MainActor static func resolve(
        agentProcess: AgentProcess,
        status: AgentStatus,
        runtime: LocalAPIRuntimeStore
    ) -> AgentHeroPresentation {
        resolve(
            processIsRunning: agentProcess.isRunning,
            processIsStarting: agentProcess.isStarting,
            statusState: status.state,
            statusLastError: status.lastError,
            statusUptime: status.uptime,
            apiUptime: runtime.snapshot.uptime,
            apiLastError: runtime.snapshot.lastError,
            hubConnectionState: runtime.snapshot.hubConnectionState,
            isReachable: runtime.snapshot.isReachable
        )
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
