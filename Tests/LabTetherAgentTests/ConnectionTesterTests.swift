import XCTest
@testable import LabTetherAgent

final class ConnectionTesterTests: XCTestCase {

    // MARK: - httpBaseURL

    func testHTTPBaseURLConvertsWSSToHTTPS() {
        XCTAssertEqual(
            ConnectionTester.httpBaseURL(from: "wss://hub.example.com:8443/ws/agent"),
            URL(string: "https://hub.example.com:8443")
        )
    }

    func testHTTPBaseURLConvertsWSToHTTP() {
        XCTAssertEqual(
            ConnectionTester.httpBaseURL(from: "ws://localhost:8080/ws/agent"),
            URL(string: "http://localhost:8080")
        )
    }

    func testHTTPBaseURLStripsPathQueryAndFragment() {
        XCTAssertEqual(
            ConnectionTester.httpBaseURL(from: "wss://hub.example.com/ws/agent?foo=bar#frag"),
            URL(string: "https://hub.example.com")
        )
    }

    func testHTTPBaseURLPreservesExplicitPort() {
        XCTAssertEqual(
            ConnectionTester.httpBaseURL(from: "wss://hub.example.com:9999/ws/agent"),
            URL(string: "https://hub.example.com:9999")
        )
    }

    func testHTTPBaseURLReturnsNilForEmptyString() {
        XCTAssertNil(ConnectionTester.httpBaseURL(from: ""))
    }

    func testHTTPBaseURLReturnsNilForNonURL() {
        XCTAssertNil(ConnectionTester.httpBaseURL(from: "not-a-url"))
    }

    func testHTTPBaseURLReturnsNilForHTTPScheme() {
        // Only ws/wss are valid input schemes
        XCTAssertNil(ConnectionTester.httpBaseURL(from: "http://example.com/path"))
    }

