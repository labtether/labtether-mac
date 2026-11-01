import Foundation

/// A saved agent token is valid only for the Hub that issued it. Hub
/// WebSockets accept a bearer token alone, so after the Hub URL changes the
/// old Hub's token must not be sent to the new address.
extension AgentSettings {
    static let agentTokenHubKey = "agentTokenHub"
    static let typedTokenHubKey = "typedTokenHub"
    /// Files the Go child writes for one Hub: its token, the asset it was
    /// enrolled as, and that Hub's CA.
    static let hubBoundFileNames = ["agent-token", "enrollment-state.json", "ca.crt"]

    /// Transport, host and port of a normalized Hub URL. The path is ignored.
    static func credentialScope(forHubWebSocketURL url: String) -> String? {
        guard let components = URLComponents(string: url),
              let scheme = components.scheme?.lowercased(), scheme == "ws" || scheme == "wss",
              let host = components.host?.lowercased(), !host.isEmpty else { return nil }
        return "\(scheme)://\(host):\(components.port ?? (scheme == "wss" ? 443 : 80))"
    }

    /// Runs before every launch. Removes credentials saved for another Hub,
    /// then binds what is left to the current Hub. Settings saved by older
    /// versions have no binding yet and are bound as they are. Returns true
    /// when a credential was removed.
    func dropCredentialsFromOtherHub() throws -> Bool {
        guard let url = normalizedHubWebSocketURL(),
              let scope = Self.credentialScope(forHubWebSocketURL: url) else { return false }
        var dropped = false
        let tokenHub = storedRecord(Self.agentTokenHubKey)
        if !tokenHub.isEmpty && tokenHub != scope {
            for name in Self.hubBoundFileNames {
                if try removeChildFile(name) { dropped = true }
            }
        }
        setStoredRecord(scope, key: Self.agentTokenHubKey)

        let typedHub = storedRecord(Self.typedTokenHubKey)
        let hasTypedToken = !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !enrollmentToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !typedHub.isEmpty && typedHub != scope {
            // Keep the old binding until a new token is typed, so a failed
            // Keychain removal is retried on the next launch.
            if hasTypedToken {
                apiToken = ""
                enrollmentToken = ""
                dropped = true
            }
        } else {
            setStoredRecord(hasTypedToken ? scope : "", key: Self.typedTokenHubKey)
        }
        return dropped
    }

    /// A token typed into Settings or onboarding is meant for the Hub used at
    /// the next launch.
    func unbindTypedToken() {
        setStoredRecord("", key: Self.typedTokenHubKey)
    }

    /// Removes a file the Go child wrote in the state folder. Returns false
    /// when it does not exist.
    func removeChildFile(_ name: String) throws -> Bool {
        if let stateLocation { return try stateLocation.removeRegularFile(name) }
        let path = appSupportDirectory.appendingPathComponent(name).path
        guard (try? FileManager.default.attributesOfItem(atPath: path)) != nil else { return false }
        try FileManager.default.removeItem(atPath: path)
        return true
    }
}
