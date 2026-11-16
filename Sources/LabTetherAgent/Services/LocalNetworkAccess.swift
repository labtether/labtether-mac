import AppKit
import Foundation
import Network

/// macOS Local Network privacy. A new app may not reach addresses on the
/// local network until the person answers macOS's question with Allow; until
/// then, and after Don't Allow, every connection to a Hub on the LAN fails.
/// No call reads the answer, but a connection attempt shows it: its path is
/// unsatisfied with the reason `localNetworkDenied`.
enum LocalNetworkAccess: Equatable {
    /// Not looked at yet, or nothing showed that macOS blocks the Hub.
    case notBlocked
    /// macOS refuses this app the local network.
    case denied

    /// What a connection's path says. Only the Local Network reason counts:
    /// a Mac with no network at all is not sent to the privacy settings.
    static func from(status: NWPath.Status, reason: NWPath.UnsatisfiedReason) -> LocalNetworkAccess {
        status == .unsatisfied && reason == .localNetworkDenied ? .denied : .notBlocked
    }

    /// Tries a TCP connection to the Hub's host and port. The first attempt
    /// is also what makes macOS ask the person.
    static func probe(hubURL: String, timeout: TimeInterval = 3) async -> LocalNetworkAccess {
        guard let canonical = AgentSettingsNormalization.canonicalHubWebSocketURL(from: hubURL),
              let components = URLComponents(string: canonical), let host = components.host, !host.isEmpty else {
            return .notBlocked
        }
        let defaultPort = components.scheme == "ws" ? 80 : 443
        guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: components.port ?? defaultPort)) else {
            return .notBlocked
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        let answer = ProbeAnswer()
        return await withCheckedContinuation { continuation in
            let finish: @Sendable (LocalNetworkAccess) -> Void = { value in
                guard answer.claim() else { return }
                connection.cancel()
                continuation.resume(returning: value)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(.notBlocked)
                case .waiting, .failed:
                    let path = connection.currentPath
                    finish(path.map { from(status: $0.status, reason: $0.unsatisfiedReason) } ?? .notBlocked)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                let path = connection.currentPath
                finish(path.map { from(status: $0.status, reason: $0.unsatisfiedReason) } ?? .notBlocked)
            }
        }
    }

    /// System Settings › Privacy & Security › Local Network.
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The app's name as macOS shows it in the question and in Settings.
    static var appName: String {
        let info = Bundle.main.infoDictionary
        return (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String) ?? "LabTether Agent"
    }
}

/// The first of the state handler and the timeout wins.
private final class ProbeAnswer: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
