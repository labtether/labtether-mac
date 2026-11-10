import Foundation

/// Where trusted Hub CAs live.
///
/// `ca.crt` is the CA of the Hub this Mac's token belongs to: the bundled
/// agent keeps it beside the token and verifies every connection against it.
/// While a token for one Hub is saved, a CA trusted for a different Hub must
/// not replace it (the agent would then accept that Hub and hand it the old
/// token). Such a CA waits in `pending-hub-ca.crt` and takes over only after
/// the person has confirmed the move and the old token is gone.
extension AgentSettings {
    static let managedHubCAName = "ca.crt"
    static let pendingHubCAName = "pending-hub-ca.crt"
    /// The Hub ("wss://host:port") the waiting CA was trusted for.
    static let pendingHubCAScopeRecord = "pendingHubCAScope"
    /// "<scope> <fingerprint>" of the CA the person trusted for a Hub with
    /// "Trust this Hub". A `ca.crt` without this record is one the agent kept
    /// from an enrollment answer; nobody chose it.
    static let trustedHubCARecord = "trustedHubCA"

    /// What the agent is given as the only root for the Hub's connections
    /// (`LABTETHER_TLS_CA_ONLY`): the system's roots then count for nothing,
    /// so a publicly trusted certificate on the Hub's name is refused too.
    enum HubCAPin: Equatable {
        /// No CA of the person's choosing: the agent verifies as before.
        case none
        /// This file is the only root.
        case file(String)
        /// A CA was chosen or trusted, but its file cannot be used. The agent
        /// is not started on weaker terms; the words say what to do.
        case unusable(String)
    }

    static let chosenCAUnusableMessage = "The CA certificate file in Settings › Security cannot be read."
    static let trustedCAUnusableMessage =
        "The certificate this Mac trusted for the Hub is missing. Trust the Hub again with Test connection in Settings › Connection."

    /// A CA file chosen in Settings, or the CA trusted for the Hub in use.
    var hubCAPin: HubCAPin {
        let chosen = tlsCAFile.trimmingCharacters(in: .whitespacesAndNewlines)
        if !chosen.isEmpty {
            // A missing file is named by the settings check before any start.
            guard FileManager.default.fileExists(atPath: chosen) else { return .file(chosen) }
            return Self.firstFingerprint(inPEMFile: chosen) != nil ? .file(chosen) : .unusable(Self.chosenCAUnusableMessage)
        }
        guard let scope = pendingHubScope, let trusted = trustedHubCAFingerprint(for: scope) else { return .none }
        guard Self.firstFingerprint(inPEMFile: managedHubCAPath) == trusted else {
            return .unusable(Self.trustedCAUnusableMessage)
        }
        return .file(managedHubCAPath)
    }

    /// True when the CA file a check of `hubURL` uses is the only root: one
    /// the person chose or trusted. The app's own checks then judge a Hub the
    /// way the agent will.
    func hubCAIsOnlyRoot(forHubURL hubURL: String) -> Bool {
        let file = effectiveTLSCAFile(forHubURL: hubURL)
        if file.isEmpty { return false }
        if file != managedHubCAPath { return true }   // chosen in Settings, or trusted and waiting
        return hubScope(of: hubURL).flatMap { trustedHubCAFingerprint(for: $0) } != nil
    }

    /// The fingerprint the person trusted for `scope`: recorded for that
    /// address, or for the token's Hub when the address is known to be it.
    private func trustedHubCAFingerprint(for scope: String) -> String? {
        let parts = storedRecord(Self.trustedHubCARecord).split(separator: " ").map(String.init)
        guard parts.count == 2 else { return nil }
        if parts[0] == scope { return parts[1] }
        if parts[0] == savedTokenScope, isKnownSameHub(scope) { return parts[1] }
        return nil
    }

