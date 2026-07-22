import XCTest
@testable import LabTetherAgent

final class BundleHelperTests: XCTestCase {
    func testPackagedAgentWinsOverDevelopmentCandidates() {
        let resolved = BundleHelper.resolveAgentBinaryPath(
            bundledPath: "/Applications/LabTether Agent.app/Contents/Resources/labtether-agent",
            overridePath: "/tmp/override-agent",
            executableURL: URL(fileURLWithPath: "/workspace/mac-agent/.build/debug/LabTetherAgent"),
            currentDirectoryPath: "/workspace/mac-agent",
            isExecutable: { $0.contains("Contents/Resources") || $0 == "/tmp/override-agent" }
        )

        XCTAssertEqual(
            resolved,
            "/Applications/LabTether Agent.app/Contents/Resources/labtether-agent"
        )
    }

    func testDevelopmentFallbackUsesSplitRepositoryBuildDirectory() {
        let expected = "/workspace/LabTether/mac-agent/build/labtether-agent-darwin"
        let resolved = BundleHelper.resolveAgentBinaryPath(
            bundledPath: nil,
            overridePath: nil,
            executableURL: URL(
                fileURLWithPath: "/workspace/LabTether/mac-agent/.build/arm64-apple-macosx/debug/LabTetherAgent"
            ),
            currentDirectoryPath: "/workspace/LabTether",
            isExecutable: { $0 == expected }
        )

        XCTAssertEqual(resolved, expected)
    }

    func testRelativeOverrideIsIgnored() {
        let expected = "/workspace/LabTether/mac-agent/build/labtether-agent-darwin"
        let resolved = BundleHelper.resolveAgentBinaryPath(
            bundledPath: nil,
            overridePath: "./untrusted-agent",
            executableURL: URL(fileURLWithPath: "/workspace/LabTether/mac-agent/.build/debug/LabTetherAgent"),
            currentDirectoryPath: "/workspace/LabTether/mac-agent",
            isExecutable: { $0 == expected || $0 == "./untrusted-agent" }
        )

        XCTAssertEqual(resolved, expected)
    }

    func testPathLookupIsLastResortWhenNoCandidateIsExecutable() {
        let resolved = BundleHelper.resolveAgentBinaryPath(
            bundledPath: nil,
            overridePath: nil,
            executableURL: nil,
            currentDirectoryPath: "/workspace/LabTether/mac-agent",
            isExecutable: { _ in false }
        )

        XCTAssertEqual(resolved, "labtether-agent")
    }
}
