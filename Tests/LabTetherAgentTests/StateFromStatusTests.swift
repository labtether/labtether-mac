import Combine
import XCTest
@testable import LabTetherAgent

/// An agent that prints nothing the app's log parser knows (the Rust agent
/// writes other words than the Go agent) must still get every effect the
/// Go log lines drive: the Keychain enrollment token removed once it is
/// used, connection notifications and the crash-counter reset. A real child
/// process does the agent's file work; the contract's status bodies go
/// through the poller's own result handler and the app's wiring.
@MainActor
final class StateFromStatusTests: XCTestCase {
    // MARK: - Enrollment token

    /// Risk: with a silent agent the used one-use token stayed in the
    /// Keychain for ever. It must go once the status shows a connection.
    func testSilentEnrollmentRemovesTheKeychainTokenOnceConnected() async throws {
        let agent = try SilentAgentFixture(child: .enrollsSilently)
        defer { agent.cleanup() }
        try await agent.startAndWait { !agent.enrollmentFileExists }
        _ = agent.owner.crashCoordinator.recordCrash()

        try agent.feed("enrollment-pending")
        XCTAssertEqual(agent.keychainToken, SilentAgentFixture.enrollmentValue, "not before the status says connected")

        try agent.feed("connected")
        XCTAssertNil(agent.keychainToken)
        XCTAssertEqual(agent.settings.enrollmentToken, "")
        XCTAssertEqual(agent.sent, [.connected, .enrolled])
        XCTAssertEqual(agent.owner.crashCoordinator.currentAttempt, 0)
        XCTAssertEqual(agent.state.state, .connected)
        XCTAssertTrue(agent.settings.hasPersistedAgentToken, "the agent token stays")

        try agent.feedVariant("connected") { $0["uptime"] = "2h15m3s" }
        XCTAssertEqual(agent.sent, [.connected, .enrolled], "a later poll fires nothing again")
    }

    /// Risk: removing the token too early leaves a Mac that cannot enroll.
    func testTheTokenStaysWhileEnrollmentWaitsOrIsRefused() async throws {
        let agent = try SilentAgentFixture(child: .waits)
        defer { agent.cleanup() }
        try await agent.startAndWait { agent.owner.isRunning }
        for name in ["enrollment-pending", "auth-failed-enrollment-token-rejected",
                     "enrollment-refused-hub-words", "connecting-transient-host-unreachable"] {
            try agent.feed(name)
            XCTAssertEqual(agent.keychainToken, SilentAgentFixture.enrollmentValue, name)
        }
        XCTAssertTrue(agent.enrollmentFileExists)
        XCTAssertFalse(agent.sent.contains(.enrolled))
    }

    /// A restart with a token already saved: the agent loads it and keeps
    /// the staged enrollment token for a later re-enrollment (Go:
    /// resolveTokenWithIdentity). Connected does not mean the token was used.
    func testARestartWithASavedTokenKeepsTheStagedEnrollmentToken() async throws {
        let agent = try SilentAgentFixture(child: .waits)
        defer { agent.cleanup() }
        try agent.writeAgentToken()
        try await agent.startAndWait { agent.owner.isRunning }
        try agent.feed("connected")
        XCTAssertEqual(agent.keychainToken, SilentAgentFixture.enrollmentValue)
        XCTAssertEqual(agent.sent, [.connected])
    }

    /// The Hub took the token but the agent could not save the new agent
    /// token: it removes any older one (enroll.go), so nothing proves the
    /// Mac can reconnect after a restart.
    func testTheTokenStaysWhenTheAgentTokenWasNotSaved() async throws {
        let agent = try SilentAgentFixture(child: .usesTokenButSavesNothing)
        defer { agent.cleanup() }
        try await agent.startAndWait { !agent.enrollmentFileExists }
        try agent.feed("connected-token-persistence-failed")
        XCTAssertEqual(agent.keychainToken, SilentAgentFixture.enrollmentValue)
    }

    /// A token saved in Settings after the child started was never given to
    /// it. The child using its own token must not remove the newer one.
    func testATokenSavedWhileTheChildRunsStays() async throws {
        let agent = try SilentAgentFixture(child: .enrollsSilently)
        defer { agent.cleanup() }
        try await agent.startAndWait { !agent.enrollmentFileExists }
        agent.settings.enrollmentToken = "fixture-enrollment-newer"
        try agent.feed("connected")
        XCTAssertEqual(agent.keychainToken, "fixture-enrollment-newer")
    }

    /// A child that crashes before it used the token keeps it; one that
    /// used it and quit before a poll saw it connected has it removed, or
    /// the next start would write the used token out again.
    func testACrashBeforeUseKeepsTheTokenAndACrashAfterUseRemovesIt() async throws {
        let before = try SilentAgentFixture(child: .savesTokenThenCrashes)
        defer { before.cleanup() }
        try await before.startAndWait { before.children.first?.isRunning == false && !before.owner.isRunning }
        XCTAssertEqual(before.keychainToken, SilentAgentFixture.enrollmentValue)

        let after = try SilentAgentFixture(child: .enrollsThenCrashes)
        defer { after.cleanup() }
        try await after.startAndWait { after.children.first?.isRunning == false && !after.owner.isRunning }
        XCTAssertNil(after.keychainToken)
        XCTAssertEqual(after.sent.filter { $0 == .enrolled }.count, 1)
    }