    private static func firstFingerprint(inPEMFile path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path), data.count <= 1_048_576,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return HubCATrust.certificates(fromPEM: text).first.map { HubCATrust.fingerprint(of: $0) }
    }

    var managedHubCAPath: String {
        appSupportDirectory.appendingPathComponent(Self.managedHubCAName).path
    }

    var pendingHubCAPath: String {
        appSupportDirectory.appendingPathComponent(Self.pendingHubCAName).path
    }

    var hasManagedHubCA: Bool {
        FileManager.default.fileExists(atPath: managedHubCAPath)
    }

    private func hubScope(of hubURL: String) -> String? {
        AgentSettingsNormalization.canonicalHubWebSocketURL(from: hubURL)
            .flatMap { Self.credentialScope(forHubWebSocketURL: $0) }
    }

    /// The CA file a TLS check of `hubURL` uses: the CA waiting for exactly
    /// that Hub, else the one typed in Settings › Security, else the token
    /// Hub's CA. The waiting CA comes first because a file typed for the
    /// token's Hub says nothing about another Hub.
    func effectiveTLSCAFile(forHubURL hubURL: String) -> String {
        if let scope = hubScope(of: hubURL), storedRecord(Self.pendingHubCAScopeRecord) == scope,
           FileManager.default.fileExists(atPath: pendingHubCAPath) {
            return pendingHubCAPath
        }
        let typed = tlsCAFile.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        return hasManagedHubCA ? managedHubCAPath : ""
    }

    var effectiveTLSCAFile: String { effectiveTLSCAFile(forHubURL: hubURL) }

    /// True when trusting a CA for `hubURL` must not touch the token Hub's CA:
    /// a token for another Hub is saved and this address is not known to be
    /// that same Hub.
    func trustMustWait(forHubURL hubURL: String) -> Bool {
        guard let tokenScope = savedTokenScope, let scope = hubScope(of: hubURL) else { return false }
        return scope != tokenScope && !isKnownSameHub(scope)
    }

    /// "Trust this Hub" for the Hub at `hubURL`. A CA file typed in Settings
    /// did not validate this Hub, so the trusted CA takes its place.
    func saveTrustedHubCA(_ offer: HubCAOffer, forHubURL hubURL: String) throws {
        let waits = trustMustWait(forHubURL: hubURL)
        try writeChildFile(Data(offer.pem.utf8), name: waits ? Self.pendingHubCAName : Self.managedHubCAName)
        if waits {
            // Nothing about the token's Hub changes until the move is confirmed.
            setStoredRecord(hubScope(of: hubURL) ?? "", key: Self.pendingHubCAScopeRecord)
            return
        }
        setStoredRecord("\(hubScope(of: hubURL) ?? "") \(offer.fingerprint)", key: Self.trustedHubCARecord)
        if !tlsCAFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { tlsCAFile = "" }
    }

    /// Undoes a trust whose own verification then failed.
    func removeTrustedHubCA(forHubURL hubURL: String) {
        if trustMustWait(forHubURL: hubURL) {
            discardPendingHubCA()
        } else {
            _ = try? removeChildFile(Self.managedHubCAName)
            setStoredRecord("", key: Self.trustedHubCARecord)
        }
    }

    func discardPendingHubCA() {
        _ = try? removeChildFile(Self.pendingHubCAName)
        setStoredRecord("", key: Self.pendingHubCAScopeRecord)
    }

    /// After a confirmed move to `scope` removed the old Hub's token and CA:
    /// the CA trusted for the new Hub becomes the agent's CA.
    func promotePendingHubCA(for scope: String) throws {
        guard storedRecord(Self.pendingHubCAScopeRecord) == scope,
              let data = FileManager.default.contents(atPath: pendingHubCAPath) else { return }
        try writeChildFile(data, name: Self.managedHubCAName)
        discardPendingHubCA()
        if let trusted = Self.firstFingerprint(inPEMFile: managedHubCAPath) {
            setStoredRecord("\(scope) \(trusted)", key: Self.trustedHubCARecord)
        }
        // A CA file typed in Settings belonged to the Hub that was left.
        if !tlsCAFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { tlsCAFile = "" }
    }

    private func writeChildFile(_ data: Data, name: String) throws {
        if let stateLocation {
            _ = try? stateLocation.removeRegularFile(name)
            try stateLocation.write(data, name: name)
        } else {
            let url = appSupportDirectory.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }
}

/// One "Test connection" with the trust question in the middle: used by
/// setup and by Settings so both ask the same way.
@MainActor
final class HubTrustFlow: ObservableObject {
    typealias QuickTest = (_ hubURL: String, _ skipVerify: Bool, _ caFile: String, _ caOnly: Bool) async -> ConnectionTestResult
    typealias Check = (_ hubURL: String, _ savedCAFile: String) async -> HubCACheck

    /// Set while the person decides; nothing is saved or sent meanwhile.
    @Published private(set) var offer: HubCAOffer?
    @Published private(set) var isWorking = false
    /// The last test stopped on the Hub's certificate (never a reason to go on).
    private(set) var stoppedOnCertificate = false

    private var hubURL = ""
    private let quickTest: QuickTest
    private let check: Check

    init(
        quickTest: @escaping QuickTest = {
            await ConnectionTester.quickTest(hubURL: $0, tlsSkipVerify: $1, tlsCAFile: $2, tlsCAOnly: $3)
        },
        check: @escaping Check = { await HubCATrust.check(hubURL: $0, savedCAFile: $1) }
    ) {
        self.quickTest = quickTest
        self.check = check
    }

    /// Tests with normal verification. When only the issuer is unknown,
    /// `offer` is set and nil is returned until the person decides.
    func test(hubURL: String, settings: AgentSettings) async -> ConnectionTestResult? {
        isWorking = true
        defer { isWorking = false }
        offer = nil
        stoppedOnCertificate = false
        self.hubURL = hubURL
        let caFile = settings.effectiveTLSCAFile(forHubURL: hubURL)
        let result = await quickTest(hubURL, settings.tlsSkipVerify, caFile, settings.hubCAIsOnlyRoot(forHubURL: hubURL))
        guard case .failure(let message) = result, message == ConnectionTester.certificateFailureMessage else {
            return result
        }
        stoppedOnCertificate = true
        // For an address that is not the token's Hub, the token Hub's CA says
        // nothing: this is a first look at another Hub, not a changed certificate.
        switch await check(hubURL, settings.trustMustWait(forHubURL: hubURL) ? "" : caFile) {
        case .offer(let found):
            offer = found
            return nil
        case .refused(let words):
            return .failure(error: words)
        case .trusted, .unreachable:
            return result
        }
    }

    /// "Trust this Hub": keeps the CA, then tests again with normal
    /// verification. Only a success lets the caller go on.
    func trust(settings: AgentSettings) async -> ConnectionTestResult {
        guard let offer else { return .failure(error: ConnectionTester.certificateFailureMessage) }
        isWorking = true
        defer { isWorking = false }
        do {
            try settings.saveTrustedHubCA(offer, forHubURL: hubURL)
        } catch {
            return .failure(error: "The Hub's certificate could not be saved.")
        }
        let result = await quickTest(
            hubURL, settings.tlsSkipVerify, settings.effectiveTLSCAFile(forHubURL: hubURL),
            settings.hubCAIsOnlyRoot(forHubURL: hubURL)
        )
        if case .failure(let message) = result, message == ConnectionTester.certificateFailureMessage {
            settings.removeTrustedHubCA(forHubURL: hubURL)
        } else {
            stoppedOnCertificate = false
        }
        self.offer = nil
        return result
    }

    func cancel() {
        offer = nil
    }
}