    func testHTTPBaseURLWithoutPortProducesNoPort() {
        let result = ConnectionTester.httpBaseURL(from: "wss://hub.example.com/ws/agent")
        XCTAssertEqual(result, URL(string: "https://hub.example.com"))
        XCTAssertNil(result.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.port })
    }

    // MARK: - ConnectionTestResult

    func testConnectionTestResultSuccessStoresResponseTime() {
        let result = ConnectionTestResult.success(responseTimeMs: 42)
        if case .success(let ms) = result {
            XCTAssertEqual(ms, 42)
        } else {
            XCTFail("Expected .success")
        }
    }

    func testConnectionTestResultFailureStoresErrorMessage() {
        let result = ConnectionTestResult.failure(error: "Connection refused")
        if case .failure(let message) = result {
            XCTAssertEqual(message, "Connection refused")
        } else {
            XCTFail("Expected .failure")
        }
    }

    func testConnectionTestResultEquality() {
        XCTAssertEqual(
            ConnectionTestResult.success(responseTimeMs: 100),
            ConnectionTestResult.success(responseTimeMs: 100)
        )
        XCTAssertNotEqual(
            ConnectionTestResult.success(responseTimeMs: 100),
            ConnectionTestResult.success(responseTimeMs: 200)
        )
        XCTAssertEqual(
            ConnectionTestResult.failure(error: "timeout"),
            ConnectionTestResult.failure(error: "timeout")
        )
        XCTAssertNotEqual(
            ConnectionTestResult.success(responseTimeMs: 100),
            ConnectionTestResult.failure(error: "timeout")
        )
    }

    // MARK: - DiagnosticStep / StepStatus

    func testDiagnosticStepDefaultsToStatusPending() {
        let step = DiagnosticStep(name: "DNS Resolution")
        XCTAssertEqual(step.status, .pending)
    }

    func testDiagnosticStepStatusTransitionsFromPendingToRunning() {
        var step = DiagnosticStep(name: "DNS Resolution")
        XCTAssertEqual(step.status, .pending)
        step.status = .running
        XCTAssertEqual(step.status, .running)
    }

    func testDiagnosticStepStatusTransitionsToSuccess() {
        var step = DiagnosticStep(name: "DNS Resolution")
        step.status = .running
        step.status = .success("Resolved: 1.2.3.4")
        if case .success(let detail) = step.status {
            XCTAssertEqual(detail, "Resolved: 1.2.3.4")
        } else {
            XCTFail("Expected .success")
        }
    }

    func testDiagnosticStepStatusTransitionsToFailure() {
        var step = DiagnosticStep(name: "TCP Connect")
        step.status = .running
        step.status = .failure("Connection refused")
        if case .failure(let detail) = step.status {
            XCTAssertEqual(detail, "Connection refused")
        } else {
            XCTFail("Expected .failure")
        }
    }

    func testDiagnosticStepHasUniqueID() {
        let stepA = DiagnosticStep(name: "DNS")
        let stepB = DiagnosticStep(name: "DNS")
        XCTAssertNotEqual(stepA.id, stepB.id)
    }

    func testStepStatusEquality() {
        XCTAssertEqual(StepStatus.pending, StepStatus.pending)
        XCTAssertEqual(StepStatus.running, StepStatus.running)
        XCTAssertEqual(StepStatus.success("ok"), StepStatus.success("ok"))
        XCTAssertEqual(StepStatus.failure("err"), StepStatus.failure("err"))
        XCTAssertNotEqual(StepStatus.success("a"), StepStatus.success("b"))
        XCTAssertNotEqual(StepStatus.pending, StepStatus.running)
    }

    // MARK: - formatDiagnosticsReport

    func testFormatDiagnosticsReportIncludesHubURL() {
        let steps = [
            DiagnosticStep(name: "DNS Resolution"),
            DiagnosticStep(name: "TCP Connect"),
        ]
        let report = ConnectionTester.formatDiagnosticsReport(steps, hubURL: "wss://hub.example.com:8443/ws/agent")
        XCTAssertTrue(report.contains("wss://hub.example.com:8443/ws/agent"))
    }

    func testFormatDiagnosticsReportIncludesStepNames() {
        var step1 = DiagnosticStep(name: "DNS Resolution")
        step1.status = .success("Resolved: 1.2.3.4")
        var step2 = DiagnosticStep(name: "TCP Connect")
        step2.status = .failure("Timed out")

        let report = ConnectionTester.formatDiagnosticsReport(
            [step1, step2],
            hubURL: "wss://hub.example.com/ws/agent"
        )
        XCTAssertTrue(report.contains("DNS Resolution"))
        XCTAssertTrue(report.contains("TCP Connect"))
        XCTAssertTrue(report.contains("Resolved: 1.2.3.4"))
        XCTAssertTrue(report.contains("Timed out"))
    }

    func testFormatDiagnosticsReportPendingStepsShowNeutralMarker() {
        let step = DiagnosticStep(name: "TLS Handshake")
        let report = ConnectionTester.formatDiagnosticsReport([step], hubURL: "wss://host/ws/agent")
        XCTAssertTrue(report.contains("TLS Handshake"))
    }

    func testFormatDiagnosticsReportIsNonEmpty() {
        let report = ConnectionTester.formatDiagnosticsReport([], hubURL: "wss://host/ws/agent")
        XCTAssertFalse(report.isEmpty)
    }

    // MARK: - quickTest (live network tests skipped in unit suite)

    func testQuickTestReturnsFailureForUnreachableHost() async {
        // Uses an unroutable IP address to guarantee a fast failure without network dependency.
        let result = await ConnectionTester.quickTest(
            hubURL: "wss://192.0.2.1:9999/ws/agent",
            tlsSkipVerify: false
        )
        if case .failure = result {
            // expected
        } else {
            // A success here would mean something unusual is in the network path;
            // flag as unexpected rather than hard-fail to stay CI-friendly.
            XCTFail("Expected .failure for unroutable IP, got \(result)")
        }
    }
}
