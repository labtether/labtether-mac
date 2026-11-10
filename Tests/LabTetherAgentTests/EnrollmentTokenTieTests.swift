import XCTest
@testable import LabTetherAgent

/// A token file that an installer or a script put in the app's folder was
/// sent to whichever Hub the address pointed at: made for Hub A, it went to
/// Hub B after the address was changed. It must only ever reach the Hub it
/// was made for.
@MainActor
final class EnrollmentTokenTieTests: XCTestCase {
    private let hubA = "wss://nas01.example.com:8443/ws/agent"
    private let hubB = "wss://nas02.example.com:8443/ws/agent"

    private func makeSettings() throws -> (AgentSettings, URL, () -> Void) {
        let suite = "LabTetherAgentTests.\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lt-token-tie-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let settings = AgentSettings(testSettingsStore: store, appSupportDirectory: folder)
        return (settings, folder, {
            store.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        })
    }

    private func installToken(_ settings: AgentSettings, tie: String?) throws {
        try Data("installer-token-for-hub-a\n".utf8).write(to: URL(fileURLWithPath: settings.enrollmentTokenFilePath))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settings.enrollmentTokenFilePath)
        let tieURL = settings.appSupportDirectory.appendingPathComponent(AgentSettings.enrollmentTokenTieName)
        try? FileManager.default.removeItem(at: tieURL)
        if let tie { try Data(tie.utf8).write(to: tieURL) }
    }

    func testAnInstallersTokenIsSentOnlyToTheHubItWasMadeFor() throws {
        let (settings, _, cleanup) = try makeSettings()
        defer { cleanup() }
        settings.hubURL = hubA
        try installToken(settings, tie: #"{"hub_url":"wss://nas01.example.com:8443"}"#)
        XCTAssertEqual(settings.enrollmentTokenFile, .tied)
        XCTAssertTrue(settings.isConfigured)
        XCTAssertEqual(try settings.buildEnvironment()["LABTETHER_ENROLLMENT_TOKEN_FILE"], settings.enrollmentTokenFilePath)

        // The address is changed to another Hub in Settings.
        settings.hubURL = hubB
        XCTAssertEqual(settings.enrollmentTokenFile, .untied)
        XCTAssertNil(try settings.buildEnvironment()["LABTETHER_ENROLLMENT_TOKEN_FILE"], "Hub A's token is not handed to an agent started for Hub B")
        XCTAssertFalse(settings.isConfigured, "so setup asks for a token from Hub B")
        XCTAssertEqual(
            try String(contentsOfFile: settings.enrollmentTokenFilePath, encoding: .utf8), "installer-token-for-hub-a\n",
            "the file is left as the installer wrote it"
        )

        // Back on Hub A it is usable again.
        settings.hubURL = hubA
        XCTAssertEqual(settings.enrollmentTokenFile, .tied)
    }

    func testATokenFileWithoutATieIsNeverSent() throws {
        let (settings, _, cleanup) = try makeSettings()
        defer { cleanup() }
        settings.hubURL = hubA
        try installToken(settings, tie: nil)
        XCTAssertEqual(settings.enrollmentTokenFile, .untied)
        XCTAssertFalse(settings.isConfigured)
        XCTAssertNil(try settings.buildEnvironment()["LABTETHER_ENROLLMENT_TOKEN_FILE"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: settings.enrollmentTokenFilePath))
    }

    /// The Linux install command carries the Hub's CA fingerprint. A tie with
    /// one holds only once the agent trusts exactly that CA for the Hub.
    func testATieWithAFingerprintNeedsThatCATrusted() throws {
        let (settings, _, cleanup) = try makeSettings()
        defer { cleanup() }
        settings.hubURL = hubA
        let tie = #"{"hub_url":"nas01.example.com:8443","ca_fingerprint_sha256":"\#(HubCATrustTests.caFingerprint.uppercased())"}"#
        try installToken(settings, tie: tie)
        XCTAssertEqual(settings.enrollmentTokenFile, .untied, "no CA is trusted for the Hub yet")

        try settings.saveTrustedHubCA(
            HubCAOffer(pem: HubCATrustTests.caPEM, fingerprint: HubCATrustTests.caFingerprint), forHubURL: hubA)
        XCTAssertEqual(settings.enrollmentTokenFile, .tied)

        let other = #"{"hub_url":"nas01.example.com:8443","ca_fingerprint_sha256":"\#(String(repeating: "0", count: 64))"}"#
        try installToken(settings, tie: other)
        XCTAssertEqual(settings.enrollmentTokenFile, .untied, "the trusted CA is not the one the token was made for")
    }

    /// The address is changed before this Mac ever enrolled, and the person
    /// trusts the new Hub's certificate. The next start used to delete that
    /// certificate as "the previous Hub's", so the menu said "not trusted"
    /// right after Trust this Hub. And the installer's token, made for the
    /// first Hub, must still not go to the trusted new one.
    func testTrustingANewHubBeforeEnrollingKeepsItsCAAndStillHoldsTheTokenBack() throws {
        let (settings, _, cleanup) = try makeSettings()
        defer { cleanup() }
        settings.hubURL = hubA
        try installToken(settings, tie: #"{"hub_url":"wss://nas01.example.com:8443"}"#)
        XCTAssertFalse(try settings.dropCredentialsFromOtherHub())   // first start, for Hub A

        settings.hubURL = hubB
        try settings.saveTrustedHubCA(
            HubCAOffer(pem: HubCATrustTests.caPEM, fingerprint: HubCATrustTests.caFingerprint), forHubURL: hubB)
        _ = try settings.dropCredentialsFromOtherHub()               // the next start, for Hub B
        XCTAssertEqual(settings.hubCAPin, .file(settings.managedHubCAPath), "the CA just trusted for Hub B is still there")
        XCTAssertEqual(settings.enrollmentTokenFile, .untied)
        XCTAssertNil(try settings.buildEnvironment()["LABTETHER_ENROLLMENT_TOKEN_FILE"])
        XCTAssertFalse(settings.isConfigured)
    }

    /// A token typed in the app is written to the same file for the agent. It
    /// gets its tie from the app, so it is still usable after a relaunch.
    func testATypedTokenIsTiedToTheHubItWasTypedFor() throws {
        let (settings, _, cleanup) = try makeSettings()
        defer { cleanup() }
        settings.hubURL = hubA
        settings.enrollmentToken = "typed-token"
        XCTAssertEqual(try settings.buildEnvironment()["LABTETHER_ENROLLMENT_TOKEN_FILE"], settings.enrollmentTokenFilePath)
        XCTAssertNotNil(settings.enrollmentTokenTie)
        XCTAssertEqual(settings.enrollmentTokenFile, .tied)
    }
}
