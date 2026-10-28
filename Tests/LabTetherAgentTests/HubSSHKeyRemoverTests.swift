import XCTest
@testable import LabTetherAgent

/// Risks: uninstall leaves the Hub's SSH key in authorized_keys, or the
/// bundled 1.7.0 agent (no `ssh-key` command) or a hung agent stops the
/// uninstall.
final class HubSSHKeyRemoverTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("labtether-ssh-key-remover-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testRunsRemoveWithTheAppsTokenFile() throws {
        let agent = try fakeAgent("""
        [ "$1 $2" = "ssh-key remove" ] || exit 3
        [ "$LABTETHER_TOKEN_FILE" = "/Users/demo/state/agent-token" ] || exit 4
        echo "removed the Hub SSH key from /Users/demo/.ssh/authorized_keys"
        """)
        XCTAssertEqual(run(agent), .done("removed the Hub SSH key from /Users/demo/.ssh/authorized_keys"))
    }

    func testOlderAgentWithoutTheCommandIsNotAFailure() throws {
        let agent = try fakeAgent("""
        echo "unknown command: ssh-key"
        echo "Usage:"
        exit 1
        """)
        XCTAssertEqual(run(agent), .unsupported)
    }

    func testHungAgentIsStoppedAndReported() throws {
        let agent = try fakeAgent("sleep 30")
        guard case .failed = run(agent, timeout: 0.5) else { return XCTFail("expected a failure") }
    }

    private func run(_ agent: String, timeout: TimeInterval = 10) -> HubSSHKeyRemover.Outcome {
        HubSSHKeyRemover.run(agentBinaryPath: agent,
                             tokenFilePath: "/Users/demo/state/agent-token",
                             agentSettingsFilePath: "/Users/demo/state/agent-config.json",
                             timeout: timeout)
    }

    private func fakeAgent(_ body: String) throws -> String {
        let path = folder.appendingPathComponent("labtether-agent-\(UUID().uuidString)").path
        try Data("#!/bin/sh\n\(body)\n".utf8).write(to: URL(fileURLWithPath: path))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
        return path
    }
}