    /// The whole path with nothing stood in for but the agent: the child
    /// enrolls silently and serves a contract body on the port the app gave
    /// it; the app's poller fetches it over HTTP with its bearer token.
    func testThePollerOverHTTPRemovesTheTokenOfASilentAgent() async throws {
        let python = "/usr/bin/python3"
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: python), "no python3 to serve the status")
        let agent = try SilentAgentFixture(child: .enrollsSilently, servesStatus: "connected", python: python)
        defer { agent.cleanup() }
        agent.settings.agentPort = String(Int.random(in: 20_000...45_000))
        try await agent.startAndWait { !agent.enrollmentFileExists }
        agent.client.start(settings: agent.settings)
        try await agent.waitUntil(seconds: 15) { agent.keychainToken == nil }
        XCTAssertTrue(agent.client.isReachable)
        XCTAssertEqual(agent.state.state, .connected)
        XCTAssertEqual(agent.sent, [.connected, .enrolled])
    }

    // MARK: - Connection notifications

    /// Risk: with a silent agent "connected" and "connection lost" never
    /// showed and the crash counter never reset.
    func testConnectionNotificationsFollowTheStatus() async throws {
        let agent = try SilentAgentFixture(child: .waits)
        defer { agent.cleanup() }
        try agent.writeAgentToken()
        try await agent.startAndWait { agent.owner.isRunning }
        _ = agent.owner.crashCoordinator.recordCrash()

        try agent.feed("connected")
        XCTAssertEqual(agent.sent, [.connected])
        XCTAssertEqual(agent.owner.crashCoordinator.currentAttempt, 0)

        // A connection that lasted, then a failed reconnect.
        let later = Date().addingTimeInterval(60)
        try agent.feedVariant("disconnected-no-transport") { $0["disconnected_at"] = SilentAgentFixture.goTime(later) }
        XCTAssertEqual(agent.sent, [.connected], "lost is said when a reconnect fails")
        try agent.feedVariant("connecting-transient-host-unreachable") {
            $0["disconnected_at"] = SilentAgentFixture.goTime(later)
        }
        XCTAssertEqual(agent.sent, [.connected, .connectionLost])
        try agent.feedVariant("connecting-transient-host-unreachable") { $0["last_error_reason"] = "timed_out" }
        XCTAssertEqual(agent.sent, [.connected, .connectionLost], "not on every retry")

        try agent.feed("connected")
        XCTAssertEqual(agent.sent, [.connected, .connectionLost, .connected])

        // The Hub refusing the token is not a lost connection.
        try agent.feed("auth-failed-token-rejected")
        XCTAssertEqual(agent.state.state, .authFailed)
        XCTAssertEqual(agent.sent, [.connected, .connectionLost, .connected])
    }

    /// The Hub accepts each connection and closes it at once. Go prints a
    /// line for that and the app stays quiet; from the status the app must
    /// stay quiet too. The fixture's `disconnected_at` is before the app
    /// saw the connection, so the connection counts as short.
    func testAHubThatKeepsClosingConnectionsRaisesOneNotification() async throws {
        let agent = try SilentAgentFixture(child: .waits)
        defer { agent.cleanup() }
        try agent.writeAgentToken()
        try await agent.startAndWait { agent.owner.isRunning }
        for round in 0..<3 {
            try agent.feedVariant("connected") { $0["uptime"] = "\(round)s" }
            try agent.feedVariant("connecting-transient-host-unreachable") { $0["uptime"] = "\(round)s" }
            XCTAssertEqual(agent.state.state, .reconnecting)
        }
        XCTAssertEqual(agent.sent, [.connected])
    }

    // MARK: - Both sources

    /// The Go agent prints its lines and serves its status. Each effect must
    /// fire once whichever arrives first. The child prints the enrollment
    /// lines at once and "connected to" a second later, after the poll.
    func testGoLinesAndStatusTogetherFireEachEffectOnce() async throws {
        let agent = try SilentAgentFixture(child: .enrollsWithGoLines)
        defer { agent.cleanup() }
        try await agent.startAndWait { agent.keychainToken == nil }
        XCTAssertEqual(agent.sent, [.enrolled], "the log line removed the token first")

        try agent.feed("connected")
        XCTAssertEqual(agent.sent, [.enrolled, .connected])
        try await agent.waitUntil {
            agent.logBuffer.logLines.contains { $0.raw.contains("agentws: connected to") }
        }
        XCTAssertEqual(agent.sent, [.enrolled, .connected], "the later log line fires nothing again")
        XCTAssertEqual(agent.state.state, .connected)
    }
}

@MainActor
private final class SilentAgentFixture {
    static let enrollmentValue = "fixture-enrollment-value"

