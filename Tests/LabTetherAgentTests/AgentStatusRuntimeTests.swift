import XCTest
@testable import LabTetherAgent

@MainActor
final class AgentStatusRuntimeTests: XCTestCase {
    func testLogParserRecognizesConsumedEnrollmentToken() {
        XCTAssertEqual(
            LogParser().parse("2026/07/24 14:03:05 agent: removed consumed enrollment token file"),
            .enrollmentTokenConsumed
        )
        XCTAssertEqual(
            LogParser().parse("2026/07/24 14:03:05 agent: loaded token from /private/agent-token"),
            .tokenLoaded(path: "/private/agent-token")
        )
    }

    func testLogParserRecognizesRetryingAuthenticationFailure() {
        let event = LogParser().parse(
            "2026/07/24 11:34:59 agentws: auth failure (1/3), retrying in 1s: websocket: bad handshake"
        )

        XCTAssertEqual(
            event,
            .authenticationFailed(
                error: "auth failure (1/3), retrying in 1s: websocket: bad handshake"
            )
        )
    }

    func testLogParserRecognizesTerminalAuthenticationFailure() {
        let event = LogParser().parse(
            "2026/07/24 11:35:02 agentws: AUTH FAILURE (3 consecutive) — credentials rejected by hub, backing off to 5m0s: websocket: bad handshake"
        )

        XCTAssertEqual(
            event,
            .authenticationFailed(
                error: "AUTH FAILURE (3 consecutive) — credentials rejected by hub, backing off to 5m0s: websocket: bad handshake"
            )
        )
    }

    /// Since labtether-agent #127 the agent prints this line when the Hub
    /// closes a connection straight after accepting it (ws_reconnect.go,
    /// waitAfterSession). Risk: the app kept saying "Connected" while the
    /// agent was waiting to reconnect.
    func testHubClosingTheConnectionMeansReconnecting() {
        let status = AgentStatus()
        status.setPanelVisible(true)
        status.handleEvent(.connected(url: "wss://hub.example.com:8443/ws/agent"))

        status.handleEvent(LogParser().parse(
            "2026/11/16 10:00:00 agentws: the connection to the Hub closed after 112ms; retrying in 1.187s"
        ))

        XCTAssertEqual(status.state, .reconnecting)
        XCTAssertEqual(status.lastEvent, "Reconnecting in 1.187s")
        XCTAssertEqual(status.lastError, "The Hub closed the connection after 112ms")
    }

    func testAuthenticationFailureEventReplacesStartingState() {
        let status = AgentStatus()
        status.setPanelVisible(true)
        status.markStarting(pid: 123)

        status.handleEvent(.authenticationFailed(error: "credentials rejected"))

        XCTAssertEqual(status.state, .authFailed)
        XCTAssertEqual(status.lastError, "credentials rejected")
        XCTAssertEqual(status.lastEvent, "Hub authentication failed")
    }

    func testRuntimeAuthenticationFailureReplacesStartingState() {
        let status = AgentStatus()
        status.markStarting(pid: 123)

        status.reconcileRuntime(
            LocalAPIRuntimeSnapshot(
                isReachable: true,
                hubConnectionState: "auth_failed",
                assetID: "untrusted-pre-enrollment-id",
                uptime: "8s",
                lastError: "auth_failed"
            ),
            processIsRunning: true
        )

        XCTAssertEqual(status.state, .authFailed)
        XCTAssertEqual(status.lastError, "The Hub refused the agent token. Enter a new token in Settings › Connection.")
        XCTAssertEqual(status.assetID, "")
    }

    func testRuntimeConnectedStateRecoversAndClearsAuthenticationError() {
        let status = AgentStatus()
        status.handleEvent(.authenticationFailed(error: "credentials rejected"))

        status.reconcileRuntime(
            LocalAPIRuntimeSnapshot(
                isReachable: true,
                hubConnectionState: "connected",
                assetID: "canonical-mac-asset",
                uptime: "12s",
                lastError: nil
            ),
            processIsRunning: true
        )

        XCTAssertEqual(status.state, .connected)
        XCTAssertEqual(status.lastError, "")
        XCTAssertEqual(status.assetID, "canonical-mac-asset")
    }

    func testUnreachableDisconnectedRuntimeDoesNotEraseRicherState() {
        let status = AgentStatus()
        status.handleEvent(.authenticationFailed(error: "credentials rejected"))

        status.reconcileRuntime(
            LocalAPIRuntimeSnapshot(),
            processIsRunning: true
        )

        XCTAssertEqual(status.state, .authFailed)
        XCTAssertEqual(status.lastError, "credentials rejected")
    }

    func testPrepareForLaunchReplacesHubAndClearsStaleAssetIdentity() {
        let status = AgentStatus()
        status.handleEvent(.connected(url: "wss://old.example/ws/agent"))
        status.handleEvent(.enrolled(assetID: "old-hub-asset"))

        status.prepareForLaunch(hubURL: "ws://127.0.0.1:23000/ws/agent")

        XCTAssertEqual(status.state, .starting)
        XCTAssertEqual(status.hubURL, "ws://127.0.0.1:23000/ws/agent")
        XCTAssertEqual(status.assetID, "")
        XCTAssertEqual(status.lastError, "")
    }
}
