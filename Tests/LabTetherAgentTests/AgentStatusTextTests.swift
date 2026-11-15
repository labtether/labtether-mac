import XCTest
@testable import LabTetherAgent

/// The status word and the line under it come from the agent's `/agent/status`.
/// Risks: the agent's internal `last_error` codes (`enrollment_pending`,
/// `auth_failed`, ...) reached people as text, and a 401 from the agent's own
/// local endpoint was shown as the Hub refusing the device.
///
/// Bodies are the protocol contract's real `/agent/status` fixtures
/// (`StatusFixtures`), decoded by the app's own decoder. A case no fixture
/// covers uses a fixture with one field changed.
@MainActor
final class AgentStatusTextTests: XCTestCase {
    private let hubURL = "wss://hub.example.com:8443/ws/agent"
    private let notSaved = "This Mac could not save the agent token. Logs show why."

    /// What the menu shows for one poll: decoded, published and reconciled
    /// by the same code the app runs.
    private func screen(_ body: Data) throws -> (AgentHeroPresentation, AgentStatus) {
        let client = LocalAPIClient()
        client.applySuccessfulPollResult(try LocalAPIClient.decodeStatus(body))
        let status = AgentStatus()
        status.handleEvent(.connected(url: hubURL))
        status.reconcileRuntime(client.runtime.snapshot, processIsRunning: true)
        return (hero(status: status, runtime: client.runtime.snapshot), status)
    }

    private func hero(status: AgentStatus, runtime: LocalAPIRuntimeSnapshot) -> AgentHeroPresentation {
        AgentHeroPresentation.resolve(
            processIsRunning: true,
            processIsStarting: false,
            statusState: status.state,
            statusLastError: status.lastError,
            statusUptime: status.uptime,
            apiUptime: runtime.uptime,
            apiLastError: runtime.lastError,
            hubConnectionState: runtime.hubConnectionState,
            isReachable: runtime.isReachable,
            apiLastErrorReason: runtime.lastErrorReason,
            hubHost: AgentHeroPresentation.hubHost(from: status.hubURL),
            enrollmentError: runtime.enrollmentError,
            localStatusRefused: runtime.localStatusRefused
        )
    }

