import XCTest
@testable import LabTetherAgent

/// A CA file chosen in Settings becomes the agent's only root
/// (LABTETHER_TLS_CA_ONLY). The risk: a Mac that already has such a file
/// saved, and whose Hub's certificate that file does not sign, would go
/// offline with the update. And a wrong file chosen later would do the same.
@MainActor
final class ChosenHubCATests: XCTestCase {
    private let hubA = "wss://nas01.example.com:8443/ws/agent"
    private let hubB = "wss://nas02.example.com:8443/ws/agent"

    private func makeSettings() throws -> (AgentSettings, String, () -> Void) {
        let suite = "LabTetherAgentTests.\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lt-chosen-ca-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let caPath = folder.appendingPathComponent("hub-ca.pem").path
        try Data(HubCATrustTests.caPEM.utf8).write(to: URL(fileURLWithPath: caPath))
        let settings = AgentSettings(testSettingsStore: store, appSupportDirectory: folder.appendingPathComponent("state"))
        settings.hubURL = hubA
        return (settings, caPath, {
            store.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        })
    }

    func testASavedCAFileIsUsedAsBeforeUntilItVerifiesTheHubAlone() async throws {
        let (settings, caPath, cleanup) = try makeSettings()
        defer { cleanup() }
        settings.tlsCAFile = caPath   // as an earlier version saved it
        XCTAssertEqual(settings.hubCAPin, .alongside(caPath))
        XCTAssertTrue(settings.chosenCANeedsCheck)
        var environment = try settings.buildEnvironment()
        XCTAssertEqual(environment["LABTETHER_TLS_CA_FILE"], caPath)
        XCTAssertNil(environment["LABTETHER_TLS_CA_ONLY"], "the update alone changes nothing for this Mac")

        // The Hub does not answer the check at start: as before, one line, again next time.
        let noAnswer = await settings.checkSavedChosenCA(check: { _, _ in .unreachable })
        XCTAssertEqual(noAnswer, AgentSettings.chosenCAKeptAsBeforeNoAnswer)
        XCTAssertNil(try settings.buildEnvironment()["LABTETHER_TLS_CA_ONLY"])
        XCTAssertTrue(settings.chosenCANeedsCheck)

        // The file is not this Hub's CA (say the Hub has a public certificate): as before, never offline.
        let mismatch = await settings.checkSavedChosenCA(check: { _, _ in .mismatch })
        XCTAssertEqual(mismatch, AgentSettings.chosenCAKeptAsBeforeMismatch)
        XCTAssertNil(try settings.buildEnvironment()["LABTETHER_TLS_CA_ONLY"])
        XCTAssertTrue(settings.chosenCANeedsCheck)

        // The file alone verifies the Hub: from here on it is the only root.
        let verified = await settings.checkSavedChosenCA(
            check: { _, _ in .verified(fingerprint: HubCATrustTests.caFingerprint) })
        XCTAssertNil(verified)
        XCTAssertEqual(settings.hubCAPin, .file(caPath))
        XCTAssertFalse(settings.chosenCANeedsCheck)
        environment = try settings.buildEnvironment()
        XCTAssertEqual(environment["LABTETHER_TLS_CA_FILE"], caPath)
        XCTAssertEqual(environment["LABTETHER_TLS_CA_ONLY"], "true")

        // That was shown for this Hub, not for another address.
        settings.hubURL = hubB
        XCTAssertEqual(settings.hubCAPin, .alongside(caPath))
        XCTAssertTrue(settings.chosenCANeedsCheck)
    }

    func testAChosenCAFileIsSavedOnlyWhenItVerifiesTheHubAlone() async throws {
        let (settings, caPath, cleanup) = try makeSettings()
        defer { cleanup() }

        let refused = await settings.chooseCAFile(caPath, check: { _, _ in .mismatch })
        XCTAssertEqual(refused, "This CA certificate does not match this Hub's certificate.")
        XCTAssertEqual(settings.tlsCAFile, "", "the previous setting stays")

        let noAnswer = await settings.chooseCAFile(caPath, check: { _, _ in .unreachable })
        XCTAssertEqual(noAnswer, AgentSettings.chosenCAUnreachableMessage)
        XCTAssertEqual(settings.tlsCAFile, "")

        let saved = await settings.chooseCAFile(
            " \(caPath) ", check: { _, _ in .verified(fingerprint: HubCATrustTests.caFingerprint) })
        XCTAssertNil(saved)
        XCTAssertEqual(settings.tlsCAFile, caPath)
        XCTAssertEqual(settings.hubCAPin, .file(caPath))

        // Another file that does not match is refused; the good one stays.
        let otherPath = caPath + ".other"
        try Data(HubCATrustTests.caPEM.utf8).write(to: URL(fileURLWithPath: otherPath))
        let second = await settings.chooseCAFile(otherPath, check: { _, _ in .mismatch })
        XCTAssertEqual(second, AgentSettings.chosenCAMismatchMessage)
        XCTAssertEqual(settings.tlsCAFile, caPath)
        XCTAssertEqual(settings.hubCAPin, .file(caPath))

        let missing = await settings.chooseCAFile(caPath + ".gone", check: { _, _ in .unreachable })
        XCTAssertEqual(missing, AgentSettings.chosenCANotFoundMessage)
        XCTAssertEqual(settings.tlsCAFile, caPath)

        // Clearing the field is always allowed.
        let cleared = await settings.chooseCAFile("", check: { _, _ in .mismatch })
        XCTAssertNil(cleared)
        XCTAssertEqual(settings.tlsCAFile, "")
        XCTAssertEqual(settings.hubCAPin, .none)
    }
}
