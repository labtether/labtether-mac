import XCTest
@testable import LabTetherAgent

/// The Store edition's Hub CA file, picked in the file panel (PickedHubCA.swift).
@MainActor
final class PickedHubCATests: XCTestCase {
    private let verifies: AgentSettings.ChosenCACheck = { _, _ in .verified(fingerprint: HubCATrustTests.caFingerprint) }

    /// Settings with a state folder, and a picked file outside it, as the
    /// sandboxed app sees a file in the person's own folders.
    private func makeSettings() throws -> (AgentSettings, URL, () -> Void) {
        let suite = "LabTetherAgentTests.\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lt-picked-ca-\(UUID().uuidString)")
        let documents = folder.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let picked = documents.appendingPathComponent("hub-ca.pem")
        try Data(HubCATrustTests.caPEM.utf8).write(to: picked)
        let settings = AgentSettings(testSettingsStore: store, appSupportDirectory: folder.appendingPathComponent("state"))
        settings.hubURL = "wss://nas01.example.com:8443/ws/agent"
        return (settings, picked, {
            store.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        })
    }

    // Fault: the agent is given the picked file's own path. The sandbox lets
    // only the app read it, so the agent cannot open its CA and stays offline.
    func testTheAgentGetsTheCopyInsideTheStateFolder() async throws {
        let (settings, picked, cleanup) = try makeSettings()
        defer { cleanup() }
        let words = await settings.choosePickedCAFile(picked, check: verifies)
        XCTAssertNil(words)
        XCTAssertEqual(settings.tlsCAFile, settings.pickedCACopyPath)
        XCTAssertTrue(settings.pickedCACopyPath.hasPrefix(settings.appSupportDirectory.path + "/"))
        XCTAssertEqual(settings.pickedCAOriginalPath, picked.path)
        let env = try settings.buildEnvironment()
        XCTAssertEqual(env["LABTETHER_TLS_CA_FILE"], settings.pickedCACopyPath)
        XCTAssertEqual(env["LABTETHER_TLS_CA_ONLY"], "true")
        let staging = settings.appSupportDirectory.appendingPathComponent(AgentSettings.pickedCAStagingName).path
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging), "the file checked under its own name is gone")
    }

    // Fault: the copy hides a change. A CA replaced at the picked place kept
    // the agent on the old copy, so the rule "a verified CA that changed stops
    // the agent until it is checked again" never applied in the Store edition.
    func testAChangedPickedFileStopsTheAgentUntilCheckedAgain() async throws {
        let (settings, picked, cleanup) = try makeSettings()
        defer { cleanup() }
        _ = await settings.choosePickedCAFile(picked, check: verifies)
        try Data(HubCATrustTests.otherCAPEM.utf8).write(to: picked)

        XCTAssertEqual(settings.refreshPickedCACopy(), AgentSettings.pickedCAChangedLine)
        XCTAssertEqual(settings.hubCAPin, .unusable(AgentSettings.chosenCAChangedMessage))
        XCTAssertEqual(settings.chosenCAProblem, .changed)
        XCTAssertThrowsError(try settings.buildEnvironment())
        XCTAssertNil(settings.refreshPickedCACopy(), "nothing more to copy")
    }

    // Fault: a removed CA file left the agent trusting the copy for good.
    func testARemovedPickedFileRemovesTheCopy() async throws {
        let (settings, picked, cleanup) = try makeSettings()
        defer { cleanup() }
        _ = await settings.choosePickedCAFile(picked, check: verifies)
        try FileManager.default.removeItem(at: picked)

        XCTAssertEqual(settings.refreshPickedCACopy(), AgentSettings.pickedCARemovedLine)
        XCTAssertFalse(FileManager.default.fileExists(atPath: settings.pickedCACopyPath))
        XCTAssertEqual(settings.hubCAPin, .unusable(AgentSettings.chosenCAChangedMessage))
    }

    // Fault: a picked file that does not verify the Hub overwrote the copy in
    // use, which took a working Mac offline at its next start.
    func testARefusedPickKeepsTheWorkingCopy() async throws {
        let (settings, picked, cleanup) = try makeSettings()
        defer { cleanup() }
        _ = await settings.choosePickedCAFile(picked, check: verifies)
        let other = picked.deletingLastPathComponent().appendingPathComponent("other-ca.pem")
        try Data(HubCATrustTests.otherCAPEM.utf8).write(to: other)

        let words = await settings.choosePickedCAFile(other, check: { _, _ in .mismatch })
        XCTAssertEqual(words, AgentSettings.chosenCAMismatchMessage)
        XCTAssertEqual(settings.tlsCAFile, settings.pickedCACopyPath)
        XCTAssertEqual(settings.pickedCAOriginalPath, picked.path)
        XCTAssertEqual(FileManager.default.contents(atPath: settings.pickedCACopyPath), Data(HubCATrustTests.caPEM.utf8))
        XCTAssertEqual(settings.hubCAPin, .file(settings.pickedCACopyPath))
    }
}