    /// A snake_case word such as `enrollment_pending` is a code, not text.
    private func assertNoCode(_ text: String, _ message: String, line: UInt = #line) {
        XCTAssertNil(text.range(of: #"[a-z]+_[a-z_]+"#, options: .regularExpression), "\(message): \(text)", line: line)
    }

    private struct Shown {
        let body: String
        let connected: Bool
        let state: String
        let label: String
        let line: String
    }

    private func assertScreen(_ cases: [Shown], bodies: (Shown) throws -> Data, line: UInt = #line) throws {
        for item in cases {
            let data = try bodies(item)
            let decoded = try LocalAPIClient.decodeStatus(data)
            let (hero, status) = try screen(data)
            XCTAssertEqual(decoded.connected, item.connected, item.body, line: line)
            XCTAssertEqual(decoded.connectionState, item.state, item.body, line: line)
            XCTAssertEqual(hero.label, item.label, item.body, line: line)
            XCTAssertEqual(hero.subtitle, item.line, item.body, line: line)
            assertNoCode(hero.subtitle, item.body, line: line)
            assertNoCode(status.lastError, "\(item.body) status.lastError", line: line)
        }
    }

    /// Risk: a real agent state shows the wrong word, or a code as text.
    func testEachContractStateShowsItsWords() throws {
        let tokenRefused = "The Hub refused the agent token. Enter a new token in Settings › Connection."
        let cases = [
            Shown(body: "connected", connected: true, state: "connected",
                  label: "Connected", line: "hub.example.com · up 2h14m33s"),
            Shown(body: "alerts-with-temperature", connected: true, state: "connected",
                  label: "Connected", line: "hub.example.com · up 2h14m33s"),
            Shown(body: "connected-token-persistence-failed", connected: true, state: "connected",
                  label: "Connected", line: "hub.example.com · \(notSaved)"),
            Shown(body: "connecting-transient-host-unreachable", connected: false, state: "connecting",
                  label: "Reconnecting", line: "Can't reach the Hub"),
            Shown(body: "enrollment-pending", connected: false, state: "connecting",
                  label: "Waiting for approval", line: "Approve this Mac in Devices on the Hub"),
            Shown(body: "auth-failed-token-rejected", connected: false, state: "auth_failed",
                  label: "Token refused", line: tokenRefused),
            // The Hub's own words win over the app's line for a refused enrollment token.
            Shown(body: "auth-failed-enrollment-token-rejected", connected: false, state: "auth_failed",
                  label: "Enrollment refused", line: "This enrollment token expired. Make a new one in Devices, Add device."),
            Shown(body: "enrollment-refused-hub-words", connected: false, state: "disconnected",
                  label: "Enrollment refused", line: "An admin rejected this device in LabTether."),
            Shown(body: "disconnected-no-transport", connected: false, state: "disconnected",
                  label: "Disconnected", line: "hub.example.com"),
            Shown(body: "minimal-optional-fields-absent", connected: false, state: "disconnected",
                  label: "Disconnected", line: "hub.example.com"),
        ]
        XCTAssertEqual(Set(cases.map(\.body)), Set(StatusFixtures.names), "every fixture has a screen check")
        try assertScreen(cases) { try StatusFixtures.data($0.body) }
    }

    /// Code pairs the contract allows that no fixture holds: each fixture
    /// below gets one field changed.
    func testCodePairsWithoutAFixtureReadAsWords() throws {
        let edits: [String: (String, (inout [String: Any]) -> Void)] = [
            "transient, no reason": ("connecting-transient-host-unreachable", { $0["last_error_reason"] = nil }),
            "connecting, token not saved": ("enrollment-pending", { $0["last_error"] = "agent_token_persistence_failed" }),
            "connected, two codes": ("connected", {
                $0["last_error"] = "agent_token_persistence_failed,consumed_enrollment_token_cleanup_failed"
            }),
            "connected, used token kept": ("connected", { $0["last_error"] = "consumed_enrollment_token_cleanup_failed" }),
            // An agent before 2.0 sends no Hub words.
            "enrollment token refused, no Hub words": ("auth-failed-enrollment-token-rejected", { $0["enrollment_error"] = nil }),
        ]
        let cases = [
            Shown(body: "transient, no reason", connected: false, state: "connecting",
                  label: "Reconnecting", line: "hub.example.com"),
            Shown(body: "connecting, token not saved", connected: false, state: "connecting",
                  label: "Reconnecting", line: notSaved),
            Shown(body: "connected, two codes", connected: true, state: "connected",
                  label: "Connected", line: "hub.example.com · \(notSaved)"),
            Shown(body: "connected, used token kept", connected: true, state: "connected",
                  label: "Connected", line: "hub.example.com · up 2h14m33s"),
            Shown(body: "enrollment token refused, no Hub words", connected: false, state: "auth_failed",
                  label: "Token refused",
                  line: "The Hub refused this enrollment token. Make a new one in the console under Add device."),
        ]
        try assertScreen(cases) { item in
            let (base, edit) = try XCTUnwrap(edits[item.body])
            return try StatusFixtures.variant(base, edit)
        }
    }

    /// A code a later agent adds is never shown as it is: the generic line stays.
    func testUnknownCodesShowTheGenericLine() throws {
        let edits: [String: (String, (inout [String: Any]) -> Void)] = [
            "unknown last_error, connecting": ("connecting-transient-host-unreachable", {
                $0["last_error"] = "hub_moved_elsewhere"
                $0["last_error_reason"] = nil
            }),
            "unknown last_error_reason": ("connecting-transient-host-unreachable", { $0["last_error_reason"] = "dns_poisoned" }),
            "unknown last_error, auth_failed": ("auth-failed-token-rejected", {
                $0["last_error"] = "hub_key_rotated"
                $0["last_error_reason"] = nil
            }),
            "unknown last_error, connected": ("connected", { $0["last_error"] = "hub_moved_elsewhere" }),
        ]
        let cases = [
            Shown(body: "unknown last_error, connecting", connected: false, state: "connecting",
                  label: "Reconnecting", line: "hub.example.com"),
            Shown(body: "unknown last_error_reason", connected: false, state: "connecting",
                  label: "Reconnecting", line: "hub.example.com"),
            Shown(body: "unknown last_error, auth_failed", connected: false, state: "auth_failed",
                  label: "Token refused", line: "The Hub refused the agent token"),
            Shown(body: "unknown last_error, connected", connected: true, state: "connected",
                  label: "Connected", line: "hub.example.com · up 2h14m33s"),
        ]
        try assertScreen(cases) { item in
            let (base, edit) = try XCTUnwrap(edits[item.body])
            return try StatusFixtures.variant(base, edit)
        }
    }

    /// Waiting for approval is a normal step, not a fault.
    func testWaitingForApprovalIsNotAFault() throws {
        let (hero, _) = try screen(StatusFixtures.data("enrollment-pending"))
        XCTAssertNotEqual(hero.tone, .bad)
        XCTAssertNotEqual(hero.tone, .warn)
    }

    /// The agent's local endpoint refusing this app's token says nothing about
    /// the Hub. The menu must not say the Hub refused the device.
    func testALocal401IsNotTheHubRefusingTheDevice() {
        let client = LocalAPIClient()
        let status = AgentStatus()
        status.handleEvent(.connected(url: hubURL))

        client.applyPollAuthFailure()
        status.reconcileRuntime(client.runtime.snapshot, processIsRunning: true)

        XCTAssertNotEqual(client.hubConnectionState, "auth_failed")
        XCTAssertEqual(status.state, .connected, "the Hub state from the agent's log stays")
        XCTAssertEqual(status.lastError, "")
        let shown = hero(status: status, runtime: client.runtime.snapshot)
        XCTAssertEqual(shown.label, "Status unavailable")
        XCTAssertEqual(shown.subtitle, "The agent refused this app's local token")
        let icon = MenuBarIconResolver.resolve(
            statusState: status.state,
            hubConnectionState: client.hubConnectionState,
            isReachable: client.isReachable,
            metrics: nil,
            hasFiringAlerts: false
        )
        XCTAssertNotEqual(icon, .error, "the icon must not say token refused")
    }
}
