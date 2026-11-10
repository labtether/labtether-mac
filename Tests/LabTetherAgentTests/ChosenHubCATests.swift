import XCTest
@testable import LabTetherAgent

/// A CA file chosen in Settings becomes the agent's only root
/// (LABTETHER_TLS_CA_ONLY). The risks: a Mac that already has such a file
/// saved, and whose Hub's certificate that file does not sign, would go
/// offline with the update; and a file that verified the Hub once could later
/// fall back to the system's roots, so a certificate from any public CA on
/// the Hub's name would be accepted again.
@MainActor
final class ChosenHubCATests: XCTestCase {
    private let hubA = "wss://nas01.example.com:8443/ws/agent"
    private let hubB = "wss://nas02.example.com:8443/ws/agent"
    private let verifies: AgentSettings.ChosenCACheck = { _, _ in .verified(fingerprint: HubCATrustTests.caFingerprint) }

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

    private func caOnly(_ settings: AgentSettings) throws -> String? {
        try settings.buildEnvironment()["LABTETHER_TLS_CA_ONLY"]
    }

    func testASavedCAFileIsUsedAsBeforeUntilItVerifiesTheHubAlone() async throws {
        let (settings, caPath, cleanup) = try makeSettings()
        defer { cleanup() }
        settings.tlsCAFile = caPath   // as an earlier version saved it
        XCTAssertEqual(settings.hubCAPin, .alongside(caPath))
        XCTAssertTrue(settings.chosenCANeedsCheck)
        XCTAssertEqual(try settings.buildEnvironment()["LABTETHER_TLS_CA_FILE"], caPath)
        XCTAssertNil(try caOnly(settings), "the update alone changes nothing for this Mac")

        // The Hub is away at start: as before for this start, one line, checked again next time.
        let noAnswer = await settings.checkSavedChosenCA(check: { _, _ in .unreachable })
        XCTAssertEqual(noAnswer, AgentSettings.chosenCAKeptAsBeforeNoAnswer)
        XCTAssertNil(try caOnly(settings))
        XCTAssertTrue(settings.chosenCANeedsCheck)
        XCTAssertNil(settings.chosenCAProblem)

        // The Hub answers and the file does not sign its certificate: the Mac
        // keeps working, and Settings says the file does nothing useful.
        let mismatch = await settings.checkSavedChosenCA(check: { _, _ in .mismatch })
        XCTAssertEqual(mismatch, AgentSettings.chosenCAKeptAsBeforeMismatch)
        XCTAssertNil(try caOnly(settings))
        XCTAssertTrue(settings.chosenCANeedsCheck)
        XCTAssertEqual(settings.chosenCAProblem, .doesNotMatch)
        XCTAssertEqual(settings.chosenCAProblem?.words, "This CA certificate does not match this Hub's certificate.")

        // The file alone verifies the Hub: from here on it is the only root.
        let verified = await settings.checkSavedChosenCA(check: verifies)
        XCTAssertEqual(verified, AgentSettings.chosenCANowOnlyRoot)
        XCTAssertEqual(settings.hubCAPin, .file(caPath))
        XCTAssertFalse(settings.chosenCANeedsCheck)
        XCTAssertNil(settings.chosenCAProblem)
        XCTAssertEqual(try settings.buildEnvironment()["LABTETHER_TLS_CA_FILE"], caPath)
        XCTAssertEqual(try caOnly(settings), "true")
    }

    func testOnceVerifiedAFailedOrMissingCheckNeverAddsTheSystemRootsBack() async throws {
        let (settings, caPath, cleanup) = try makeSettings()
        defer { cleanup() }
        let saved = await settings.chooseCAFile(caPath, check: verifies)
        XCTAssertNil(saved)
        XCTAssertEqual(try caOnly(settings), "true")

        // The Hub is away, or a later check fails: nothing to check, still the only root.
        for verdict in [HubCATrust.OwnCAVerdict.unreachable, .unreadable, .mismatch] {
            let line = await settings.checkSavedChosenCA(check: { _, _ in verdict })
            XCTAssertNil(line)
            XCTAssertEqual(settings.hubCAPin, .file(caPath))
            XCTAssertEqual(try caOnly(settings), "true")
        }

        // The file now holds another certificate: the agent is not started.
        try Data(HubCATrustTests.otherCAPEM.utf8).write(to: URL(fileURLWithPath: caPath))
        XCTAssertEqual(settings.hubCAPin, .unusable(AgentSettings.chosenCAChangedMessage))
        XCTAssertThrowsError(try settings.buildEnvironment()) { error in
            XCTAssertEqual(error.localizedDescription, AgentSettings.chosenCAChangedMessage)
        }
        XCTAssertEqual(settings.chosenCAProblem, .changed)

        // The file is gone: the same.
        try FileManager.default.removeItem(atPath: caPath)
        XCTAssertEqual(settings.hubCAPin, .unusable(AgentSettings.chosenCAChangedMessage))
        XCTAssertThrowsError(try settings.buildEnvironment())
        XCTAssertFalse(settings.validationErrors().isEmpty, "a start stops with words")

        // Put back as it was: the only root again.
        try Data(HubCATrustTests.caPEM.utf8).write(to: URL(fileURLWithPath: caPath))
        XCTAssertEqual(settings.hubCAPin, .file(caPath))
    }

    func testAChangedAddressIsCheckedForItsOwnHub() async throws {
        let (settings, caPath, cleanup) = try makeSettings()
        defer { cleanup() }
        _ = await settings.chooseCAFile(caPath, check: verifies)
        XCTAssertEqual(settings.hubCAPin, .file(caPath))

        // Shown for Hub A says nothing about Hub B: checked again for it.
        settings.hubURL = hubB
        XCTAssertTrue(settings.chosenCANeedsCheck)
        var asked: [String] = []
        let line = await settings.checkSavedChosenCA(check: { url, _ in asked.append(url); return .unreachable })
        XCTAssertEqual(line, AgentSettings.chosenCAKeptAsBeforeNoAnswer)
        XCTAssertEqual(asked, ["wss://nas02.example.com:8443/ws/agent"])
        XCTAssertEqual(settings.hubCAPin, .alongside(caPath))

        _ = await settings.checkSavedChosenCA(check: verifies)
        XCTAssertEqual(settings.hubCAPin, .file(caPath))

        // Hub A's record was kept: back on Hub A it is still the only root.
        settings.hubURL = hubA
        XCTAssertFalse(settings.chosenCANeedsCheck)
        XCTAssertEqual(settings.hubCAPin, .file(caPath))
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

        let saved = await settings.chooseCAFile(" \(caPath) ", check: verifies)
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

        // Clearing the field is always allowed, and forgets what was shown.
        let cleared = await settings.chooseCAFile("", check: { _, _ in .mismatch })
        XCTAssertNil(cleared)
        XCTAssertEqual(settings.tlsCAFile, "")
        XCTAssertEqual(settings.hubCAPin, .none)
        settings.tlsCAFile = caPath
        XCTAssertEqual(settings.hubCAPin, .alongside(caPath))
    }
}
