import Foundation
import Network

enum AgentSettingsNormalization {
    static func canonicalHubWebSocketURL(from raw: String) -> String? {
        var candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.isEmpty {
            return nil
        }
        if !candidate.contains("://") {
            candidate = "wss://\(candidate)"
        }
        guard var components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              !host.isEmpty
        else {
            return nil
        }
        if components.user != nil || components.password != nil || components.query != nil || components.fragment != nil {
            return nil
        }

        switch scheme {
        case "ws", "wss":
            break
        case "http":
            components.scheme = "ws"
        case "https":
            components.scheme = "wss"
        default:
            return nil
        }

        let path = components.path.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty || path == "/" {
            components.path = "/ws/agent"
        } else if !path.hasPrefix("/") {
            components.path = "/\(path)"
        }
        return components.string
    }

    static func dockerEndpointValidationError(_ raw: String) -> String? {
        let endpoint = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if endpoint.isEmpty {
            return "Docker endpoint is required when Docker integration is enabled."
        }
        if endpoint.hasPrefix("/") {
            return nil
        }
        if endpoint.lowercased().hasPrefix("unix://") {
            let path = String(endpoint.dropFirst("unix://".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if path.hasPrefix("/") {
                return nil
            }
            return "Docker endpoint unix:// path must be absolute."
        }
        guard let url = URL(string: endpoint),
              let scheme = url.scheme?.lowercased(),
              let host = url.host,
              !host.isEmpty
        else {
            return "Docker endpoint must be an absolute path, unix:// path, or an https URL."
        }
        if scheme != "https" {
            return "Docker endpoint URL scheme must be https."
        }
        return nil
    }

    static func normalizedPortList(_ raw: String) -> String? {
        guard portListValidationError(raw) == nil else {
            return nil
        }
        let tokens = splitListTokens(raw)
        if tokens.isEmpty {
            return ""
        }
        var seen = Set<Int>()
        var ports: [Int] = []
        for token in tokens {
            guard let port = Int(token), (1...65535).contains(port) else {
                return nil
            }
            if seen.contains(port) {
                continue
            }
            seen.insert(port)
            ports.append(port)
        }
        ports.sort()
        return ports.map(String.init).joined(separator: ",")
    }

    static func portListValidationError(_ raw: String) -> String? {
        let tokens = splitListTokens(raw)
        if tokens.isEmpty {
            return nil
        }
        for token in tokens {
            guard let port = Int(token), (1...65535).contains(port) else {
                return "must contain only TCP ports between 1 and 65535."
            }
        }
        return nil
    }

    static func normalizedCIDRList(_ raw: String) -> String? {
        guard cidrListValidationError(raw) == nil else {
            return nil
        }
        let tokens = splitListTokens(raw)
        if tokens.isEmpty {
            return ""
        }
        var seen = Set<String>()
        var cidrs: [String] = []
        for token in tokens {
            guard let normalized = normalizedCIDR(token), !normalized.isEmpty else {
                return nil
            }
            if seen.contains(normalized) {
                continue
            }
            seen.insert(normalized)
            cidrs.append(normalized)
        }
        cidrs.sort()
        return cidrs.joined(separator: ",")
    }

    static func cidrListValidationError(_ raw: String) -> String? {
        let tokens = splitListTokens(raw)
        if tokens.isEmpty {
            return nil
        }
        for token in tokens {
            guard let normalized = normalizedCIDR(token), !normalized.isEmpty else {
                return "must contain valid CIDR values."
            }
            guard isPrivateOrLocalCIDR(normalized) else {
                return "only private/local CIDR ranges are allowed."
            }
        }
        return nil
    }

    private static func splitListTokens(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return []
        }
        return trimmed
            .components(separatedBy: CharacterSet(charactersIn: ",; \n\t"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func normalizedCIDR(_ raw: String) -> String? {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = token.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2, let prefixBits = Int(parts[1]) else {
            return nil
        }

        if let ip4 = IPv4Address(parts[0]) {
            guard (0...32).contains(prefixBits) else { return nil }
            let masked = maskIPv4(ip4.rawValue, prefixBits: prefixBits)
            guard let network = IPv4Address(masked) else { return nil }
            return "\(network)/\(prefixBits)"
        }

        if let ip6 = IPv6Address(parts[0]) {
            guard (0...128).contains(prefixBits) else { return nil }
            let masked = maskIPv6(ip6.rawValue, prefixBits: prefixBits)
            guard let network = IPv6Address(masked) else { return nil }
            return "\(network)/\(prefixBits)"
        }

        return nil
    }

    private static func maskIPv4(_ raw: Data, prefixBits: Int) -> Data {
        var bytes = [UInt8](raw)
        if bytes.count != 4 {
            return raw
        }
        if prefixBits <= 0 {
            return Data(repeating: 0, count: 4)
        }
        if prefixBits >= 32 {
            return raw
        }

        let fullBytes = prefixBits / 8
        let remainderBits = prefixBits % 8
        if remainderBits != 0 && fullBytes < bytes.count {
            let mask: UInt8 = UInt8(0xFF << (8 - remainderBits))
            bytes[fullBytes] &= mask
        }
        if fullBytes + (remainderBits == 0 ? 0 : 1) < bytes.count {
            for index in (fullBytes + (remainderBits == 0 ? 0 : 1))..<bytes.count {
                bytes[index] = 0
            }
        }
        return Data(bytes)
    }

    private static func maskIPv6(_ raw: Data, prefixBits: Int) -> Data {
        var bytes = [UInt8](raw)
        if bytes.count != 16 {
            return raw
        }
        if prefixBits <= 0 {
            return Data(repeating: 0, count: 16)
        }
        if prefixBits >= 128 {
            return raw
        }

        let fullBytes = prefixBits / 8
        let remainderBits = prefixBits % 8
        if remainderBits != 0 && fullBytes < bytes.count {
            let mask: UInt8 = UInt8(0xFF << (8 - remainderBits))
            bytes[fullBytes] &= mask
        }
        if fullBytes + (remainderBits == 0 ? 0 : 1) < bytes.count {
            for index in (fullBytes + (remainderBits == 0 ? 0 : 1))..<bytes.count {
                bytes[index] = 0
            }
        }
        return Data(bytes)
    }

    private static func isPrivateOrLocalCIDR(_ normalized: String) -> Bool {
        let parts = normalized.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            return false
        }
        if let ip4 = IPv4Address(parts[0]) {
            let bytes = [UInt8](ip4.rawValue)
            guard bytes.count == 4 else { return false }
            if bytes[0] == 10 || bytes[0] == 127 {
                return true
            }
            if bytes[0] == 172 && (16...31).contains(bytes[1]) {
                return true
            }
            if bytes[0] == 192 && bytes[1] == 168 {
                return true
            }
            if bytes[0] == 169 && bytes[1] == 254 {
                return true
            }
            return false
        }
        if let ip6 = IPv6Address(parts[0]) {
            let bytes = [UInt8](ip6.rawValue)
            guard bytes.count == 16 else { return false }
            // fc00::/7 (unique local)
            if (bytes[0] & 0xFE) == 0xFC {
                return true
            }
            // fe80::/10 (link-local)
            if bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80 {
                return true
            }
            // loopback ::1
            if bytes.dropLast().allSatisfy({ $0 == 0 }) && bytes.last == 1 {
                return true
            }
            return false
        }
        return false
    }
}
