import Foundation

/// A CA file the person chose in Settings › Security.
///
/// Before 2.0 such a file was one more root beside the system's. As the
/// agent's only root it must really be the Hub's CA, or the Mac goes offline.
/// So it becomes the only root only once it was shown to verify the Hub
/// alone: when it is chosen (a file that does not is refused), or, for a file
/// saved by an earlier version, by a check at each start until it passes.
/// Until then it is used as before.
extension AgentSettings {
    /// "<scope> <fingerprint>" of the chosen CA that verified the Hub alone.
    static let chosenCAVerifiedRecord = "chosenCAVerified"
    static let chosenCAMismatchMessage = "This CA certificate does not match this Hub's certificate."
    static let chosenCAUnreachableMessage = "Can't reach the Hub to check this CA certificate."
    static let chosenCANotFoundMessage = "CA certificate file not found."
    static let chosenCAKeptAsBeforeMismatch =
        "The CA certificate file does not sign this Hub's certificate. The agent uses it as before, together with the system's certificates."
    static let chosenCAKeptAsBeforeNoAnswer =
        "The Hub did not answer a check of the CA certificate file. The agent uses it as before, together with the system's certificates; the check runs again at the next start."

    typealias ChosenCACheck = (_ hubURL: String, _ caFile: String) async -> HubCATrust.OwnCAVerdict

    func chosenCAIsVerified(fingerprint: String, forHubURL hubURL: String) -> Bool {
        guard let url = AgentSettingsNormalization.canonicalHubWebSocketURL(from: hubURL),
              let scope = Self.credentialScope(forHubWebSocketURL: url) else { return false }
        let parts = storedRecord(Self.chosenCAVerifiedRecord).split(separator: " ").map(String.init)
        guard parts.count == 2, parts[1] == fingerprint else { return false }
        return parts[0] == scope || (parts[0] == savedTokenScope && isKnownSameHub(scope))
    }

    /// A saved CA file that has not yet been shown to verify the Hub in use.
    var chosenCANeedsCheck: Bool {
        let chosen = tlsCAFile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chosen.isEmpty, let url = normalizedHubWebSocketURL(), url.hasPrefix("wss://"),
              let fingerprint = Self.firstFingerprint(inPEMFile: chosen) else { return false }
        return !chosenCAIsVerified(fingerprint: fingerprint, forHubURL: url)
    }

    /// Settings: the person chose `path` (empty clears the setting). It is
    /// saved only when it verifies the Hub alone; otherwise the words say why
    /// and the previous setting stays.
    func chooseCAFile(_ path: String, check: ChosenCACheck = HubCATrust.verifiesAlone) async -> String? {
        let chosen = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if chosen.isEmpty {
            if !tlsCAFile.isEmpty { tlsCAFile = "" }
            return nil
        }
        guard FileManager.default.fileExists(atPath: chosen) else { return Self.chosenCANotFoundMessage }
        guard let url = normalizedHubWebSocketURL(), url.hasPrefix("wss://"),
              let scope = Self.credentialScope(forHubWebSocketURL: url) else {
            // No wss:// Hub to check against yet: kept as before, and checked at the first start for one.
            tlsCAFile = chosen
            return nil
        }
        switch await check(url, chosen) {
        case .verified(let fingerprint):
            tlsCAFile = chosen
            setStoredRecord("\(scope) \(fingerprint)", key: Self.chosenCAVerifiedRecord)
            return nil
        case .mismatch: return Self.chosenCAMismatchMessage
        case .unreadable: return Self.chosenCAUnusableMessage
        case .unreachable: return Self.chosenCAUnreachableMessage
        }
    }

    /// At start, for a CA file saved before it had to verify the Hub alone.
    /// Nil when it now does and is the agent's only root from here on;
    /// otherwise the one line for the log, and the file is used as before.
    func checkSavedChosenCA(check: ChosenCACheck = HubCATrust.verifiesAlone) async -> String? {
        let chosen = tlsCAFile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard chosenCANeedsCheck, let url = normalizedHubWebSocketURL(),
              let scope = Self.credentialScope(forHubWebSocketURL: url) else { return nil }
        switch await check(url, chosen) {
        case .verified(let fingerprint):
            setStoredRecord("\(scope) \(fingerprint)", key: Self.chosenCAVerifiedRecord)
            return nil
        case .mismatch: return Self.chosenCAKeptAsBeforeMismatch
        case .unreadable, .unreachable: return Self.chosenCAKeptAsBeforeNoAnswer
        }
    }
}
