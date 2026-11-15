import XCTest
@testable import LabTetherAgent

/// The contract's real `/agent/status` bodies through the app's own decoder
/// (`LocalAPIClient.decodeStatus`, the one the poller uses).
final class StatusContractTests: XCTestCase {
    /// Risk: a body the agent really sends fails to decode, and the menu stays
    /// on "Status unavailable" while the agent runs.
    func testEveryContractBodyDecodes() throws {
        XCTAssertEqual(try StatusFixtures.namesOnDisk(), StatusFixtures.names.sorted(), "fixture list matches the copy")
        for name in try StatusFixtures.namesOnDisk() {
            let decoded = try LocalAPIClient.decodeStatus(StatusFixtures.data(name))
            XCTAssertEqual(decoded.assetID, "nas01", name)
            XCTAssertEqual(decoded.port, "8091", name)
            XCTAssertEqual(decoded.updateAvailable, false, name)
            XCTAssertNil(decoded.latestVersion, name)
        }
    }

    /// The alerts list and the metrics rows come from these fields.
    func testAlertsAndMetricsReachTheApp() throws {
        let decoded = try LocalAPIClient.decodeStatus(StatusFixtures.data("alerts-with-temperature"))
        XCTAssertEqual(decoded.alerts.map(\.id), ["alr-disk-nas01", "alr-cpu-nas01"])
        XCTAssertEqual(decoded.alerts.map(\.state), ["firing", "resolved"])
        XCTAssertEqual(decoded.alerts.first?.title, "Disk usage above 90%")
        XCTAssertEqual(decoded.metrics.cpuPercent, 12.5)
        XCTAssertEqual(decoded.metrics.diskPercent, 63.2)
        XCTAssertEqual(decoded.metrics.netRXBytesPerSec, 18432.5)
        XCTAssertEqual(decoded.metrics.tempCelsius, 47.5)

        let minimal = try LocalAPIClient.decodeStatus(StatusFixtures.data("minimal-optional-fields-absent"))
        XCTAssertNil(minimal.uptime)
        XCTAssertNil(minimal.groupID)
        XCTAssertNil(minimal.metrics.tempCelsius)
        XCTAssertTrue(minimal.alerts.isEmpty)
    }

    /// Risk: a newer agent adds a field and every older app stops showing
    /// status.
    func testAnUnknownExtraFieldStillDecodes() throws {
        let body = try StatusFixtures.variant("alerts-with-temperature") { body in
            body["hub_region"] = "eu-1"
            body["capabilities"] = ["files": true]
            var metrics = body["metrics"] as? [String: Any] ?? [:]
            metrics["gpu_percent"] = 7.5
            body["metrics"] = metrics
            var alerts = body["alerts"] as? [[String: Any]] ?? []
            alerts[0]["runbook_url"] = "https://hub.example.com/runbooks/disk"
            body["alerts"] = alerts
        }
        let decoded = try LocalAPIClient.decodeStatus(body)
        XCTAssertEqual(decoded.connectionState, "connected")
        XCTAssertEqual(decoded.alerts.count, 2)
    }

    /// Risk: the contract lists a code the app has no words for, so people
    /// see only the generic line for a state that needs them. Run after each
    /// contract update.
    func testTheAppKnowsEveryContractCode() throws {
        let codes = try StatusFixtures.codes()
        let byState = try XCTUnwrap(codes["last_error_by_state"] as? [String: [String]])
        for code in Set(byState.values.joined()) where !code.isEmpty {
            XCTAssertNotNil(AgentLastError(code: code), "last_error \(code)")
        }
        let reasons = try XCTUnwrap(codes["last_error_reasons"] as? [String])
        for reason in reasons {
            XCTAssertNotNil(HubConnectReason(code: reason), "last_error_reason \(reason)")
        }
        let states = try XCTUnwrap(codes["connection_states"] as? [String])
        XCTAssertEqual(Set(states), ["connected", "connecting", "auth_failed", "disconnected"],
                       "AgentHeroPresentation and AgentStatus.reconcileRuntime handle these four")
    }
}
