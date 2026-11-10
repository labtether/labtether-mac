import Foundation

/// What a new Hub address means for this Mac's saved token (owner decision
/// for 2.0): the same Hub keeps it; another Hub needs a warning first, then a
/// new enrollment token.
enum HubChangeVerdict: Equatable {
    /// Same address, or no saved token: nothing to decide.
    case unchanged
    /// An address the Hub gave for this token, or the same TLS server key.
    case sameHub
    /// The new address answers with another server key, or plain ws:// that
    /// the Hub never named.
    case otherHub
    /// The new address could not be reached to compare its server key.
    case unknown
}

extension AgentSettings {
    /// "<scope> <sha256>" of the TLS server key of the Hub the token works with.
    static let hubServerKeyRecord = "hubServerKey"
    /// Space-separated scopes proven to be the token's Hub.
    static let sameHubScopesRecord = "sameHubScopes"

    /// The Hub scope the saved agent token belongs to, if a token is saved.
    var savedTokenScope: String? {
        let scope = storedRecord(Self.agentTokenHubKey)
        return !scope.isEmpty && hasPersistedAgentToken ? scope : nil
    }

    /// The scope of the Hub address the next start will use.
    var pendingHubScope: String? {
        normalizedHubWebSocketURL().flatMap { Self.credentialScope(forHubWebSocketURL: $0) }
    }

    /// The agent's host:port spelling of a scope ("wss://hub.lan:8443" -> "hub.lan:8443").
    static func agentOrigin(ofScope scope: String) -> String? {
        guard let components = URLComponents(string: scope), var host = components.host, !host.isEmpty,
              let port = components.port else { return nil }
        if host.contains(":") && !host.hasPrefix("[") { host = "[\(host)]" }
        return "\(host.lowercased()):\(port)"
    }

    /// The Hub addresses the agent recorded for its saved token.
    func savedTokenOrigins() -> [String] {
        guard let object = enrollmentStateObject() else { return [] }
        return (object["token_origins"] as? [String]) ?? []
    }

    /// True without any network check: the token's own scope, an address the
    /// Hub gave for the token, or one already proven to be the same Hub.
    func isKnownSameHub(_ scope: String) -> Bool {
        guard let tokenScope = savedTokenScope else { return true }
        if scope == tokenScope { return true }
        if let origin = Self.agentOrigin(ofScope: scope), savedTokenOrigins().contains(origin) { return true }
        return storedRecord(Self.sameHubScopesRecord).split(separator: " ").contains { String($0) == scope }
    }

    /// The next start would remove the saved token, and nobody confirmed it.
    var hubChangeNeedsConfirmation: Bool {
        guard let scope = pendingHubScope, !isKnownSameHub(scope) else { return false }
        return confirmedHubChangeScope != scope
    }

    /// Settings and the restart gate: same Hub, another Hub, or unknown.
    func checkHubChange() async -> HubChangeVerdict {
        guard let tokenScope = savedTokenScope, let scope = pendingHubScope,
              let url = normalizedHubWebSocketURL(), scope != tokenScope else { return .unchanged }
        if isKnownSameHub(scope) { return .sameHub }
        // Same Hub = same CA: the new address proves the CA kept for this Hub.
        if hasManagedHubCA, await HubCATrust.isServedBy(savedCAFile: managedHubCAPath, hubURL: url) {
            rememberSameHub(scope)
            return .sameHub
        }
        let record = storedRecord(Self.hubServerKeyRecord).split(separator: " ").map(String.init)
        guard record.count == 2, record[0] == tokenScope else { return .unknown }
        guard let key = await HubServerKey.fingerprint(hubURL: url) else {
            return url.hasPrefix("wss://") ? .unknown : .otherHub
        }
        guard key == record[1] else { return .otherHub }
        rememberSameHub(scope)
        return .sameHub
    }

    /// Keeps the TLS server key of the Hub the token works with. Called on
    /// each connection, when the token has just been accepted there.
    func recordHubServerKey() {
        guard let url = normalizedHubWebSocketURL(), url.hasPrefix("wss://"),
              let scope = pendingHubScope, scope == savedTokenScope else { return }
        Task { @MainActor [weak self] in
            guard let key = await HubServerKey.fingerprint(hubURL: url), let self,
                  self.savedTokenScope == scope else { return }
            self.setStoredRecord("\(scope) \(key)", key: Self.hubServerKeyRecord)
        }
    }

    func rememberSameHub(_ scope: String) {
        var scopes = storedRecord(Self.sameHubScopesRecord).split(separator: " ").map(String.init)
        guard !scopes.contains(scope) else { return }
        scopes.append(scope)
        setStoredRecord(scopes.joined(separator: " "), key: Self.sameHubScopesRecord)
    }

    func forgetHubIdentity() {
        setStoredRecord("", key: Self.sameHubScopesRecord)
        setStoredRecord("", key: Self.hubServerKeyRecord)
        confirmedHubChangeScope = nil
    }

    /// Lets the agent send the kept token to the new address of the same Hub:
    /// the agent only sends it to the addresses in `token_origins`.
    func allowSavedToken(forScope scope: String) throws {
        guard let origin = Self.agentOrigin(ofScope: scope), var object = enrollmentStateObject() else { return }
        var origins = (object["token_origins"] as? [String]) ?? []
        guard !origins.contains(origin) else { return }
        origins.append(origin)
        object["token_origins"] = origins
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        if let stateLocation {
            try stateLocation.write(data, name: "enrollment-state.json")
        } else {
            let url = appSupportDirectory.appendingPathComponent("enrollment-state.json")
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    private func enrollmentStateObject() -> [String: Any]? {
        let data: Data?
        if let stateLocation {
            data = try? stateLocation.read("enrollment-state.json")
        } else {
            data = try? Data(contentsOf: appSupportDirectory.appendingPathComponent("enrollment-state.json"))
        }
        guard let data else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
