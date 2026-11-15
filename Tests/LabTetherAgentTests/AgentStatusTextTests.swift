import XCTest
@testable import LabTetherAgent

/// The status word and the line under it come from the agent's `/agent/status`.
/// Risks: the agent's internal `last_error` codes (`enrollment_pending`,
/// `auth_failed`, ...) reached people as text, and a 401 from the agent's own
/// local endpoint was shown as the Hub refusing the device.
///
/// Bodies follow `StatusResponse` in the Go agent's
/// `internal/agentcore/local_status.go`, and the state and code pairs follow
/// `wsTransport.ConnectionState` in `ws_transport.go` (labtether-agent d0b6a7c).
@MainActor
final class AgentStatusTextTests: XCTestCase {
    private let hubURL = "wss://hub.example.com:8443/ws/agent"

    /// A body as the Go agent writes it, with nanosecond times.
    private func goStatusBody(connected: Bool, state: String, lastError: String?, reason: String? = nil) -> Data {
        var fields: [String] = [
            #""agent_name":"nas01","asset_id":"nas01","port":"8091""#,
            #""device_fingerprint":"SHA256:demo","device_key_algorithm":"ed25519""#,
            #""connected":\#(connected),"connection_state":"\#(state)""#,
        ]
        if state != "connected", lastError != "enrollment_pending" {
            fields.append(#""disconnected_at":"2026-11-16T09:58:01.204518337Z""#)
        }
        if let lastError { fields.append(#""last_error":"\#(lastError)""#) }
        if let reason { fields.append(#""last_error_reason":"\#(reason)""#) }
        fields.append(#""uptime":"2m3s","started_at":"2026-11-16T20:57:58.912345678+11:00""#)
        fields.append(
            #""metrics":{"asset_id":"nas01","cpu_percent":3.5,"memory_percent":41.2,"disk_percent":22,"#
                + #""net_rx_bytes":123456,"net_tx_bytes":65432,"net_rx_bytes_per_sec":512,"#
                + #""net_tx_bytes_per_sec":256,"collected_at":"2026-11-16T10:00:00.5Z"}"#
        )
        fields.append(#""alerts":[],"agent_version":"v2.0.1","local_bind_address":"127.0.0.1""#)
        fields.append(#""local_auth_enabled":true,"allow_insecure_transport":false,"update_available":false"#)
        return Data("{\(fields.joined(separator: ","))}".utf8)
    }

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

    func testEveryAgentCodeReadsAsWords() throws {
        let notSaved = "This Mac could not save the agent token. Logs show why."
        let cases: [(connected: Bool, state: String, code: String?, reason: String?, label: String, line: String)] = [
            (false, "connecting", "enrollment_pending", nil, "Waiting for approval", "Approve this Mac in Devices on the Hub"),
            (false, "connecting", "transient", nil, "Reconnecting", "hub.example.com"),
            (false, "connecting", "agent_token_persistence_failed", nil, "Reconnecting", notSaved),
            (false, "auth_failed", "auth_failed", "token_rejected", "Token refused",
             "The Hub refused the agent token. Enter a new token in Settings › Connection."),
            (false, "auth_failed", "enrollment_token_rejected", nil, "Token refused",
             "The Hub refused this enrollment token. Make a new one in the console under Add device."),
            (true, "connected", "agent_token_persistence_failed", nil, "Connected", "hub.example.com · \(notSaved)"),
            (true, "connected", "agent_token_persistence_failed,consumed_enrollment_token_cleanup_failed", nil,
             "Connected", "hub.example.com · \(notSaved)"),
            (true, "connected", "consumed_enrollment_token_cleanup_failed", nil, "Connected", "hub.example.com · up 2m3s"),
            // A code a later agent adds is never shown as it is.
            (false, "connecting", "hub_moved_elsewhere", nil, "Reconnecting", "hub.example.com"),
        ]
        for item in cases {
            let body = goStatusBody(connected: item.connected, state: item.state, lastError: item.code, reason: item.reason)
            let (hero, status) = try screen(body)
            let name = "\(item.state)/\(item.code ?? "-")"
            XCTAssertEqual(hero.label, item.label, name)
            XCTAssertEqual(hero.subtitle, item.line, name)
            assertNoCode(hero.subtitle, name)
            assertNoCode(status.lastError, "\(name) status.lastError")
        }
    }

    /// Waiting for approval is a normal step, not a fault.
    func testWaitingForApprovalIsNotAFault() throws {
        let (hero, _) = try screen(goStatusBody(connected: false, state: "connecting", lastError: "enrollment_pending"))
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
