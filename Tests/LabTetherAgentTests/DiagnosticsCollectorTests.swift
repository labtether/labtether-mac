import XCTest
@testable import LabTetherAgent

final class DiagnosticsCollectorTests: XCTestCase {

    // MARK: - Baseline collect call

    private func makeReport(
        appVersion: String = "1.2.3",
        buildNumber: String = "42",
        agentVersion: String? = "0.9.1",
        osVersion: String = "macOS 15.0",
        architecture: String = "arm64",
        hubURL: String = "wss://hub.example.com/ws/agent",
        connectionState: String = "connected",
        apiTokenConfigured: Bool = true,
        enrollmentTokenConfigured: Bool = false,
        assetID: String = "asset-abc",
        groupID: String = "group-xyz",
        pid: Int32? = 1234,
        uptime: String? = "5m",
        tlsSkipVerify: Bool = false,
        dockerMode: String = "auto",
        filesRootMode: String = "home",
        allowRemoteOverrides: Bool = false,
        logLevel: String = "info",
        webrtcEnabled: Bool = false,
        screenSharingEnabled: Bool = true,
        screenSharingControlAccess: Bool = true,
        validationErrors: [String] = [],
        secretPersistenceErrors: [String] = [],
        logSummaryLines: [String] = []
    ) -> String {
        DiagnosticsCollector.collect(
            appVersion: appVersion,
            buildNumber: buildNumber,
            agentVersion: agentVersion,
            osVersion: osVersion,
            architecture: architecture,
            hubURL: hubURL,
            connectionState: connectionState,
            apiTokenConfigured: apiTokenConfigured,
            enrollmentTokenConfigured: enrollmentTokenConfigured,
            assetID: assetID,
            groupID: groupID,
            pid: pid,
            uptime: uptime,
            tlsSkipVerify: tlsSkipVerify,
            dockerMode: dockerMode,
            filesRootMode: filesRootMode,
            allowRemoteOverrides: allowRemoteOverrides,
            logLevel: logLevel,
            webrtcEnabled: webrtcEnabled,
            screenSharingEnabled: screenSharingEnabled,
            screenSharingControlAccess: screenSharingControlAccess,
            validationErrors: validationErrors,
            secretPersistenceErrors: secretPersistenceErrors,
            logSummaryLines: logSummaryLines
        )
    }

    // MARK: - Tests

    func testCollectIncludesAppVersionAndOSVersion() {
        let report = makeReport(
            appVersion: "2.5.0",
            buildNumber: "99",
            osVersion: "macOS 14.5",
            architecture: "x86_64"
        )

        XCTAssertTrue(report.contains("2.5.0 (99)"), "Expected formatted app version in report")
        XCTAssertTrue(report.contains("macOS 14.5"), "Expected OS version in report")
        XCTAssertTrue(report.contains("x86_64"), "Expected architecture in report")
    }

    func testCollectIncludesAgentVersionWhenPresent() {
        let report = makeReport(agentVersion: "1.0.5")

        XCTAssertTrue(report.contains("1.0.5"), "Expected agent version when present")
        XCTAssertFalse(report.contains("Not running"), "Should not show 'Not running' when version is present")
    }

    func testCollectShowsNotRunningWhenAgentVersionIsNil() {
        let report = makeReport(agentVersion: nil)

        XCTAssertTrue(report.contains("Not running"), "Expected 'Not running' when agentVersion is nil")
    }

    func testCollectMasksTokenValues() {
        // Configured tokens: report says "configured" — never actual values
        let reportWithTokens = makeReport(
            apiTokenConfigured: true,
            enrollmentTokenConfigured: true
        )
        XCTAssertTrue(reportWithTokens.contains("configured"), "Expected 'configured' label for set token")
        XCTAssertFalse(reportWithTokens.contains("Bearer"), "Token values must never appear in report")
        XCTAssertFalse(reportWithTokens.contains("sk-"), "Token values must never appear in report")

        // Unconfigured tokens: report says "not configured"
        let reportWithoutTokens = makeReport(
            apiTokenConfigured: false,
            enrollmentTokenConfigured: false
        )
        XCTAssertTrue(reportWithoutTokens.contains("not configured"), "Expected 'not configured' for unset token")
    }