    /// What the stand-in child does. None prints a line the parser knows,
    /// except `enrollsWithGoLines`. The order of file work is the agent's:
    /// write the agent token, then remove the used enrollment token file.
    enum Child {
        case waits
        case enrollsSilently
        case usesTokenButSavesNothing
        case savesTokenThenCrashes
        case enrollsThenCrashes
        case enrollsWithGoLines

        func script(serving directory: URL?, python: String) -> String {
            let save = "umask 077; printf 'issued-agent-value\\n' > \"$LABTETHER_TOKEN_FILE\""
            let use = "rm -f \"$LABTETHER_ENROLLMENT_TOKEN_FILE\""
            let wait = directory.map {
                "exec \(python) -m http.server \"$AGENT_PORT\" --bind 127.0.0.1 --directory '\($0.path)'"
            } ?? "exec /bin/sleep 30"
            switch self {
            case .waits: return wait
            case .enrollsSilently: return "\(save)\n\(use)\necho 'enrolled as nas01'\n\(wait)"
            case .usesTokenButSavesNothing: return "\(use)\n\(wait)"
            case .savesTokenThenCrashes: return "\(save)\nexit 3"
            case .enrollsThenCrashes: return "\(save)\n\(use)\nexit 3"
            case .enrollsWithGoLines:
                return """
                \(save)
                \(use)
                echo '2026/11/16 10:00:00 agent: removed consumed enrollment token file' >&2
                echo '2026/11/16 10:00:00 agent: enrolled successfully as nas01' >&2
                sleep 1
                echo '2026/11/16 10:00:01 agentws: connected to wss://localhost:8443/ws/agent' >&2
                \(wait)
                """
            }
        }
    }

    private let suite = "LabTetherAgentTests.StateFromStatus.\(UUID().uuidString)"
    private let store: UserDefaults
    private let root: URL
    let settings: AgentSettings
    let state = AgentStatus()
    let logBuffer = LogBuffer()
    let client = LocalAPIClient()
    private(set) var children: [Process] = []
    private(set) var sent: [AgentNotification] = []
    private var follow: AnyCancellable?
    private(set) var owner: AgentProcess!

    init(child: Child, servesStatus fixture: String? = nil, python: String = "") throws {
        store = try XCTUnwrap(UserDefaults(suiteName: suite))
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("labtether-state-from-status-\(UUID().uuidString)")
        let binary = root.appendingPathComponent("stand-in-agent")
        settings = AgentSettings(testSettingsStore: store, appSupportDirectory: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var served: URL?
        if let fixture {
            let site = root.appendingPathComponent("site")
            try FileManager.default.createDirectory(at: site.appendingPathComponent("agent"), withIntermediateDirectories: true)
            try StatusFixtures.data(fixture).write(to: site.appendingPathComponent("agent/status"))
            served = site
        }
        try Data("#!/bin/sh\n\(child.script(serving: served, python: python))\n".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        settings.enrollmentToken = Self.enrollmentValue

        let notifications = NotificationManager(requestAuthorization: false, allowSystemIntegration: false)
        owner = AgentProcess(
            status: state, settings: settings, notifications: notifications, logBuffer: logBuffer,
            sessionHistory: SessionHistoryTracker(filePath: root.appendingPathComponent("history.json").path),
            makeProcess: { [weak self] in
                let process = Process()
                self?.children.append(process)
                return process
            },
            agentBinaryPath: { binary.path },
            waitForCrashRestart: { _ in try? await Task.sleep(for: .seconds(3600)) }
        )
        notifications.onNotify = { [weak self] event in
            if case .crashRestart = event { return }
            self?.sent.append(event)
        }
        follow = owner.followRuntime(client.runtime)
    }

    var keychainToken: String? { settings.bootstrapSecrets.load(account: AgentSettings.enrollmentTokenAccount) }

    var enrollmentFileExists: Bool {
        (try? FileManager.default.attributesOfItem(atPath: settings.enrollmentTokenFilePath)) != nil
    }

    /// The agent token a previous run saved.
    func writeAgentToken() throws {
        try Data("saved-agent-value\n".utf8).write(to: URL(fileURLWithPath: settings.tokenFilePath))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settings.tokenFilePath)
    }

    func startAndWait(_ condition: () -> Bool) async throws {
        owner.start()
        XCTAssertEqual(children.count, 1, "the stand-in child started")
        try await waitUntil(condition)
    }

    func waitUntil(seconds: TimeInterval = 5, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition(), "the stand-in child did not reach the expected point")
    }

    /// One contract body, through the poller's own 200 handler.
    func feed(_ name: String) throws {
        client.applySuccessfulPollResult(try LocalAPIClient.decodeStatus(StatusFixtures.data(name)))
    }

    func feedVariant(_ name: String, _ edit: (inout [String: Any]) -> Void) throws {
        client.applySuccessfulPollResult(try LocalAPIClient.decodeStatus(StatusFixtures.variant(name, edit)))
    }

    static func goTime(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    func cleanup() {
        client.stop()
        follow = nil
        for child in children { child.terminationHandler = nil }
        owner.forceKill()
        for child in children where child.isRunning {
            child.terminate()
            child.waitUntilExit()
        }
        store.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}
