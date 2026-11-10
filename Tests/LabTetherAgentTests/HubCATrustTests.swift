import XCTest
@testable import LabTetherAgent

/// Risks: setup offers trust for a certificate that has another fault, shows
/// a fingerprint that is not the one the Hub console shows, or lets the
/// enrollment token leave before the person has trusted the Hub.
final class HubCATrustTests: XCTestCase {
    // Throwaway certificates made for this test (their keys were not kept):
    // a CA, a server certificate for hub.example.com signed by it (valid
    // 2026-11-10 to 2029-01-18), and an unrelated CA.
    static let caPEM = """
        -----BEGIN CERTIFICATE-----
        MIIBmDCCAT2gAwIBAgIUAzd+au5P9Ja6eStEdHzUB3SBQpcwCgYIKoZIzj0EAwIw
        GTEXMBUGA1UEAwwORXhhbXBsZSBIdWIgQ0EwHhcNMjYxMTEwMDYwNzQzWhcNNDYx
        MTA1MDYwNzQzWjAZMRcwFQYDVQQDDA5FeGFtcGxlIEh1YiBDQTBZMBMGByqGSM49
        AgEGCCqGSM49AwEHA0IABEEsI2Q9hda49M6kqcsrL4fUT5CLFj+LzjN2FT9/u/Ss
        28OaHhNqcLXm8hSZjCz6Nh9HG4JbabC7MEp2opnU4j+jYzBhMB0GA1UdDgQWBBSV
        u5AByx+enKBzkrJFtRUp6BcfSzAfBgNVHSMEGDAWgBSVu5AByx+enKBzkrJFtRUp
        6BcfSzAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBBjAKBggqhkjOPQQD
        AgNJADBGAiEAuVjB+SbUDgSaQAFc0JUxVcBqELa0Ax7OXpe6oRWq1ikCIQDn/imR
        /x5LkmhYoHNdqT1zM5HI3yxMHe67E6+9YoWDQQ==
        -----END CERTIFICATE-----
        """
    private static let leafPEM = """
        -----BEGIN CERTIFICATE-----
        MIIBxTCCAWugAwIBAgIUfITXgDgvY1fMQ6BpbZcWs89dEMkwCgYIKoZIzj0EAwIw
        GTEXMBUGA1UEAwwORXhhbXBsZSBIdWIgQ0EwHhcNMjYxMTEwMDYwNzQzWhcNMjkw
        MTE4MDYwNzQzWjAaMRgwFgYDVQQDDA9odWIuZXhhbXBsZS5jb20wWTATBgcqhkjO
        PQIBBggqhkjOPQMBBwNCAASfJRXTBtrNMvamisH6ET2htoXnHv4XuzgVHjv1hlw7
        E+F9WhdeSL8zw0MtzkHIXcraoiPXhHVkjCFkAsdFxvC6o4GPMIGMMBoGA1UdEQQT
        MBGCD2h1Yi5leGFtcGxlLmNvbTATBgNVHSUEDDAKBggrBgEFBQcDATAOBgNVHQ8B
        Af8EBAMCB4AwCQYDVR0TBAIwADAdBgNVHQ4EFgQUp7vtV0qIFZyTlkML0JFabD1V
        uZswHwYDVR0jBBgwFoAUlbuQAcsfnpygc5KyRbUVKegXH0swCgYIKoZIzj0EAwID
        SAAwRQIgExZxLR9rb2NVApA3RTaDDVzlTe1lmImuBczV3HnVhW4CIQDqAlJWtoIf
        RGdOHkGeUodfrY96EZHHNFXtJJQsDw2rpQ==
        -----END CERTIFICATE-----
        """
    private static let otherCAPEM = """
        -----BEGIN CERTIFICATE-----
        MIIBlzCCAT2gAwIBAgIUZxwsMuFqw1aFEeSZQOcBRglydngwCgYIKoZIzj0EAwIw
        GTEXMBUGA1UEAwwOQW5vdGhlciBIdWIgQ0EwHhcNMjYxMTEwMDYwNzQzWhcNNDYx
        MTA1MDYwNzQzWjAZMRcwFQYDVQQDDA5Bbm90aGVyIEh1YiBDQTBZMBMGByqGSM49
        AgEGCCqGSM49AwEHA0IABM5gXeY1NH5/4gSh5kA8r2GP1QQrxGR+JeduRloN+tqE
        0AE1Id1tBPOR1SKoaYCYXnrM1BI1WUWBU8MB50KKhc2jYzBhMB0GA1UdDgQWBBSa
        QwePlj1441oN1sMgA27uEW1gfjAfBgNVHSMEGDAWgBSaQwePlj1441oN1sMgA27u
        EW1gfjAPBgNVHRMBAf8EBTADAQH/MA4GA1UdDwEB/wQEAwIBBjAKBggqhkjOPQQD
        AgNIADBFAiAw6c+JwBCAoLQcuw60cnxdzOOIDy4khI9FEizvg5O/aAIhAPBhqtiP
        /1zBjF/BgzdM2tuiVqik61xKvqmbs3MMAZn9
        -----END CERTIFICATE-----
        """
    static let caFingerprint = "2d7e54ca6aa0d37f9256473f4dd8a70f64497e02220cb27bcb31ac9008df1a91"
    private let host = "hub.example.com"
    /// Inside the server certificate's validity, so the test does not age.
    private let day = Date(timeIntervalSince1970: 1_812_000_000) // 2027-06-03

