import XCTest
@testable import LabTetherAgent

/// Risk: after the Hub URL changes, the old Hub's bearer token is sent to the
/// new address, which can then replay it to the old Hub as this device.
final class AgentCredentialScopeTests: XCTestCase {
    func testChangingHubDropsOnlyTheOldHubsCredentials() throws {
        let suiteName = "LabTetherAgentTests.\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("labtether-credential-scope-\(UUID().uuidString)")
        defer {
            store.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: support)
        }
        let settings = AgentSettings(testSettingsStore: store, appSupportDirectory: support)
        settings.hubURL = "wss://nas01.example.com:8443/ws/agent"
        settings.apiToken = "old-hub-token"
        try settings.persistRuntimeSecret("old-hub-token", to: settings.tokenFilePath,
                                          issueKey: "test.token", label: "Test token")
        let caPath = support.appendingPathComponent("ca.crt").path
        XCTAssertTrue(FileManager.default.createFile(atPath: caPath, contents: Data("old CA".utf8)))

        // Existing installs have no binding yet: keep and bind to this Hub.
        XCTAssertFalse(try settings.dropCredentialsFromOtherHub())
        // The same Hub written another way is still the same Hub.
        settings.hubURL = "https://NAS01.example.com:8443"
        XCTAssertFalse(try settings.dropCredentialsFromOtherHub())
        XCTAssertTrue(settings.hasPersistedAgentToken)
        XCTAssertEqual(settings.apiToken, "old-hub-token")

        settings.hubURL = "wss://nas02.example.com:8443/ws/agent"
        XCTAssertTrue(try settings.dropCredentialsFromOtherHub())
        XCTAssertFalse(settings.hasPersistedAgentToken)
        XCTAssertFalse(FileManager.default.fileExists(atPath: caPath))
        XCTAssertEqual(settings.apiToken, "")
        XCTAssertFalse(settings.isConfigured)

        // A token typed after the change is meant for the Hub launched next.
        settings.hubURL = "wss://192.0.2.10:8443/ws/agent"
        settings.enrollmentToken = "new-hub-enrollment"
        XCTAssertFalse(try settings.dropCredentialsFromOtherHub())
        XCTAssertEqual(settings.enrollmentToken, "new-hub-enrollment")
    }
}