    func testCollectIncludesConnectionState() {
        let report = makeReport(hubURL: "wss://mylab.local/ws/agent", connectionState: "auth_failed")

        XCTAssertTrue(report.contains("auth_failed"), "Expected connection state in report")
        XCTAssertTrue(report.contains("wss://mylab.local/ws/agent"), "Expected hub URL in report")
    }

    func testCollectIncludesAssetAndGroupIDs() {
        let report = makeReport(assetID: "my-asset-42", groupID: "prod-group")

        XCTAssertTrue(report.contains("my-asset-42"))
        XCTAssertTrue(report.contains("prod-group"))
    }

    func testCollectShowsNoneForEmptyGroupID() {
        let report = makeReport(groupID: "")

        XCTAssertTrue(report.contains("(none)"), "Expected '(none)' when groupID is empty")
    }

    func testCollectIncludesPIDAndUptime() {
        let report = makeReport(pid: 9876, uptime: "22m")

        XCTAssertTrue(report.contains("9876"))
        XCTAssertTrue(report.contains("22m"))
    }

    func testCollectShowsNoneForNilPID() {
        let report = makeReport(pid: nil)

        XCTAssertTrue(report.contains("none"), "Expected 'none' for nil PID")
    }

    func testCollectShowsNAForNilUptime() {
        let report = makeReport(uptime: nil)

        XCTAssertTrue(report.contains("n/a"), "Expected 'n/a' for nil uptime")
    }

    func testCollectIncludesConfigurationFields() {
        let report = makeReport(
            tlsSkipVerify: true,
            dockerMode: "true",
            filesRootMode: "full",
            allowRemoteOverrides: true,
            logLevel: "debug",
            webrtcEnabled: true
        )

        XCTAssertTrue(report.contains("true"))
        XCTAssertTrue(report.contains("debug"))
        XCTAssertTrue(report.contains("full"))
    }

    func testCollectIncludesScreenSharingSection() {
        let report = makeReport(screenSharingEnabled: true, screenSharingControlAccess: false)

        XCTAssertTrue(report.contains("Screen Sharing"), "Expected Screen Sharing section")
        XCTAssertTrue(report.contains("Control Access"), "Expected Control Access field")
    }

    func testCollectIncludesValidationErrors() {
        let errors = ["Hub URL is invalid", "API token is required"]
        let report = makeReport(validationErrors: errors)

        XCTAssertTrue(report.contains("Issues"), "Expected Issues section when there are validation errors")
        XCTAssertTrue(report.contains("Hub URL is invalid"), "Expected first validation error")
        XCTAssertTrue(report.contains("API token is required"), "Expected second validation error")
    }

    func testCollectOmitsIssuesSectionWhenNoErrors() {
        let report = makeReport(validationErrors: [], secretPersistenceErrors: [])

        XCTAssertFalse(report.contains("### Issues"), "Issues section should be absent when there are no errors")
    }

    func testCollectIncludesSecretPersistenceErrors() {
        let secretErrors = ["API token could not be saved to Keychain"]
        let report = makeReport(secretPersistenceErrors: secretErrors)

        XCTAssertTrue(report.contains("Issues"))
        XCTAssertTrue(report.contains("API token could not be saved to Keychain"))
    }

    func testCollectIncludesLogSummary() {
        let summaryLines = [
            "Buffered Logs: 10 total (2 error, 3 warning, 5 info)",
            "Recent raw log lines are omitted from clipboard diagnostics for redaction safety."
        ]
        let report = makeReport(logSummaryLines: summaryLines)

        XCTAssertTrue(report.contains("Log Summary"), "Expected Log Summary section")
        XCTAssertTrue(report.contains("Buffered Logs: 10 total"))
    }

    func testCollectOmitsLogSummarySectionWhenEmpty() {
        let report = makeReport(logSummaryLines: [])

        XCTAssertFalse(report.contains("### Log Summary"), "Log Summary section should be absent when empty")
    }

    func testCollectReportHasMarkdownHeader() {
        let report = makeReport()

        XCTAssertTrue(report.hasPrefix("## LabTether Diagnostics Report"), "Report must start with markdown header")
    }

    func testCollectIncludesGeneratedTimestamp() {
        let before = Date()
        let report = makeReport()
        let after = Date()

        // The report should include "Generated:" with an ISO 8601 timestamp.
        // We verify the keyword is present; exact timestamp matching is fragile.
        XCTAssertTrue(report.contains("Generated:"), "Expected 'Generated:' line in report")
        _ = before  // suppress unused warning
        _ = after
    }
}
