import Foundation

/// Plain words for the agent's `last_error`, a fixed code that people must
/// never see as it is. The Go agent sends these (labtether-agent
/// `internal/agentcore`): `transient` and `auth_failed` from
/// `connectErrorKind.String` (ws_transport.go, set in ws_reconnect.go);
/// `enrollment_pending` and the credential codes from
/// `wsTransport.ConnectionState`; `enrollment_token_rejected` and
/// `agent_token_persistence_failed` from run.go; and
/// `consumed_enrollment_token_cleanup_failed` from run.go, which may follow
/// another code after a comma. An unknown code gives nil, so the status line
/// keeps its generic text.
enum AgentLastError: Equatable {
    /// `transient`: the agent is retrying. `last_error_reason` says why.
    case retrying
    /// `auth_failed`: the Hub refused the agent token.
    case agentTokenRefused
    /// `enrollment_pending`: the Hub has not approved this device yet.
    case waitingForApproval
    /// `enrollment_token_rejected`: the Hub refused the enrollment token.
    case enrollmentTokenRefused
    /// `agent_token_persistence_failed`: the agent token was not saved.
    case agentTokenNotSaved
    /// `consumed_enrollment_token_cleanup_failed`: the used enrollment token
    /// file stayed. The agent records it as used and never sends it again.
    case usedEnrollmentTokenKept

    init?(code: String?) {
        let parts = (code ?? "").split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // With two codes, the one that needs the person wins.
        let known = parts.compactMap(Self.single)
        guard let first = known.first(where: { $0.text != nil }) ?? known.first else { return nil }
        self = first
    }

    private static func single(_ code: String) -> AgentLastError? {
        switch code {
        case "transient": return .retrying
        case "auth_failed": return .agentTokenRefused
        case "enrollment_pending": return .waitingForApproval
        case "enrollment_token_rejected": return .enrollmentTokenRefused
        case "agent_token_persistence_failed": return .agentTokenNotSaved
        case "consumed_enrollment_token_cleanup_failed": return .usedEnrollmentTokenKept
        default: return nil
        }
    }

    /// The line under the status word, or nil when there is nothing to add.
    var text: String? {
        switch self {
        case .retrying, .usedEnrollmentTokenKept:
            return nil
        case .agentTokenRefused:
            return "The Hub refused the agent token. Enter a new token in Settings › Connection."
        case .waitingForApproval:
            return "Approve this Mac in Devices on the Hub"
        case .enrollmentTokenRefused:
            return "The Hub refused this enrollment token. Make a new one in the console under Add device."
        case .agentTokenNotSaved:
            return "This Mac could not save the agent token. Logs show why."
        }
    }

    /// Plain words for a raw `last_error`, or nil.
    static func words(for code: String?) -> String? {
        AgentLastError(code: code)?.text
    }
}
