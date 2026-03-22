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
        XCTAssertEqual(client.runtime.snapshot.uptime, "5m")
        XCTAssertEqual(client.metrics.snapshot.current, status.metrics)
        XCTAssertTrue(client.metrics.snapshot.history.samples.isEmpty)
        XCTAssertTrue(client.alerts.snapshot.alerts.isEmpty)
        XCTAssertEqual(client.metadata.snapshot.localBindAddress, "127.0.0.1:8091")
    }

    func testStopClearsKnownAlertIDs() {
        let client = LocalAPIClient()

        client.processAlerts([makeAlert(id: "alert-1", severity: "high", state: "firing")])
        XCTAssertEqual(client.knownAlertIDs, ["alert-1"])

        client.stop()

        XCTAssertTrue(client.knownAlertIDs.isEmpty)
    }

    func testPollAuthFailurePublishesAuthFailedState() {
        let client = LocalAPIClient()

        client.applyPollAuthFailure()

        XCTAssertFalse(client.isReachable)
        XCTAssertEqual(client.hubConnectionState, "auth_failed")
        XCTAssertNil(client.status)
        XCTAssertNil(client.metrics.snapshot.current)
        XCTAssertTrue(client.alerts.snapshot.alerts.isEmpty)
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