    private func certificate(_ pem: String) throws -> SecCertificate {
        try XCTUnwrap(HubCATrust.certificates(fromPEM: pem).first)
    }

    func testFingerprintIsTheSHA256OfTheCertificateInGroupsOfFour() throws {
        let ca = try certificate(Self.caPEM)
        XCTAssertEqual(HubCATrust.fingerprint(of: ca), Self.caFingerprint)
        let offer = HubCAOffer(pem: HubCATrust.pem(of: ca), fingerprint: Self.caFingerprint)
        XCTAssertEqual(offer.groupedRows, [
            "2d7e 54ca 6aa0 d37f 9256 473f 4dd8 a70f",
            "6449 7e02 220c b27b cb31 ac90 08df 1a91",
        ])
        // What is saved is the same certificate.
        XCTAssertEqual(HubCATrust.fingerprint(of: try certificate(offer.pem)), Self.caFingerprint)
    }

    func testOnlyAnUnknownIssuerIsOfferedForTrust() throws {
        let ca = try certificate(Self.caPEM), leaf = try certificate(Self.leafPEM), other = try certificate(Self.otherCAPEM)
        func check(_ chain: [SecCertificate], host: String = "hub.example.com", saved: [SecCertificate] = [],
                   fetched: SecCertificate? = nil, at date: Date? = nil) -> HubCACheck {
            HubCATrust.evaluate(chain: chain, host: host, savedAnchors: saved, fetchedCA: fetched, at: date ?? day)
        }
        let offered = HubCAOffer(pem: HubCATrust.pem(of: ca), fingerprint: Self.caFingerprint)
        XCTAssertEqual(check([leaf, ca]), .offer(offered), "CA sent in the chain")
        XCTAssertEqual(check([leaf], fetched: ca), .offer(offered), "CA from /api/v1/ca.crt")
        // The Hub's certificate does not chain to the CA it offers: no trust.
        XCTAssertEqual(check([leaf], fetched: other), .refused(HubCATrust.mismatchMessage))
        XCTAssertEqual(check([leaf]), .refused(HubCATrust.noOwnCAMessage))
        // Other faults stay errors in plain words.
        XCTAssertEqual(check([leaf, ca], host: "nas01.example.com"), .refused(HubCATrust.wrongHostMessage))
        XCTAssertEqual(check([leaf, ca], at: Date(timeIntervalSince1970: 1_900_000_000)), .refused(HubCATrust.expiredMessage))
        // Once trusted there is no question; another CA later is a change.
        XCTAssertEqual(check([leaf], saved: [ca]), .trusted)
        var changed = offered
        changed.replacesSavedCA = true
        XCTAssertEqual(check([leaf, ca], saved: [other]), .offer(changed))
        XCTAssertTrue(HubCATrust.chainsOnly(to: [ca], chain: [leaf], host: host, at: day))
        XCTAssertFalse(HubCATrust.chainsOnly(to: [other], chain: [leaf], host: host, at: day))
    }

