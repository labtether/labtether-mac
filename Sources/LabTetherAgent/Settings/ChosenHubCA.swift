import Foundation

/// A CA file the person chose in Settings › Security.
///
/// Before 2.0 such a file was one more root beside the system's. As the
/// agent's only root (LABTETHER_TLS_CA_ONLY) it must really be the Hub's CA,
/// or the Mac goes offline. The rules:
///
/// - Choosing a file: saved only when a handshake with that file as the only
///   root reaches the Hub. A file that does not is refused.
/// - Once a file has verified a Hub alone, it is that Hub's only root from
///   then on. Nothing takes that back: not a Hub that is away, not a failed
///   check. If the file later goes missing or holds another certificate, the
///   agent is not started; it is never started with the system's roots added.
/// - A file saved by an earlier version that has never verified this Hub is
///   used as that version used it, beside the system's roots: the same
///   security as before, and no Mac goes offline with the update. It is
///   checked at every start and after every connection until it verifies the
///   Hub. While it is known not to match, Settings says so.
extension AgentSettings {
    /// "<scope> <fingerprint>" entries, one per Hub, separated by "|".
    static let chosenCAVerifiedRecord = "chosenCAVerified"
    /// "<scope> <fingerprint>" of a file last seen not to sign that Hub's certificate.
    static let chosenCAMismatchRecord = "chosenCAMismatch"

    static let chosenCAMismatchMessage = "This CA certificate does not match this Hub's certificate."
    static let chosenCAUnreachableMessage = "Can't reach the Hub to check this CA certificate."
    static let chosenCANotFoundMessage = "CA certificate file not found."
    static let chosenCAChangedMessage =
        "The CA certificate file chosen for this Hub is missing or is not the same certificate. Choose it again in Settings › Security."
    static let chosenCAKeptAsBeforeMismatch =
        "The CA certificate file does not sign this Hub's certificate. The agent uses it as before, together with the system's certificates. Settings › Security shows this."
    static let chosenCAKeptAsBeforeNoAnswer =
        "The Hub did not answer a check of the CA certificate file. The agent uses it as before, together with the system's certificates; the check runs again at the next start."
    static let chosenCANowOnlyRoot =
        "The CA certificate file verifies this Hub alone. From the next start the agent trusts only that file for the Hub."

    typealias ChosenCACheck = (_ hubURL: String, _ caFile: String) async -> HubCATrust.OwnCAVerdict

    private func chosenCAScope(of hubURL: String) -> String? {
        AgentSettingsNormalization.canonicalHubWebSocketURL(from: hubURL)
            .flatMap { Self.credentialScope(forHubWebSocketURL: $0) }
    }

    private var chosenCAVerifiedEntries: [(scope: String, fingerprint: String)] {
        storedRecord(Self.chosenCAVerifiedRecord).split(separator: "|").compactMap { entry in
            let parts = entry.split(separator: " ").map(String.init)
            return parts.count == 2 ? (parts[0], parts[1]) : nil
        }
    }

    /// The fingerprint of the chosen CA that verified the Hub at `hubURL`
    /// alone, if one ever did: for that address, or for the token's Hub when
    /// the address is known to be it.
    func chosenCAVerifiedFingerprint(forHubURL hubURL: String) -> String? {
        guard let scope = chosenCAScope(of: hubURL) else { return nil }
        let entries = chosenCAVerifiedEntries
        if let own = entries.first(where: { $0.scope == scope }) { return own.fingerprint }
        if let tokenScope = savedTokenScope, isKnownSameHub(scope) {
            return entries.first(where: { $0.scope == tokenScope })?.fingerprint
        }
        return nil
    }

    private func recordChosenCAVerified(scope: String, fingerprint: String) {
        var entries = chosenCAVerifiedEntries.filter { $0.scope != scope }
        entries.append((scope, fingerprint))
        setStoredRecord(entries.map { "\($0.scope) \($0.fingerprint)" }.joined(separator: "|"), key: Self.chosenCAVerifiedRecord)
        setStoredRecord("", key: Self.chosenCAMismatchRecord)
        objectWillChange.send()
    }

    /// The setting is cleared or replaced by a trusted CA: nothing is known
    /// about a chosen file any more.
    func forgetChosenCA() {
        setStoredRecord("", key: Self.chosenCAVerifiedRecord)
        setStoredRecord("", key: Self.chosenCAMismatchRecord)
    }

