import XCTest
@testable import LabTetherAgent

/// Choices of the Mac App Store edition that the default test run reaches
/// by passing the edition in. The Store binary itself is checked by
/// `scripts/validate-app.sh --edition store` and the installed-app QA.
@MainActor
final class StoreEditionTests: XCTestCase {
    private func makeSettings() throws -> (AgentSettings, () -> Void) {
        let suite = "LabTetherAgentTests.\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lt-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let settings = AgentSettings(testSettingsStore: store, appSupportDirectory: folder)
        settings.hubURL = "wss://nas01.example.com:8443/ws/agent"
        return (settings, {
            store.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        })
    }

    // Fault: a setting the Store edition hides still reaches its agent, so a
    // later monitoring agent that learns Docker or a LAN scan would follow a
    // value nobody can see or change. The Developer ID edition must still
    // pass every one of them, and nothing the monitoring agent reads may go.
    func testStoreAgentGetsNoSettingTheStoreHides() throws {
        let (settings, cleanup) = try makeSettings()
        defer { cleanup() }
        settings.dockerEnabled = "true"
        settings.filesRootMode = "full"
        settings.servicesDiscoveryLANScanEnabled = true
        settings.webrtcTurnURL = "turn:turn.example.com:3478"

        let direct = try AgentEnvironmentBuilder.buildEnvironment(from: settings, edition: .developerID)
        let store = try AgentEnvironmentBuilder.buildEnvironment(from: settings, edition: .appStore)

        let hidden = direct.keys.filter { key in
            ["LABTETHER_DOCKER_", "LABTETHER_SERVICES_DISCOVERY_", "LABTETHER_WEBRTC_"].contains { key.hasPrefix($0) }
                || ["LABTETHER_FILES_ROOT_MODE", "LABTETHER_CAPTURE_FPS", "LABTETHER_LOG_STREAM_ENABLED"].contains(key)
        }
        XCTAssertEqual(direct["LABTETHER_DOCKER_ENABLED"], "true", "the Developer ID edition still passes its settings")
        XCTAssertGreaterThanOrEqual(hidden.count, 20)
        for key in hidden { XCTAssertNil(store[key], key) }
        XCTAssertEqual(Set(store.keys).union(hidden), Set(direct.keys), "only the hidden settings differ")
        for key in store.keys { XCTAssertEqual(store[key], direct[key], key) }
        for key in ["LABTETHER_WS_URL", "LABTETHER_TOKEN_FILE", "AGENT_PORT", "LABTETHER_LOG_LEVEL",
                    "LABTETHER_ALLOW_REMOTE_OVERRIDES", "LABTETHER_PARENT_PID",
                    "LABTETHER_AGENT_LOCAL_AUTH_TOKEN_FILE", "LABTETHER_DEVICE_KEY_FILE"] {
            XCTAssertNotNil(store[key], key)
        }
    }

    // Fault: a Store and a direct install on one Mac shared Keychain items,
    // so Reset and uninstall in one edition removed the other's tokens.
    func testStoreTokensUseTheirOwnKeychainService() {
        XCTAssertEqual(AppEdition.developerID.keychainService(bundleIdentifier: "com.example.store"), "com.labtether.agent")
        XCTAssertEqual(AppEdition.appStore.keychainService(bundleIdentifier: "com.example.store"), "com.example.store")
    }
}