    @MainActor
    func testTokenStaysInSetupUntilTheHubIsTrustedAndVerified() async throws {
        let suite = "LabTetherAgentTests.\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lt-trust-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            store.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        let settings = AgentSettings(testSettingsStore: store, appSupportDirectory: folder)
        let offer = HubCAOffer(pem: Self.caPEM + "\n", fingerprint: Self.caFingerprint)
        var testedWith: [String] = []
        let trust = HubTrustFlow(
            quickTest: { _, _, caFile, _ in
                testedWith.append(caFile)
                return caFile.isEmpty ? .failure(error: ConnectionTester.certificateFailureMessage) : .success(responseTimeMs: 3)
            },
            check: { _, _ in .offer(offer) }
        )
        let setup = OnboardingState()
        setup.hubURL = "hub.example.com:8443"
        setup.tokenValue = "one-use-token"

        var step = await setup.connect(settings: settings, trust: trust)
        XCTAssertEqual(step, .waitingForTrust)
        XCTAssertEqual(trust.offer, offer)
        XCTAssertEqual(settings.enrollmentToken, "", "the token has not left the setup window")
        XCTAssertFalse(settings.hasCompletedOnboarding)
        XCTAssertFalse(settings.hasManagedHubCA)

        // Cancel saves nothing.
        setup.cancelTrust(trust)
        XCTAssertNil(trust.offer)
        XCTAssertFalse(settings.hasManagedHubCA)
        XCTAssertEqual(settings.enrollmentToken, "")

        // Trust: the CA is kept, the Hub verifies against it, then setup goes on.
        step = await setup.connect(settings: settings, trust: trust)
        XCTAssertEqual(step, .waitingForTrust)
        step = await setup.trustHub(settings: settings, trust: trust)
        XCTAssertEqual(step, .go)
        XCTAssertEqual(settings.effectiveTLSCAFile, settings.managedHubCAPath)
        XCTAssertEqual(testedWith.last, settings.managedHubCAPath, "verified with the kept CA before going on")
        XCTAssertEqual(settings.enrollmentToken, "one-use-token")
        XCTAssertTrue(settings.hasCompletedOnboarding)

        // The CA download asks for the public file and carries nothing.
        let request = try XCTUnwrap(HubCATrust.caRequest(for: XCTUnwrap(URL(string: "https://hub.example.com:8443/api/v1/discover"))))
        XCTAssertEqual(request.url?.absoluteString, "https://hub.example.com:8443/api/v1/ca.crt")
        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    // MARK: - Trust and the saved token (security)

    @MainActor
    private func enrolledSettings(_ store: UserDefaults, _ folder: URL) throws -> AgentSettings {
        // This Mac is enrolled with Hub A: token, A's CA, and what was
        // recorded about A when the token connected there.
        let settings = AgentSettings(testSettingsStore: store, appSupportDirectory: folder)
        settings.hubURL = "wss://nas01.example.com:8443/ws/agent"
        try settings.persistRuntimeSecret("hub-a-token", to: settings.tokenFilePath, issueKey: "test.token", label: "Test token")
        try Data(Self.caPEM.utf8).write(to: URL(fileURLWithPath: settings.managedHubCAPath))
        XCTAssertFalse(try settings.dropCredentialsFromOtherHub())
        settings.setStoredRecord("wss://nas01.example.com:8443 \(Self.caFingerprint)", key: AgentSettings.hubCARecord)
        settings.setStoredRecord("wss://nas01.example.com:8443 key-of-hub-a", key: AgentSettings.hubServerKeyRecord)
        return settings
    }

    /// The hole a review found: with a token for Hub A saved, pointing the app
    /// at Hub B and pressing "Trust this Hub" replaced A's CA with B's, and
    /// the same-Hub check then took B for A, so A's token would go to B.
    @MainActor
    func testTrustingAnotherHubNeverMakesItTheTokensHub() async throws {
        let suite = "LabTetherAgentTests.\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lt-trust-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            store.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        let settings = try enrolledSettings(store, folder)
        let hubB = "wss://nas02.example.com:8443/ws/agent"
        let offerB = HubCAOffer(pem: Self.otherCAPEM + "\n", fingerprint: "b-ca-fingerprint")
        let probeB = HubIdentityProbe(holdsServerKey: { _, _ in .notProven }, ownCA: { _ in "b-ca-fingerprint" })

        // The address changes to Hub B and the person trusts B's certificate.
        settings.hubURL = hubB
        var checkedAgainst: [String] = []
        let trust = HubTrustFlow(
            quickTest: { _, _, caFile, _ in
                caFile == settings.pendingHubCAPath ? .success(responseTimeMs: 2)
                    : .failure(error: ConnectionTester.certificateFailureMessage)
            },
            check: { _, saved in checkedAgainst.append(saved); return .offer(offerB) }
        )
        let first = await trust.test(hubURL: hubB, settings: settings)
        XCTAssertNil(first)
        XCTAssertEqual(checkedAgainst, [""], "Hub A's CA is not what B is measured against")
        let trusted = await trust.trust(settings: settings)
        XCTAssertEqual(trusted, .success(responseTimeMs: 2))

        // Hub A's CA is still the agent's CA; B's waits beside it.
        XCTAssertEqual(try String(contentsOfFile: settings.managedHubCAPath, encoding: .utf8), Self.caPEM)
        XCTAssertEqual(try String(contentsOfFile: settings.pendingHubCAPath, encoding: .utf8), Self.otherCAPEM + "\n")
        // B is another Hub, whatever was just trusted for it: the warning comes first.
        XCTAssertTrue(settings.hubChangeNeedsConfirmation)
        let verdict = await settings.checkHubChange(probe: probeB)
        XCTAssertEqual(verdict, .otherHub)
        XCTAssertTrue(settings.hubChangeNeedsConfirmation)
        XCTAssertTrue(settings.hasPersistedAgentToken, "nothing is removed before the person agrees")
        XCTAssertFalse(settings.savedTokenOrigins().contains("nas02.example.com:8443"))

        // Only after Continue: A's token goes, then B's CA becomes the agent's CA.
        settings.confirmedHubChangeScope = "wss://nas02.example.com:8443"
        XCTAssertTrue(try settings.dropCredentialsFromOtherHub())
        XCTAssertFalse(settings.hasPersistedAgentToken)
        XCTAssertEqual(try String(contentsOfFile: settings.managedHubCAPath, encoding: .utf8), Self.otherCAPEM + "\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: settings.pendingHubCAPath))
        XCTAssertEqual(settings.storedRecord(AgentSettings.hubCARecord), "")
    }

    /// A CA file typed in Settings belongs to the token's Hub. Trusting
    /// another Hub must not clear it before the move is confirmed, and the
    /// other Hub is checked against its own waiting CA, not against that file.
    @MainActor
    func testATypedCAFileStaysUntilTheMoveToAnotherHubIsConfirmed() async throws {
        let suite = "LabTetherAgentTests.\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lt-trust-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            store.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        let settings = try enrolledSettings(store, folder)
        let hubA = settings.hubURL
        let typed = folder.appendingPathComponent("typed-ca.pem").path
        settings.tlsCAFile = typed
        let hubB = "wss://nas02.example.com:8443/ws/agent"
        settings.hubURL = hubB
        let trust = HubTrustFlow(
            quickTest: { _, _, caFile, _ in
                caFile == settings.pendingHubCAPath ? .success(responseTimeMs: 2)
                    : .failure(error: ConnectionTester.certificateFailureMessage)
            },
            check: { _, _ in .offer(HubCAOffer(pem: Self.otherCAPEM + "\n", fingerprint: "b-ca-fingerprint")) }
        )
        let first = await trust.test(hubURL: hubB, settings: settings)
        XCTAssertNil(first)
        let trusted = await trust.trust(settings: settings)
        XCTAssertEqual(trusted, .success(responseTimeMs: 2))
        XCTAssertEqual(settings.tlsCAFile, typed, "nothing about Hub A changes while the person decides")
        XCTAssertEqual(settings.effectiveTLSCAFile(forHubURL: hubA), typed)
        XCTAssertEqual(settings.effectiveTLSCAFile(forHubURL: hubB), settings.pendingHubCAPath)

        settings.confirmedHubChangeScope = "wss://nas02.example.com:8443"
        XCTAssertTrue(try settings.dropCredentialsFromOtherHub())
        XCTAssertEqual(settings.tlsCAFile, "", "the typed file belonged to the Hub that was left")
        XCTAssertEqual(settings.effectiveTLSCAFile, settings.managedHubCAPath)
    }

    /// The agent trusts the system's roots as well as the Hub's CA unless it
    /// is told otherwise, so a publicly trusted certificate on the Hub's name
    /// would be accepted. A CA the person chose or trusted is therefore handed
    /// over as the only root; a `ca.crt` the agent kept by itself is not, and
    /// a trusted CA whose file is gone stops the start instead of weakening it.
    @MainActor
    func testACATheTrustedHubIsTheAgentsOnlyRoot() async throws {
        let suite = "LabTetherAgentTests.\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lt-trust-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            store.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        let settings = try enrolledSettings(store, folder)
        XCTAssertEqual(settings.hubCAPin, .none, "a CA nobody chose stays one root among the system's")
        XCTAssertNil(try settings.buildEnvironment()["LABTETHER_TLS_CA_ONLY"])
        XCTAssertFalse(settings.hubCAIsOnlyRoot(forHubURL: settings.hubURL))

        // The person trusts this Hub's certificate.
        let hub = settings.hubURL
        let trust = HubTrustFlow(
            quickTest: { _, _, caFile, caOnly in
                caFile == settings.managedHubCAPath && caOnly ? .success(responseTimeMs: 2)
                    : .failure(error: ConnectionTester.certificateFailureMessage)
            },
            check: { _, _ in .offer(HubCAOffer(pem: Self.caPEM, fingerprint: Self.caFingerprint)) }
        )
        let first = await trust.test(hubURL: hub, settings: settings)
        XCTAssertNil(first)
        let trusted = await trust.trust(settings: settings)
        XCTAssertEqual(trusted, .success(responseTimeMs: 2), "the app checks the Hub the way the agent will")
        XCTAssertEqual(settings.hubCAPin, .file(settings.managedHubCAPath))
        let environment = try settings.buildEnvironment()
        XCTAssertEqual(environment["LABTETHER_TLS_CA_FILE"], settings.managedHubCAPath)
        XCTAssertEqual(environment["LABTETHER_TLS_CA_ONLY"], "true")

        // The trusted file goes missing: no start on weaker terms.
        try FileManager.default.removeItem(atPath: settings.managedHubCAPath)
        XCTAssertEqual(settings.hubCAPin, .unusable(AgentSettings.trustedCAUnusableMessage))
        XCTAssertThrowsError(try settings.buildEnvironment()) { error in
            XCTAssertEqual(error.localizedDescription, AgentSettings.trustedCAUnusableMessage)
        }
    }

    /// Showing the Hub's certificate is not proof of being the Hub: a
    /// certificate is public. An address that answers without finishing a
    /// handshake with the Hub's key is another Hub; one that does not answer
    /// is unknown. Neither keeps the token without asking.
    @MainActor
    func testAnAddressThatCannotProveTheHubsKeyIsNotTheSameHub() async throws {
        let suite = "LabTetherAgentTests.\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lt-trust-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            store.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        let settings = try enrolledSettings(store, folder)
        settings.hubURL = "wss://192.0.2.10:8443/ws/agent"
        var askedFor: [String] = []
        let copiedCertificate = HubIdentityProbe(
            holdsServerKey: { _, key in askedFor.append(key); return .notProven },
            ownCA: { _ in nil }
        )
        let shown = await settings.checkHubChange(probe: copiedCertificate)
        XCTAssertEqual(shown, .otherHub)
        XCTAssertEqual(askedFor, ["key-of-hub-a"], "the address is asked to prove the key recorded for the token's Hub")
        let silent = HubIdentityProbe(holdsServerKey: { _, _ in .unreachable }, ownCA: { _ in nil })
        let unanswered = await settings.checkHubChange(probe: silent)
        XCTAssertEqual(unanswered, .unknown)
        XCTAssertTrue(settings.hubChangeNeedsConfirmation)
        XCTAssertFalse(settings.savedTokenOrigins().contains("192.0.2.10:8443"))
    }

    /// The good path stays: the same Hub at another address (the CA and
    /// server key recorded at enrollment) keeps the token.
    @MainActor
    func testSameHubAtAnotherAddressIsStillTheSameHub() async throws {
        let suite = "LabTetherAgentTests.\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lt-trust-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            store.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        let settings = try enrolledSettings(store, folder)
        settings.hubURL = "wss://192.0.2.10:8443/ws/agent"
        let sameHub = HubIdentityProbe(holdsServerKey: { _, key in key == "key-of-hub-a" ? .proven : .notProven }, ownCA: { _ in Self.caFingerprint })
        let verdict = await settings.checkHubChange(probe: sameHub)
        XCTAssertEqual(verdict, .sameHub)
        XCTAssertFalse(settings.hubChangeNeedsConfirmation)
        XCTAssertFalse(try settings.dropCredentialsFromOtherHub())
        XCTAssertTrue(settings.hasPersistedAgentToken)
        XCTAssertEqual(try String(contentsOfFile: settings.managedHubCAPath, encoding: .utf8), Self.caPEM)

        // With nothing recorded for the token's Hub there is no proof at all.
        let bare = AgentSettings(testSettingsStore: try XCTUnwrap(UserDefaults(suiteName: suite + ".bare")),
                                 appSupportDirectory: folder.appendingPathComponent("bare"))
        try FileManager.default.createDirectory(at: bare.appSupportDirectory, withIntermediateDirectories: true)
        bare.hubURL = "wss://nas01.example.com:8443/ws/agent"
        try bare.persistRuntimeSecret("hub-a-token", to: bare.tokenFilePath, issueKey: "test.token", label: "Test token")
        XCTAssertFalse(try bare.dropCredentialsFromOtherHub())
        bare.hubURL = "wss://192.0.2.10:8443/ws/agent"
        let unknown = await bare.checkHubChange(probe: sameHub)
        XCTAssertEqual(unknown, .unknown)
        UserDefaults().removePersistentDomain(forName: suite + ".bare")
    }
}
