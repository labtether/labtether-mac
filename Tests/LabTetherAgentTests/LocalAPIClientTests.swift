import XCTest
@testable import LabTetherAgent

@MainActor
final class LocalAPIClientTests: XCTestCase {
    func testSuccessfulPollPublishesStatusWhileHiddenWithoutAppendingHistory() {
        let client = LocalAPIClient()
        let status = makeStatus(connectionState: "connected", connected: true)

        client.applySuccessfulPollResult(status)

        XCTAssertEqual(client.status, status)
        XCTAssertTrue(client.isReachable)
        XCTAssertEqual(client.hubConnectionState, "connected")
        XCTAssertEqual(client.runtime.snapshot.assetID, "asset-1")
        XCTAssertEqual(client.runtime.snapshot.uptime, "5m")
        XCTAssertEqual(client.metrics.snapshot.current, status.metrics)
        XCTAssertTrue(client.metrics.snapshot.history.samples.isEmpty)
        XCTAssertTrue(client.alerts.snapshot.alerts.isEmpty)
        XCTAssertEqual(client.metadata.snapshot.localBindAddress, "127.0.0.1:8091")
    }

    /// After Start the agent needs a moment to open its local API. A refused
    /// first poll must be asked again within a second, menu open or not:
    /// waiting the hidden 30 s left "Status unavailable" up after every
    /// Start and Restart.
    func testARefusedFirstPollAfterStartIsAskedAgainWithinASecond() {
        let client = LocalAPIClient()
        client.beginStartup()
        client.applyPollFailure()
        XCTAssertEqual(client.nextPollInterval, 1)
        client.applyPollFailure()
        XCTAssertEqual(client.nextPollInterval, 1, "refusals while the agent starts do not back off")

        client.applySuccessfulPollResult(makeStatus(connectionState: "connected", connected: true))
        XCTAssertEqual(client.nextPollInterval, 30, "answered and nothing on screen: the slow rate")
        client.setMenuVisible(true)
        XCTAssertEqual(client.nextPollInterval, 5)
        client.applyPollFailure()
        client.applyPollFailure()
        XCTAssertEqual(client.nextPollInterval, 10, "later failures back off as before")
    }

    /// Stopping the agent does not close the menu. The client must still
    /// know the menu is open, or it polls at the hidden rate under it.
    func testStopKeepsWhatIsOnScreen() {
        let client = LocalAPIClient()
        client.setMenuVisible(true)
        client.stop()
        XCTAssertTrue(client.isMenuVisible)
    }

    func testStopClearsKnownAlertIDs() {
        let client = LocalAPIClient()

        client.processAlerts([makeAlert(id: "alert-1", severity: "high", state: "firing")])
        XCTAssertEqual(client.knownAlertIDs, ["alert-1"])

        client.stop()

        XCTAssertTrue(client.knownAlertIDs.isEmpty)
    }

    func testPollAuthFailurePublishesLocalRefusal() {
        let client = LocalAPIClient()

        client.applyPollAuthFailure()

        XCTAssertFalse(client.isReachable)
        XCTAssertTrue(client.runtime.snapshot.localStatusRefused)
        XCTAssertNil(client.status)
        XCTAssertNil(client.metrics.snapshot.current)
        XCTAssertTrue(client.alerts.snapshot.alerts.isEmpty)
    }