    /// What the agent is given for the chosen file `chosen` and the Hub at `hubURL`.
    func chosenCAPin(_ chosen: String, forHubURL hubURL: String) -> HubCAPin {
        let onDisk = Self.firstFingerprint(inPEMFile: chosen)
        // Once a file verified this Hub alone it is the only root for good.
        // If it is gone or holds another certificate now, the agent is not
        // started; the system's roots are never added back.
        if let verified = chosenCAVerifiedFingerprint(forHubURL: hubURL) {
            return onDisk == verified ? .file(chosen) : .unusable(Self.chosenCAChangedMessage)
        }
        // Whoever left an enrollment token for this Hub named this CA with
        // it: the only root from the first start, or the token is not sent.
        if let onDisk, enrollmentTokenTieCA(forHubURL: hubURL) == onDisk { return .file(chosen) }
        // Never verified for this Hub: as before 2.0.
        return .alongside(chosen)
    }

    /// A saved CA file that has never verified the Hub in use alone.
    var chosenCANeedsCheck: Bool {
        let chosen = tlsCAFile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chosen.isEmpty, let url = normalizedHubWebSocketURL(), url.hasPrefix("wss://"),
              Self.firstFingerprint(inPEMFile: chosen) != nil else { return false }
        return chosenCAVerifiedFingerprint(forHubURL: url) == nil
    }

    /// For Settings: what is wrong with the saved file, if anything.
    enum ChosenCAProblem: Equatable {
        /// Never verified this Hub, and seen not to sign its certificate: it
        /// does nothing useful there.
        case doesNotMatch
        /// Verified this Hub before; now missing or another certificate. The
        /// agent does not start until it is checked again or removed.
        case changed

        var words: String {
            switch self {
            case .doesNotMatch: return AgentSettings.chosenCAMismatchMessage
            case .changed: return AgentSettings.chosenCAChangedMessage
            }
        }
    }

    var chosenCAProblem: ChosenCAProblem? {
        let chosen = tlsCAFile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chosen.isEmpty, let scope = chosenCAScope(of: hubURL) else { return nil }
        if case .unusable = chosenCAPin(chosen, forHubURL: hubURL) { return .changed }
        guard let fingerprint = Self.firstFingerprint(inPEMFile: chosen),
              storedRecord(Self.chosenCAMismatchRecord) == "\(scope) \(fingerprint)" else { return nil }
        return .doesNotMatch
    }

    /// Settings: the person chose `path` (empty removes the setting). It is
    /// saved only when it verifies the Hub alone; otherwise the words say why
    /// and the previous setting stays.
    @MainActor
    func chooseCAFile(_ path: String, check: ChosenCACheck = HubCATrust.verifiesAlone) async -> String? {
        let chosen = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if chosen.isEmpty {
            if !tlsCAFile.isEmpty { tlsCAFile = "" }
            forgetChosenCA()
            return nil
        }
        guard FileManager.default.fileExists(atPath: chosen) else { return Self.chosenCANotFoundMessage }
        guard let url = normalizedHubWebSocketURL(), url.hasPrefix("wss://"), let scope = chosenCAScope(of: url) else {
            // No wss:// Hub to check against yet: kept, and checked at the first start for one.
            tlsCAFile = chosen
            return nil
        }
        switch await check(url, chosen) {
        case .verified(let fingerprint):
            tlsCAFile = chosen
            recordChosenCAVerified(scope: scope, fingerprint: fingerprint)
            return nil
        case .mismatch: return Self.chosenCAMismatchMessage
        case .unreadable: return Self.chosenCAUnusableMessage
        case .unreachable: return Self.chosenCAUnreachableMessage
        }
    }

    /// At every start and after every connection, for a saved CA file that
    /// has never verified this Hub alone. Returns the one line for the log:
    /// nil when there was nothing to check.
    @MainActor
    func checkSavedChosenCA(check: ChosenCACheck = HubCATrust.verifiesAlone) async -> String? {
        let chosen = tlsCAFile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard chosenCANeedsCheck, let url = normalizedHubWebSocketURL(), let scope = chosenCAScope(of: url) else { return nil }
        let verdict = await check(url, chosen)
        // The setting may have changed while the Hub was asked.
        guard chosen == tlsCAFile.trimmingCharacters(in: .whitespacesAndNewlines), url == normalizedHubWebSocketURL() else { return nil }
        switch verdict {
        case .verified(let fingerprint):
            recordChosenCAVerified(scope: scope, fingerprint: fingerprint)
            return Self.chosenCANowOnlyRoot
        case .mismatch:
            if let fingerprint = Self.firstFingerprint(inPEMFile: chosen) {
                setStoredRecord("\(scope) \(fingerprint)", key: Self.chosenCAMismatchRecord)
                objectWillChange.send()
            }
            return Self.chosenCAKeptAsBeforeMismatch
        case .unreadable, .unreachable:
            return Self.chosenCAKeptAsBeforeNoAnswer
        }
    }
}
