import Foundation

/// Where the trusted Hub CA lives: the `ca.crt` the bundled agent already
/// keeps beside its token and reads when no CA file is typed in Settings.
extension AgentSettings {
    static let managedHubCAName = "ca.crt"
    /// The Hub ("wss://host:port") the managed CA was trusted for in setup.
    static let trustedHubCAScopeRecord = "trustedHubCAScope"

    var managedHubCAPath: String {
        appSupportDirectory.appendingPathComponent(Self.managedHubCAName).path
    }

    var hasManagedHubCA: Bool {
        FileManager.default.fileExists(atPath: managedHubCAPath)
    }

    /// The CA file every TLS check in the app uses: the one typed in
    /// Settings › Security, else the CA kept for this Hub.
    var effectiveTLSCAFile: String {
        let typed = tlsCAFile.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        return hasManagedHubCA ? managedHubCAPath : ""
    }

    /// "Trust this Hub": keeps the CA for the Hub at `hubURL`. A CA file typed
    /// in Settings did not validate this Hub, so the kept CA takes its place.
    func saveTrustedHubCA(_ offer: HubCAOffer, forHubURL hubURL: String) throws {
        let data = Data(offer.pem.utf8)
        if let stateLocation {
            _ = try? stateLocation.removeRegularFile(Self.managedHubCAName)
            try stateLocation.write(data, name: Self.managedHubCAName)
        } else {
            let url = URL(fileURLWithPath: managedHubCAPath)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        let scope = AgentSettingsNormalization.canonicalHubWebSocketURL(from: hubURL)
            .flatMap { Self.credentialScope(forHubWebSocketURL: $0) }
        setStoredRecord(scope ?? "", key: Self.trustedHubCAScopeRecord)
        if !tlsCAFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { tlsCAFile = "" }
    }

    func removeTrustedHubCA() {
        _ = try? removeChildFile(Self.managedHubCAName)
        setStoredRecord("", key: Self.trustedHubCAScopeRecord)
    }
}

/// One "Test connection" with the trust question in the middle: used by
/// setup and by Settings so both ask the same way.
@MainActor
final class HubTrustFlow: ObservableObject {
    typealias QuickTest = (_ hubURL: String, _ skipVerify: Bool, _ caFile: String) async -> ConnectionTestResult
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
        quickTest: @escaping QuickTest = { await ConnectionTester.quickTest(hubURL: $0, tlsSkipVerify: $1, tlsCAFile: $2) },
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
        let result = await quickTest(hubURL, settings.tlsSkipVerify, settings.effectiveTLSCAFile)
        guard case .failure(let message) = result, message == ConnectionTester.certificateFailureMessage else {
            return result
        }
        stoppedOnCertificate = true
        switch await check(hubURL, settings.effectiveTLSCAFile) {
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
        let result = await quickTest(hubURL, settings.tlsSkipVerify, settings.effectiveTLSCAFile)
        if case .failure(let message) = result, message == ConnectionTester.certificateFailureMessage {
            settings.removeTrustedHubCA()
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