    /// The child gets the trimmed port; the poller must ask that same port.
    /// Risk: a stray space in Settings left the menu on "Status unavailable"
    /// while the agent ran fine.
    func testPollerUsesThePortTheChildIsGiven() throws {
        let suite = "LabTetherAgentTests.\(UUID().uuidString)"
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lt-port-\(UUID().uuidString)")
        defer {
            store.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        let settings = AgentSettings(testSettingsStore: store, appSupportDirectory: folder)
        settings.hubURL = "wss://hub.example.com:8443/ws/agent"
        settings.agentPort = " 8092 "
        XCTAssertFalse(settings.validationErrors().contains { $0.contains("port") }, "a stray space passes validation")
        let childPort = try XCTUnwrap(settings.buildEnvironment()["AGENT_PORT"])

        let client = LocalAPIClient()
        client.start(settings: settings)
        defer { client.stop() }

        XCTAssertEqual(childPort, "8092")
        XCTAssertEqual(client.statusURL?.absoluteString, "http://127.0.0.1:\(childPort)/agent/status")
    }

    func testSuccessfulPollPublishesAgentVersion() {
        let client = LocalAPIClient()
        let status = makeStatus(connectionState: "connected", connected: true, agentVersion: "2.3.4")

        client.applySuccessfulPollResult(status)

        XCTAssertEqual(client.metadata.snapshot.agentVersion, "2.3.4")
    }

    func testPollFailureClearsAgentVersion() {
        let client = LocalAPIClient()
        let status = makeStatus(connectionState: "connected", connected: true, agentVersion: "2.3.4")

        client.applySuccessfulPollResult(status)
        XCTAssertEqual(client.metadata.snapshot.agentVersion, "2.3.4")

        client.applyPollFailure()

        XCTAssertNil(client.metadata.snapshot.agentVersion)
    }

    func testPollFailureClearsStaleStatusSnapshot() {
        let client = LocalAPIClient()
        let status = makeStatus(
            connectionState: "connected",
            connected: true,
            alerts: [makeAlert(id: "alert-1", severity: "high", state: "firing")],
            updateAvailable: true
        )

        client.applySuccessfulPollResult(status)
        client.applyPollFailure()

        XCTAssertNil(client.status)
        XCTAssertFalse(client.isReachable)
        XCTAssertEqual(client.hubConnectionState, "disconnected")
        XCTAssertNil(client.metrics.snapshot.current)
        XCTAssertTrue(client.alerts.snapshot.alerts.isEmpty)
        XCTAssertFalse(client.metadata.snapshot.updateAvailable)
    }

    func testStopClearsMetricsHistory() {
        let client = LocalAPIClient()
        let status = makeStatus(connectionState: "connected", connected: true)

        client.applyStatusSnapshot(status, appendHistory: true)
        XCTAssertEqual(client.metrics.snapshot.history.samples.count, 1)

        client.stop()

        XCTAssertTrue(client.metrics.snapshot.history.samples.isEmpty)
        XCTAssertNil(client.metrics.snapshot.current)
    }

    func testMetricsHistoryRetainsMostRecentFixedCapacityWindow() {
        var history = MetricsHistory()

        for index in 0..<75 {
            history.append(
                MetricsSnapshot(
                    cpuPercent: Double(index),
                    memoryPercent: Double(index),
                    diskPercent: Double(index),
                    netRXBytesPerSec: 0,
                    netTXBytesPerSec: 0,
                    tempCelsius: nil,
                    collectedAt: Date(timeIntervalSince1970: TimeInterval(index))
                )
            )
        }

        XCTAssertEqual(history.samples.count, 60)
        XCTAssertEqual(history.samples.first?.cpuPercent, 15)
        XCTAssertEqual(history.samples.last?.cpuPercent, 74)
    }

    private func makeStatus(
        connectionState: String,
        connected: Bool,
        alerts: [AlertSnapshot] = [],
        updateAvailable: Bool = false,
        agentVersion: String? = "1.0.0"
    ) -> AgentStatusResponse {
        AgentStatusResponse(
            agentName: "mac-agent",
            assetID: "asset-1",
            groupID: nil,
            port: "8091",
            deviceFingerprint: nil,
            deviceKeyAlgorithm: nil,
            connected: connected,
            connectionState: connectionState,
            disconnectedAt: nil,
            lastError: nil,
            lastErrorReason: nil,
            uptime: "5m",
            startedAt: nil,
            localBindAddress: "127.0.0.1:8091",
            localAuthEnabled: true,
            allowInsecureTransport: false,
            metrics: MetricsSnapshot(
                cpuPercent: 12,
                memoryPercent: 34,
                diskPercent: 56,
                netRXBytesPerSec: 0,
                netTXBytesPerSec: 0,
                tempCelsius: nil,
                collectedAt: Date(timeIntervalSince1970: 1_741_420_800)
            ),
            alerts: alerts,
            agentVersion: agentVersion,
            updateAvailable: updateAvailable,
            latestVersion: nil
        )
    }

    private func makeAlert(id: String, severity: String, state: String) -> AlertSnapshot {
        AlertSnapshot(
            id: id,
            severity: severity,
            title: "CPU high",
            summary: "CPU exceeded threshold",
            state: state,
            timestamp: nil
        )
    }
}
