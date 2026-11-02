import XCTest
@testable import LabTetherAgent

/// Risk: Open Console, the device link and alert links open the Hub API origin
/// (JSON) instead of the console, or open a console the Hub did not name, or
/// keep an old Hub's console after the Hub URL changes.
final class HubConsoleLocatorTests: XCTestCase {
    func testReadsTheConsoleFromTheHubAPIRoot() {
        // Hub 2.0 answer to GET / on the API port.
        let root = Data("""
        {"console_url":"http://192.0.2.10:3000","healthz_path":"/healthz",\
        "message":"LabTether hub API is running.","readyz_path":"/readyz",\
        "service":"labtether-hub","version_path":"/version"}
        """.utf8)
        XCTAssertEqual(HubConsoleLocator.consoleURL(fromHubRoot: root)?.absoluteString, "http://192.0.2.10:3000")

        func named(_ value: String, service: String = "labtether-hub") -> URL? {
            let body = try? JSONSerialization.data(withJSONObject: ["service": service, "console_url": value])
            return HubConsoleLocator.consoleURL(fromHubRoot: body ?? Data())
        }
        XCTAssertEqual(named("https://lab.example.com/console?x=1#y")?.absoluteString, "https://lab.example.com/console")
        XCTAssertNil(named("file:///etc/hosts"))
        XCTAssertNil(named("javascript:alert(1)"))
        XCTAssertNil(named("https://user:pass@lab.example.com"))
        XCTAssertNil(named("http://192.0.2.10:3000", service: "something-else"))
        XCTAssertNil(HubConsoleLocator.consoleURL(fromHubRoot: Data("<html></html>".utf8)))
    }

    func testOpenConsoleUsesTheHubNamedConsoleOnlyForThatHub() throws {
        let suiteName = "LabTetherAgentTests.\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let support = FileManager.default.temporaryDirectory
            .appendingPathComponent("labtether-console-\(UUID().uuidString)")
        defer {
            store.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: support)
        }
        let settings = AgentSettings(testSettingsStore: store, appSupportDirectory: support)
        settings.hubURL = "wss://192.0.2.10:8443/ws/agent"
        XCTAssertEqual(settings.consoleURL?.absoluteString, "https://192.0.2.10:8443")

        settings.hubConsoleSource = settings.normalizedHubWebSocketURL()
        settings.hubConsoleURL = URL(string: "http://192.0.2.10:3000")
        XCTAssertEqual(settings.consoleURL?.absoluteString, "http://192.0.2.10:3000")
        XCTAssertEqual(ConsoleURLBuilder.nodeURL(base: try XCTUnwrap(settings.consoleURL), assetID: "nas01")?
            .absoluteString, "http://192.0.2.10:3000/nodes/nas01")

        settings.hubURL = "wss://nas01.example.com:8443/ws/agent"
        XCTAssertEqual(settings.consoleURL?.absoluteString, "https://nas01.example.com:8443")
    }
}
