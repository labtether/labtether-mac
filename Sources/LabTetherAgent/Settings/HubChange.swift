import Foundation

/// What a new Hub address means for this Mac's saved token (owner decision
/// for 2.0): the same Hub keeps it; another Hub needs a warning first, then a
/// new enrollment token.
enum HubChangeVerdict: Equatable {
    /// Same address, or no saved token: nothing to decide.
    case unchanged
    /// An address the Hub gave for this token, or one that proved it holds
    /// the Hub's server key or a certificate from the Hub's own CA.
    case sameHub
    /// The new address answers without that proof, or is plain ws:// that
    /// the Hub never named.
    case otherHub
    /// The new address could not be reached to ask for proof.
    case unknown
}

/// How a new address is compared with the token's own Hub. The live probes
/// talk to the address; tests supply their own.
struct HubIdentityProbe {
    /// Whether the address holds the private key recorded for the token's
    /// Hub: proven only by a finished TLS handshake with that key.
    var holdsServerKey: (_ hubURL: String, _ key: String) async -> HubServerKey.Proof
    /// Fingerprint of the Hub's own CA, when the address completed a verified
    /// TLS handshake against that CA alone; nil otherwise.
    var ownCA: (_ hubURL: String) async -> String?

    static let live = HubIdentityProbe(
        holdsServerKey: { await HubServerKey.proves($1, hubURL: $0) },
        ownCA: { await HubCATrust.provenOwnCA(hubURL: $0, among: nil) }
    )
}

extension AgentSettings {
    /// "<scope> <sha256>" of the TLS server key of the Hub the token works with.
    static let hubServerKeyRecord = "hubServerKey"
    /// "<scope> <sha256>" of the CA of the Hub the token works with, recorded
    /// when the token connected there. Never taken from a CA file on disk:
    /// that file can hold a CA trusted later for another address.
    static let hubCARecord = "hubCA"
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

    /// The value recorded for the token's own Hub under `key`, if any.
    private func tokenHubRecord(_ key: String, tokenScope: String) -> String? {
        let parts = storedRecord(key).split(separator: " ").map(String.init)
        return parts.count == 2 && parts[0] == tokenScope ? parts[1] : nil
    }

    /// Settings and the restart gate: same Hub, another Hub, or unknown.
    ///
    /// The new address is compared only with what was recorded for the
    /// token's own Hub when the token connected there (its CA and its server
    /// key). A CA trusted later for the new address proves nothing here.
    func checkHubChange(probe: HubIdentityProbe = .live) async -> HubChangeVerdict {
        guard let tokenScope = savedTokenScope, let scope = pendingHubScope,
              let url = normalizedHubWebSocketURL(), scope != tokenScope else { return .unchanged }
        if isKnownSameHub(scope) { return .sameHub }
        let knownCA = tokenHubRecord(Self.hubCARecord, tokenScope: tokenScope)
        let knownKey = tokenHubRecord(Self.hubServerKeyRecord, tokenScope: tokenScope)
        guard knownCA != nil || knownKey != nil else { return .unknown }
        // Both questions are asked at once: an address nobody answers then
        // costs one timeout before the warning, not two.
        let caTask = Task { knownCA == nil ? nil : await probe.ownCA(url) }
        let keyTask = Task { () -> HubServerKey.Proof? in
            guard let knownKey else { return nil }
            return await probe.holdsServerKey(url, knownKey)
        }
        let ca = await caTask.value
        let key = await keyTask.value
        if let knownCA, ca == knownCA { rememberSameHub(scope); return .sameHub }
        if key == .proven { rememberSameHub(scope); return .sameHub }
        let answered = ca != nil || key == .notProven
        if !answered && url.hasPrefix("wss://") { return .unknown }
        return .otherHub
    }

    /// Records the server key and the CA of the Hub the token works with.
    /// Called on each connection, when the token has just been accepted there.
    func recordHubServerKey() {
        guard let url = normalizedHubWebSocketURL(), url.hasPrefix("wss://"),
              let scope = pendingHubScope, scope == savedTokenScope else { return }
        let trusted = (try? ConnectionTester.trustedCertificates(for: effectiveTLSCAFile)) ?? []
        Task { @MainActor [weak self] in
            // Only from a connection this Mac verifies, as the agent does.
            let key = await HubServerKey.verifiedFingerprint(hubURL: url, anchors: trusted)
            // Only a CA this Mac already trusts for the Hub, proven by a full handshake.
            let ca = await HubCATrust.provenOwnCA(hubURL: url, among: trusted)
            guard let self, self.savedTokenScope == scope, self.pendingHubScope == scope else { return }
            if let key { self.setStoredRecord("\(scope) \(key)", key: Self.hubServerKeyRecord) }
            if let ca { self.setStoredRecord("\(scope) \(ca)", key: Self.hubCARecord) }
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
        setStoredRecord("", key: Self.hubCARecord)
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
