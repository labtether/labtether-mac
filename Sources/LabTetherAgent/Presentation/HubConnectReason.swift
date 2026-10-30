import Foundation

/// Plain text for the agent's `last_error_reason`, the classified cause of the
/// last failed Hub connect. An unknown or empty code gives nil, so the menu
/// keeps its generic text.
enum HubConnectReason: String, Equatable {
    case nameLookupFailed = "name_lookup_failed"
    case connectionRefused = "connection_refused"
    case hostUnreachable = "host_unreachable"
    case timedOut = "timed_out"
    case certificateUntrusted = "certificate_untrusted"
    case tokenRejected = "token_rejected"

    init?(code: String?) {
        guard let code else { return nil }
        self.init(rawValue: code.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// One short line for the status header.
    var summary: String {
        switch self {
        case .nameLookupFailed: return "Can't find the Hub's host name"
        case .connectionRefused: return "The Hub refused the connection"
        case .hostUnreachable: return "Can't reach the Hub"
        case .timedOut: return "The Hub did not answer in time"
        case .certificateUntrusted: return "The Hub's certificate is not trusted"
        case .tokenRejected: return "The Hub refused the agent token"
        }
    }

    /// The fix, for causes where the Mac itself is the problem. macOS reports
    /// a blocked Local Network permission as "no route to host".
    var fix: String? {
        switch self {
        case .hostUnreachable:
            return "Check System Settings > Privacy & Security > Local Network and turn on LabTether Agent."
        default:
            return nil
        }
    }
}
