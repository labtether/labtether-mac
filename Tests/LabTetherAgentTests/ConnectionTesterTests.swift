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

    func testHTTPBaseURLStripsWebSocketPath() {
        XCTAssertEqual(
            ConnectionTester.httpBaseURL(from: "wss://hub.example.com/ws/agent"),
            URL(string: "https://hub.example.com")
        )
    }

    func testHTTPBaseURLRejectsQueryOrFragment() {
        XCTAssertNil(ConnectionTester.httpBaseURL(from: "wss://hub.example.com/ws/agent?foo=bar"))
        XCTAssertNil(ConnectionTester.httpBaseURL(from: "wss://hub.example.com/ws/agent#frag"))
    }

    func testHTTPBaseURLRejectsUserInformation() {
        XCTAssertNil(ConnectionTester.httpBaseURL(from: "wss://user:secret@hub.example.com/ws/agent"))
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
        XCTAssertNil(ConnectionTester.httpBaseURL(from: "not a url"))
    }

    func testHTTPBaseURLCanonicalizesHTTPSchemeInputs() {
        XCTAssertEqual(
            ConnectionTester.httpBaseURL(from: "http://example.com/path"),
            URL(string: "http://example.com")
        )
        XCTAssertEqual(
            ConnectionTester.httpBaseURL(from: "https://example.com/path"),
            URL(string: "https://example.com")
        )
    }

    func testHTTPBaseURLCanonicalizesBareHostInput() {
        XCTAssertEqual(
            ConnectionTester.httpBaseURL(from: "hub.example.com:8443"),
            URL(string: "https://hub.example.com:8443")
        )
    }

    func testHTTPBaseURLWithoutPortProducesNoPort() {
        let result = ConnectionTester.httpBaseURL(from: "wss://hub.example.com/ws/agent")
        XCTAssertEqual(result, URL(string: "https://hub.example.com"))
        XCTAssertNil(result.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.port })
    }

    // MARK: - Hub identity URL

    func testHubIdentityURLUsesPublicDiscoveryRouteForDirectOrigin() {
        XCTAssertEqual(
            ConnectionTester.hubIdentityURL(from: "wss://hub.example.com:8443/ws/agent"),
            URL(string: "https://hub.example.com:8443/api/v1/discover")
        )
    }

    func testHubIdentityURLUsesPublicDiscoveryRouteForUnifiedConsoleOrigin() {
        XCTAssertEqual(
            ConnectionTester.hubIdentityURL(from: "ws://127.0.0.1:23000/ws/agent"),
            URL(string: "http://127.0.0.1:23000/api/v1/discover")
        )
    }

    // MARK: - Hub identity response

    func testHubIdentityValidationAcceptsLegacyDirectRootResponse() throws {
        let body = try XCTUnwrap("{\"service\":\"labtether-hub\",\"message\":\"running\"}".data(using: .utf8))

        XCTAssertNil(ConnectionTester.hubIdentityValidationError(statusCode: 200, body: body))
    }

    func testHubIdentityValidationAcceptsCanonicalDiscoveryResponse() throws {
        let body = try XCTUnwrap(
            """
            {
              "hub": "labtether",
              "hub_ws_url": "ws://127.0.0.1:23000/ws/agent",
              "enroll_url": "http://127.0.0.1:23000/api/v1/enroll"
            }
            """.data(using: .utf8)
        )

        XCTAssertNil(ConnectionTester.hubIdentityValidationError(statusCode: 200, body: body))
    }

    func testHubIdentityValidationRejectsEveryNon200Response() throws {
        let body = try XCTUnwrap("{\"service\":\"labtether-hub\"}".data(using: .utf8))

        for statusCode in [201, 302, 401, 404, 500] {
            let error = ConnectionTester.hubIdentityValidationError(statusCode: statusCode, body: body)
            XCTAssertEqual(error, "Hub verification failed (HTTP \(statusCode)).")
        }
    }

    func testHubIdentityValidationRejectsUnrelatedAndMalformedEndpoints() throws {
        let unrelated = try XCTUnwrap("{\"service\":\"something-else\"}".data(using: .utf8))
        let missingService = try XCTUnwrap("{\"status\":\"ok\"}".data(using: .utf8))
        let malformed = try XCTUnwrap("not-json".data(using: .utf8))
        let malformedDiscovery = try XCTUnwrap(
            """
            {
              "hub": "labtether",
              "hub_ws_url": "https://hub.example.com/not-websocket",
              "enroll_url": "https://hub.example.com/not-enroll"
            }
            """.data(using: .utf8)
        )

        XCTAssertNotNil(ConnectionTester.hubIdentityValidationError(statusCode: 200, body: unrelated))
        XCTAssertNotNil(ConnectionTester.hubIdentityValidationError(statusCode: 200, body: missingService))
        XCTAssertNotNil(ConnectionTester.hubIdentityValidationError(statusCode: 200, body: malformed))
        XCTAssertNotNil(ConnectionTester.hubIdentityValidationError(statusCode: 200, body: malformedDiscovery))
    }

    func testHubIdentityValidationRejectsOversizedResponse() {
        let oversized = Data(repeating: 0x61, count: ConnectionTester.maxProbeBodyBytes + 1)
        let canonical = Data("{\"service\":\"labtether-hub\"}".utf8)

        XCTAssertEqual(
            ConnectionTester.hubIdentityValidationError(statusCode: 200, body: oversized),
            "Hub verification response is too large."
        )
        XCTAssertEqual(
            ConnectionTester.hubIdentityValidationError(
                statusCode: 200,
                expectedContentLength: Int64(ConnectionTester.maxProbeBodyBytes + 1),
                body: canonical
            ),
            "Hub verification response is too large."
        )
    }

    func testHubIdentityValidationRejectsNonHTTPResponse() {
        XCTAssertNotNil(ConnectionTester.hubIdentityValidationError(statusCode: nil, body: Data()))
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

    func testFormatDiagnosticsReportRedactsCredentialsQueryAndFragment() {
        let report = ConnectionTester.formatDiagnosticsReport(
            [],
            hubURL: "wss://user:secret@hub.example.com/ws/agent?token=also-secret#fragment"
        )

        XCTAssertTrue(report.contains("wss://hub.example.com/ws/agent"))
        XCTAssertFalse(report.contains("user"))
        XCTAssertFalse(report.contains("secret"))
        XCTAssertFalse(report.contains("token"))
        XCTAssertFalse(report.contains("fragment"))
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
