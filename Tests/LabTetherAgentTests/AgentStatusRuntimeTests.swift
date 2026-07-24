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
        XCTAssertEqual(status.lastError, "auth_failed")
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
