import Foundation

/// Events parsed from the Go agent's stdout/stderr lines.
enum AgentEvent: Equatable, Sendable {
    case connected(url: String)
    case reconnecting(delay: String, error: String)
    case enrolled(assetID: String)
    case enrolling
    case tokenLoaded(path: String)
    case tokenPersisted(path: String)
    case sshKeyInstalled(user: String)
    case receiveError(error: String)
    case transportStopped(name: String)
    case heartbeatStopped(name: String)
    case configUpdate(collect: String, heartbeat: String, loglevel: String)
    case warning(scope: String, message: String)
    case desktopSession(detail: String)
    case fileTransfer(detail: String)
    case terminalSession(detail: String)
    case vncSession(detail: String)
    case heartbeat(detail: String)
    case info(scope: String, message: String)
    case unknown(line: String)
}

/// Parses Go agent stdout lines into typed AgentEvent values.
/// Matches exact log.Printf patterns from internal/agentcore/.
struct LogParser: Sendable {
    func parse(_ line: String) -> AgentEvent {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip Go log timestamp prefix (e.g. "2024/01/01 12:00:00 ")
        let msg = stripTimestamp(trimmed)

        // agentws: connected to <url>
        if let url = match(msg, prefix: "agentws: connected to ") {
            return .connected(url: url)
        }

        // agentws: connect failed, retrying in <delay>: <error>
        if msg.hasPrefix("agentws: connect failed, retrying in ") {
            let rest = String(msg.dropFirst("agentws: connect failed, retrying in ".count))
            if let colonIdx = rest.firstIndex(of: ":") {
                let delay = String(rest[rest.startIndex..<colonIdx])
                let error = String(rest[rest.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                return .reconnecting(delay: delay, error: error)
            }
        }

        // agent: enrolled successfully as <assetID>
        if let assetID = match(msg, prefix: "agent: enrolled successfully as ") {
            return .enrolled(assetID: assetID)
        }

        // agent: enrolling with hub...
        if msg == "agent: enrolling with hub..." {
            return .enrolling
        }

        // agent: loaded token from <path>
        if let path = match(msg, prefix: "agent: loaded token from ") {
            return .tokenLoaded(path: path)
        }

        // agent: token persisted to <path>
        if let path = match(msg, prefix: "agent: token persisted to ") {
            return .tokenPersisted(path: path)
        }

        // ssh-key: installed hub public key for user <user>
        if let user = match(msg, prefix: "ssh-key: installed hub public key for user ") {
            return .sshKeyInstalled(user: user)
        }

        // agentws: receive error: <error>
        if let error = match(msg, prefix: "agentws: receive error: ") {
            return .receiveError(error: error)
        }

        // agentws: received config update: collect=<> heartbeat=<> loglevel=<>
        if msg.hasPrefix("agentws: received config update: ") {
            let rest = String(msg.dropFirst("agentws: received config update: ".count))
            let parts = rest.components(separatedBy: " ")
            var collect = "", heartbeat = "", loglevel = ""
            for part in parts {
                if part.hasPrefix("collect=") { collect = String(part.dropFirst("collect=".count)) }
                if part.hasPrefix("heartbeat=") { heartbeat = String(part.dropFirst("heartbeat=".count)) }
                if part.hasPrefix("loglevel=") { loglevel = String(part.dropFirst("loglevel=".count)) }
            }
            return .configUpdate(collect: collect, heartbeat: heartbeat, loglevel: loglevel)
        }

        // <name> telemetry collector stopped
        if msg.hasSuffix(" telemetry collector stopped") {
            let name = String(msg.dropLast(" telemetry collector stopped".count))
            return .transportStopped(name: name)
        }

        // <name> heartbeat loop stopped
        if msg.hasSuffix(" heartbeat loop stopped") {
            let name = String(msg.dropLast(" heartbeat loop stopped".count))
            return .heartbeatStopped(name: name)
        }

        // agentws: desktop <detail> (VNC/screen sharing)
        if let detail = match(msg, prefix: "agentws: desktop ") {
            return .desktopSession(detail: detail)
        }

        // agentws: VNC <detail>
        if let detail = match(msg, prefix: "agentws: VNC ") {
            return .vncSession(detail: detail)
        }

        // agentws: file <detail> (file transfer)
        if let detail = match(msg, prefix: "agentws: file ") {
            return .fileTransfer(detail: detail)
        }

        // terminal: <detail>
        if let detail = match(msg, prefix: "terminal: ") {
            return .terminalSession(detail: detail)
        }

        // agentws: terminal <detail>
        if let detail = match(msg, prefix: "agentws: terminal ") {
            return .terminalSession(detail: detail)
        }

        // heartbeat: <detail> or agentws: heartbeat <detail>
        if let detail = match(msg, prefix: "heartbeat: ") {
            return .heartbeat(detail: detail)
        }
        if let detail = match(msg, prefix: "agentws: heartbeat ") {
            return .heartbeat(detail: detail)
        }

        // update: <detail>
        if let detail = match(msg, prefix: "update: ") {
            return .info(scope: "update", message: detail)
        }

        // config: <detail>
        if let detail = match(msg, prefix: "config: ") {
            return .info(scope: "config", message: detail)
        }

        // agent: <detail> (general agent messages not matched above)
        if let detail = match(msg, prefix: "agent: ") {
            return .info(scope: "agent", message: detail)
        }

        // agentws: <detail> (general agentws messages not matched above)
        if let detail = match(msg, prefix: "agentws: ") {
            return .info(scope: "agentws", message: detail)
        }

        // <name> <scope> warning: <message>
        if msg.contains(" warning: ") {
            let parts = msg.components(separatedBy: " warning: ")
            if parts.count == 2 {
                return .warning(scope: parts[0], message: parts[1])
            }
        }

        return .unknown(line: trimmed)
    }

    private func match(_ msg: String, prefix: String) -> String? {
        guard msg.hasPrefix(prefix) else { return nil }
        return String(msg.dropFirst(prefix.count))
    }

    /// Strip the standard Go log timestamp prefix "YYYY/MM/DD HH:MM:SS "
    private func stripTimestamp(_ line: String) -> String {
        // Go's default log format: "2006/01/02 15:04:05 message"
        // That's 20 chars: "YYYY/MM/DD HH:MM:SS "
        if line.count > 20,
           line[line.index(line.startIndex, offsetBy: 4)] == "/",
           line[line.index(line.startIndex, offsetBy: 7)] == "/",
           line[line.index(line.startIndex, offsetBy: 10)] == " ",
           line[line.index(line.startIndex, offsetBy: 19)] == " " {
            return String(line[line.index(line.startIndex, offsetBy: 20)...])
        }
        return line
    }
}
