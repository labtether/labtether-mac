import XCTest
import Darwin
@testable import LabTetherAgent

final class AppStateIsolationTests: XCTestCase {
    // Risk: `--state-directory /private/var/...` made the app exit at start
    // while the same folder spelled `/var/...` worked.
    func testStateDirectorySpelledWithPrivateOpensLikeVarSpelling() throws {
        let environment = ProcessInfo.processInfo.environment
        let temporary = environment["LABTETHER_JOB_SCRATCH"] ?? environment["TMPDIR"] ?? ""
        let base = URL(fileURLWithPath: temporary, isDirectory: true).resolvingSymlinksInPath()
        guard base.path.hasPrefix("/var/") else { throw XCTSkip("temporary folder is not under /var") }
        let root = base.appendingPathComponent("lt-state-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }

        let location = try AppStateLocation.bootstrap(
            arguments: ["LabTetherAgent", "--state-directory", "/private" + root.path])
        XCTAssertEqual(location.root.path, root.path)
        XCTAssertThrowsError(try AppStateLocation.bootstrap(
            arguments: ["LabTetherAgent", "--state-directory", "/private" + root.path + "/../x"]))
    }

    @MainActor
    func testIsolatedOnboardingPersistsOnlyOwnedSettingsAndRuntimeSecrets() throws {
        let first = try PrivateStateFixture()
        defer { first.cleanup() }
        let peer = try PrivateStateFixture()
        defer { peer.cleanup() }
        let settings = try AgentSettings(location: first.location)
        let peerSettings = try AgentSettings(location: peer.location)
        peerSettings.hubURL = "wss://peer.example/ws/agent"
        peerSettings.enrollmentToken = "peer-bootstrap"
        _ = try peerSettings.buildEnvironment()
        let peerBefore = try peer.snapshot()

        let wizard = OnboardingState()
        wizard.hubURL = " wss://isolated.example/ws/agent "
        wizard.tokenValue = " owned-bootstrap "
        wizard.assetID = "isolated-asset"
        wizard.groupID = "isolated-group"
        wizard.applyToSettings(settings)
        settings.dockerEnabled = "false"
        settings.servicesDiscoveryLANScanEnabled = true
        settings.startAtLogin = true // Preference only; no system registration.
        settings.webrtcTurnPass = "owned-turn-secret"
        XCTAssertFalse(settings.allowsSystemIntegration)
        XCTAssertThrowsError(try AppStateLocation(root: first.root, isolated: true))
        let environment = try settings.buildEnvironment()
        XCTAssertEqual(environment["HOME"], first.root.path)
        XCTAssertEqual(environment["LABTETHER_TOKEN_FILE"], settings.tokenFilePath)
        XCTAssertEqual(environment["LABTETHER_ENROLLMENT_TOKEN_FILE"], settings.enrollmentTokenFilePath)
        XCTAssertNil(environment["LABTETHER_API_TOKEN"])
        let saved = try XCTUnwrap(first.location.read("preferences.json"))
        XCTAssertFalse(String(decoding: saved, as: UTF8.self).contains("owned-bootstrap"))
        XCTAssertFalse(String(decoding: saved, as: UTF8.self).contains("owned-turn-secret"))
        XCTAssertEqual(try first.location.read("enrollment-token"), Data("owned-bootstrap\n".utf8))
        XCTAssertFalse(settings.localAPIAuthToken.isEmpty)

        let reloaded = try AgentSettings(location: first.location)
        XCTAssertEqual(reloaded.hubURL, "wss://isolated.example/ws/agent")
        XCTAssertEqual(reloaded.assetID, "isolated-asset")
        XCTAssertEqual(reloaded.dockerEnabled, "false")
        XCTAssertTrue(reloaded.servicesDiscoveryLANScanEnabled)
        XCTAssertTrue(reloaded.hasCompletedOnboarding)
        XCTAssertTrue(reloaded.startAtLogin)
        XCTAssertEqual(reloaded.enrollmentToken, "") // Bootstrap is not archived.
        XCTAssertTrue(reloaded.isConfigured) // The child's one-use input is durable.
        try first.location.write(Data("issued-agent-token\n".utf8), name: "agent-token")
        reloaded.clearConsumedEnrollmentTokenPreservingAgentToken()
        XCTAssertNil(try first.location.read("enrollment-token"))
        XCTAssertEqual(try first.location.read("agent-token"), Data("issued-agent-token\n".utf8))
        settings.cleanupEphemeralSecrets()
        XCTAssertNil(try first.location.read("local-api-auth-token"))
        XCTAssertEqual(try peer.snapshot(), peerBefore)
        XCTAssertEqual(peerSettings.enrollmentToken, "peer-bootstrap")

        // Equivalent directory URL hints must not reject a direct owned path;
        // traversal and a peer's direct path must still be rejected.
        XCTAssertEqual(first.location.root.path, first.root.path)
        XCTAssertFalse(first.location.root.hasDirectoryPath)
        XCTAssertThrowsError(try settings.persistRuntimeSecret(
            "not-written", to: peerSettings.localAPIAuthTokenFilePath,
            issueKey: "test.foreign", label: "Test secret"))
        XCTAssertThrowsError(try settings.persistRuntimeSecret(
            "not-written", to: first.root.path + "/../escape",
            issueKey: "test.traversal", label: "Test secret"))

        // The real file owner must not follow a runtime-secret alias outside its root.
        let sentinel = peer.root.appendingPathComponent("sentinel")
        try peer.location.write(Data("unchanged".utf8), name: "sentinel")
        try FileManager.default.createSymbolicLink(atPath: settings.localAPIAuthTokenFilePath,
                                                  withDestinationPath: sentinel.path)
        XCTAssertThrowsError(try settings.ensureLocalAPIAuthToken())
        XCTAssertEqual(try peer.location.read("sentinel"), Data("unchanged".utf8))
    }

    @MainActor
    func testSameBinaryChildrenHaveSeparateQuitAndRecoveryAuthority() throws {
        let first = try PrivateStateFixture()
        defer { first.cleanup() }
        let peer = try PrivateStateFixture()
        defer { peer.cleanup() }
        let firstSettings = try AgentSettings(location: first.location)
        let peerSettings = try AgentSettings(location: peer.location)
        try first.location.write(Data("first-token\n".utf8), name: "agent-token")
        try peer.location.write(Data("peer-token\n".utf8), name: "agent-token")
        var firstChildren: [Process] = [], peerChildren: [Process] = []
        let a = makeOwner(firstSettings) { firstChildren.append($0) }
        let b = makeOwner(peerSettings) { peerChildren.append($0) }
        defer {
            for child in firstChildren + peerChildren { child.terminationHandler = nil }
            a.forceKill(); b.forceKill()
            for child in firstChildren + peerChildren where child.isRunning {
                kill(child.processIdentifier, SIGKILL)
                child.waitUntilExit()
            }
        }
        a.start(); b.start()
        XCTAssertTrue(a.isRunning); XCTAssertTrue(b.isRunning)
        let old = try XCTUnwrap(firstChildren.first)
        let other = try XCTUnwrap(peerChildren.first)
        XCTAssertTrue(old.isRunning) // Starting the same binary for B did not reap A.
        a.forceKill()
        old.waitUntilExit()
        XCTAssertTrue(other.isRunning)
        a.start()
        let current = try XCTUnwrap(firstChildren.last)
        XCTAssertNotEqual(current.processIdentifier, old.processIdentifier)
        XCTAssertTrue(current.isRunning)

        let recovery = AgentChildOwnership(location: first.location)
        let exact = try XCTUnwrap(first.location.read("child.json"))
        // A record copied from the other root must not grant recovery authority.
        try first.location.write(XCTUnwrap(peer.location.read("child.json")), name: "child.json")
        XCTAssertThrowsError(try recovery.recover(binaryPath: "/bin/sleep"))
        XCTAssertTrue(current.isRunning); XCTAssertTrue(other.isRunning)
        let record = try JSONDecoder().decode(AgentChildOwnership.Record.self, from: exact)
        let staleIdentity = AgentChildOwnership.Identity(
            pid: record.child.pid, uid: record.child.uid,
            startedSeconds: record.child.startedSeconds + 1,
            startedMicroseconds: record.child.startedMicroseconds, executable: record.child.executable)
        let stale = AgentChildOwnership.Record(rootDevice: record.rootDevice, rootInode: record.rootInode, child: staleIdentity)
        try first.location.write(JSONEncoder().encode(stale), name: "child.json")
        XCTAssertThrowsError(try recovery.recover(binaryPath: "/bin/sleep"))
        XCTAssertTrue(current.isRunning); XCTAssertTrue(other.isRunning)
        try first.location.write(exact, name: "child.json")
        try recovery.recover(binaryPath: "/bin/sleep")
        current.waitUntilExit()
        XCTAssertNil(try first.location.read("child.json"))
        XCTAssertTrue(other.isRunning)
        // A dead child must not prevent the app from moving to another path.
        try first.location.write(exact, name: "child.json")
        try recovery.recover(binaryPath: "/bin/echo")
        XCTAssertNil(try first.location.read("child.json"))
        XCTAssertTrue(other.isRunning)
    }

    /// Risk: an app in a temporary folder, or one macOS runs from a
    /// translocated copy (opened from Downloads), never starts its agent core,
    /// because the kernel reports /private/var/... and Foundation drops /private.
    @MainActor
    func testChildStartsFromABinaryUnderPrivateVar() throws {
        let state = try PrivateStateFixture()
        defer { state.cleanup() }
        // The per-user temp folder, where macOS also puts translocated apps.
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let userTemp = confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count) > 0
            ? String(cString: buffer) : NSTemporaryDirectory()
        let folder = URL(fileURLWithPath: userTemp).appendingPathComponent("lt-bin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let copy = folder.appendingPathComponent("labtether-agent")
        try FileManager.default.copyItem(atPath: "/bin/sleep", toPath: copy.path)
        let real = try XCTUnwrap(realpath(copy.path, nil))
        let resolved = String(cString: real)
        free(real)
        try XCTSkipUnless(resolved.hasPrefix("/private/"), "temporary folder is not under /private here")
        let settings = try AgentSettings(location: state.location)
        try state.location.write(Data("token\n".utf8), name: "agent-token")
        for spelling in [resolved, String(resolved.dropFirst("/private".count))] {
            var children: [Process] = []
            let owner = makeOwner(settings, binary: spelling) { children.append($0) }
            owner.start()
            let child = try XCTUnwrap(children.first)
            XCTAssertTrue(owner.isRunning, "agent core did not start from \(spelling)")
            child.terminationHandler = nil
            owner.forceKill()
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            child.waitUntilExit()
        }
    }

    @MainActor
    private func makeOwner(_ settings: AgentSettings, binary: String = "/bin/sleep",
                           record: @escaping (Process) -> Void) -> AgentProcess {
        AgentProcess(status: AgentStatus(), settings: settings,
                     notifications: NotificationManager(requestAuthorization: false, allowSystemIntegration: false),
                     logBuffer: LogBuffer(),
                     sessionHistory: SessionHistoryTracker(filePath: settings.appSupportDirectory.appendingPathComponent("history.json").path),
                     makeProcess: { let child = Process(); child.arguments = ["30"]; record(child); return child },
                     agentBinaryPath: { binary })
    }
}

private final class PrivateStateFixture {
    let root: URL
    let location: AppStateLocation
    init() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["LABTETHER_JOB_ID"] == nil || environment["LABTETHER_JOB_SCRATCH"] != nil else {
            throw AppStateLocation.Failure.invalidRoot
        }
        guard let temporary = environment["LABTETHER_JOB_SCRATCH"] ?? environment["TMPDIR"],
              temporary.hasPrefix("/") else { throw AppStateLocation.Failure.invalidRoot }
        let base = URL(fileURLWithPath: temporary, isDirectory: true).resolvingSymlinksInPath()
        var info = stat()
        guard lstat(base.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == getuid() else { throw AppStateLocation.Failure.invalidRoot }
        root = base.appendingPathComponent("lt-state-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            // Preserve a legal no-trailing-slash form to exercise the real
            // runtime-secret path conversion rather than matching URL hints.
            location = try AppStateLocation(root: URL(fileURLWithPath: root.path, isDirectory: false), isolated: true)
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }
    func snapshot() throws -> [String: Data] {
        var values: [String: Data] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: root.path) where name != ".app.lock" {
            values[name] = try location.read(name)
        }
        return values
    }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}
