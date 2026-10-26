import XCTest
@testable import LabTetherAgent

final class AgentProcessOwnershipTests: XCTestCase {
    @MainActor
    func testRetiredChildTerminationCannotStopReplacementOrEraseItsLocalAuth() throws {
        try assertReplacementSurvivesDelayedTermination(restartExitedChild: false)
    }

    @MainActor
    func testRestartOwnsAlreadyExitedChildBeforeItsQueuedTerminationArrives() throws {
        try assertReplacementSurvivesDelayedTermination(restartExitedChild: true)
    }

    @MainActor
    func testRetiredCrashDelayCannotSkipReplacementBackoffOrCooldown() async throws {
        let delay = ControlledCrashDelay()
        let fixture = try ProcessOwnerFixture(waitForCrashRestart: { await delay.wait($0) })
        defer {
            fixture.cleanup()
            delay.releaseAll()
        }
        let owner = fixture.owner
        owner.start()
        try fixture.crashCurrentChild()
        try await waitUntil { delay.pendingCount == 1 }
        let firstRestart = try XCTUnwrap(owner.crashRestartTask)

        owner.start() // Manual start retires the first child's delayed restart.
        try fixture.crashCurrentChild()
        try await waitUntil { delay.pendingCount == 2 }
        let secondRestart = try XCTUnwrap(owner.crashRestartTask)
        delay.release(0)
        await firstRestart.value
        XCTAssertEqual(fixture.children.count, 2)
        XCTAssertFalse(owner.isRunning)
        XCTAssertFalse(secondRestart.isCancelled)

        owner.start() // A later child can reach the existing crash-loop cooldown.
        for _ in 0..<CrashRestartCoordinator.maxCrashRestarts {
            _ = owner.crashCoordinator.recordCrash()
        }
        try fixture.crashCurrentChild()
        XCTAssertTrue(owner.crashCoordinator.crashLoopActive)
        delay.release(1)
        await secondRestart.value
        XCTAssertEqual(fixture.children.count, 3)
        XCTAssertFalse(owner.isRunning)
        XCTAssertTrue(owner.crashCoordinator.crashLoopActive)
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition() && Date() < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        _ = try XCTUnwrap(condition() ? true : nil, "Crash restart did not reach its controlled delay")
    }

    @MainActor
    private func assertReplacementSurvivesDelayedTermination(restartExitedChild: Bool) throws {
        let fixture = try ProcessOwnerFixture()
        defer { fixture.cleanup() }
        let owner = fixture.owner
        owner.start()
        XCTAssertTrue(owner.isRunning)
        let retired = try XCTUnwrap(owner.isRunning ? fixture.children.first : nil)
        // Delay the real owner's termination delivery until the next child exists.
        retired.terminationHandler = nil
        if restartExitedChild {
            retired.terminate()
            retired.waitUntilExit()
            owner.restart()
        } else {
            owner.forceKill()
            retired.waitUntilExit()
            owner.start()
        }
        XCTAssertEqual(fixture.children.count, 2)
        let replacement = try XCTUnwrap(fixture.children.last)
        let currentAuth = fixture.settings.localAPIAuthToken
        XCTAssertFalse(currentAuth.isEmpty)

        owner.handleTermination(of: retired)

        XCTAssertTrue(owner.isRunning)
        XCTAssertTrue(replacement.isRunning)
        XCTAssertEqual(fixture.state.pid, replacement.processIdentifier)
        XCTAssertEqual(fixture.state.state, .starting)
        XCTAssertEqual(fixture.settings.localAPIAuthToken, currentAuth)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.settings.localAPIAuthTokenFilePath))
    }
}

@MainActor
private final class ControlledCrashDelay {
    private var pending: [CheckedContinuation<Void, Never>?] = []
    var pendingCount: Int { pending.count }

    func wait(_ delay: TimeInterval) async {
        // Deliberately ignore cancellation until released: the owner must check it.
        await withCheckedContinuation { pending.append($0) }
    }

    func release(_ index: Int) {
        pending[index]?.resume()
        pending[index] = nil
    }

    func releaseAll() {
        for index in pending.indices { release(index) }
    }
}

@MainActor
private final class ProcessOwnerFixture {
    private let suite = "LabTetherAgentTests.ProcessOwner.\(UUID().uuidString)"
    private let store: UserDefaults
    private let root: URL
    private let binary: URL
    private let waitForCrashRestart: @MainActor (TimeInterval) async -> Void
    let settings: AgentSettings
    let state = AgentStatus()
    private(set) var children: [Process] = []

    lazy var owner = AgentProcess(
        status: state, settings: settings,
        notifications: NotificationManager(requestAuthorization: false),
        logBuffer: LogBuffer(),
        sessionHistory: SessionHistoryTracker(filePath: root.appendingPathComponent("history.json").path),
        makeProcess: { [weak self] in
            let child = Process()
            self?.children.append(child)
            return child
        },
        agentBinaryPath: { [binary] in binary.path },
        waitForCrashRestart: waitForCrashRestart
    )

    init(waitForCrashRestart: @escaping @MainActor (TimeInterval) async -> Void = { delay in
        try? await Task.sleep(for: .seconds(delay))
    }) throws {
        store = try XCTUnwrap(UserDefaults(suiteName: suite))
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("labtether-process-owner-\(UUID().uuidString)")
        binary = root.appendingPathComponent("fixture-child")
        self.waitForCrashRestart = waitForCrashRestart
        settings = AgentSettings(testSettingsStore: store, appSupportDirectory: root)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data("#!/bin/sh\nexec /bin/sleep 30\n".utf8).write(to: binary)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
            let tokenFile = URL(fileURLWithPath: settings.tokenFilePath)
            try Data("fixture-durable-token\n".utf8).write(to: tokenFile)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenFile.path)
        } catch {
            store.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    func crashCurrentChild() throws {
        let child = try XCTUnwrap(children.last)
        XCTAssertTrue(child.isRunning)
        child.terminationHandler = nil
        child.terminate()
        child.waitUntilExit()
        XCTAssertNotEqual(child.terminationStatus, 0)
        owner.handleTermination(of: child)
    }

    func cleanup() {
        let running = children.filter(\.isRunning)
        for child in children { child.terminationHandler = nil }
        owner.forceKill()
        for child in running {
            if child.isRunning { child.terminate() }
            child.waitUntilExit()
        }
        store.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}
