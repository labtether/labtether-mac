# User-Facing Essentials Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add onboarding wizard, connection testing, connection diagnostics, About window, and Copy Diagnostics extraction to the LabTether Mac Agent.

**Architecture:** Standalone SwiftUI windows following existing MVVM + `@ObservableObject` patterns. New services (`ConnectionTester`, `DiagnosticsCollector`) are stateless/actor-based. All views use the existing `LT` design token system. No new external dependencies.

**Tech Stack:** Swift 5.9+, SwiftUI, macOS 13+, Network framework, XCTest

**Spec:** `docs/superpowers/specs/2026-03-15-user-facing-essentials-design.md`

---

## Chunk 1: Foundation Services

### Task 1: Add `agentVersion` to `LocalAPIMetadataSnapshot`

**Files:**
- Modify: `Sources/LabTetherAgent/API/LocalAPIClient.swift:78-84` (add field to snapshot struct)
- Modify: `Sources/LabTetherAgent/API/LocalAPIClient.swift:279-286` (pass field in publish call)
- Test: `Tests/LabTetherAgentTests/LocalAPIClientTests.swift`

- [ ] **Step 1: Write failing test**

Add to `LocalAPIClientTests.swift`:

```swift
func testSuccessfulPollPublishesAgentVersion() {
    let client = LocalAPIClient()
    let status = makeStatus(connectionState: "connected", connected: true)

    client.applySuccessfulPollResult(status)

    XCTAssertEqual(client.metadata.snapshot.agentVersion, "1.0.0")
}

func testPollFailureClearsAgentVersion() {
    let client = LocalAPIClient()
    let status = makeStatus(connectionState: "connected", connected: true)

    client.applySuccessfulPollResult(status)
    client.applyPollFailure()

    XCTAssertNil(client.metadata.snapshot.agentVersion)
}
```

Also update the existing `makeStatus` helper to accept an `agentVersion` parameter by adding it to the function signature:

```swift
// Add agentVersion parameter with default:
private func makeStatus(
    connectionState: String,
    connected: Bool,
    alerts: [AlertSnapshot] = [],
    updateAvailable: Bool = false,
    agentVersion: String? = "1.0.0"  // add this parameter
) -> AgentStatusResponse {
    // ... existing body, passing agentVersion: agentVersion
```
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LocalAPIClientTests 2>&1 | tail -20`
Expected: Compilation error — `agentVersion` does not exist on `LocalAPIMetadataSnapshot`

- [ ] **Step 3: Add `agentVersion` to `LocalAPIMetadataSnapshot`**

In `LocalAPIClient.swift`, modify the struct at line 78. Add `agentVersion` as the first field only — keep all other existing fields and types unchanged (note: `localAuthEnabled` and `allowInsecureTransport` are `Bool?` optional in the existing code):

```swift
struct LocalAPIMetadataSnapshot: Equatable {
    var agentVersion: String?
    var updateAvailable = false
    var latestVersion: String?
    var deviceFingerprint: String?
    var localBindAddress: String?
    var localAuthEnabled: Bool?
    var allowInsecureTransport: Bool?
}
```

Then in `applyStatusSnapshot` at line 279, add `agentVersion` to the publish call:

```swift
metadata.publish(
    LocalAPIMetadataSnapshot(
        agentVersion: decoded.agentVersion,
        updateAvailable: decoded.updateAvailable ?? false,
        latestVersion: decoded.latestVersion,
        deviceFingerprint: decoded.deviceFingerprint,
        localBindAddress: decoded.localBindAddress,
        localAuthEnabled: decoded.localAuthEnabled,
        allowInsecureTransport: decoded.allowInsecureTransport
    )
)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LocalAPIClientTests 2>&1 | tail -20`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/LabTetherAgent/API/LocalAPIClient.swift Tests/LabTetherAgentTests/LocalAPIClientTests.swift
git commit -m "feat: forward agentVersion from API response to metadata snapshot"
```

---

### Task 2: Extract `DiagnosticsCollector` service

**Files:**
- Create: `Sources/LabTetherAgent/Services/DiagnosticsCollector.swift`
- Modify: `Sources/LabTetherAgent/Views/MenuBar/MenuBarView.swift:134-172` (refactor `copyDiagnostics`)
- Test: `Tests/LabTetherAgentTests/DiagnosticsCollectorTests.swift`

- [ ] **Step 1: Write failing test**

Create `Tests/LabTetherAgentTests/DiagnosticsCollectorTests.swift`:

```swift
import XCTest
@testable import LabTetherAgent

final class DiagnosticsCollectorTests: XCTestCase {
    func testCollectIncludesAppVersionAndOSVersion() {
        let report = DiagnosticsCollector.collect(
            appVersion: "2.1.0",
            buildNumber: "42",
            agentVersion: "1.0.0",
            osVersion: "macOS 15.3",
            architecture: "arm64",
            hubURL: "wss://hub.example.com/ws/agent",
            connectionState: "connected",
            apiTokenConfigured: true,
            enrollmentTokenConfigured: false,
            assetID: "mac-01",
            groupID: "lab-a",
            pid: 12345,
            uptime: "3h 12m",
            tlsSkipVerify: false,
            dockerMode: "auto",
            filesRootMode: "home",
            allowRemoteOverrides: false,
            logLevel: "info",
            webrtcEnabled: false,
            screenSharingEnabled: true,
            screenSharingControlAccess: true,
            validationErrors: [],
            secretPersistenceErrors: [],
            logSummaryLines: ["Buffered Logs: 50 total", "  Errors: 2, Warnings: 5, Info: 43"]
        )

        XCTAssertTrue(report.contains("2.1.0"))
        XCTAssertTrue(report.contains("(42)"))
        XCTAssertTrue(report.contains("macOS 15.3"))
        XCTAssertTrue(report.contains("arm64"))
        XCTAssertTrue(report.contains("1.0.0"))
    }

    func testCollectMasksTokenValues() {
        let report = DiagnosticsCollector.collect(
            appVersion: "1.0.0",
            buildNumber: "1",
            agentVersion: nil,
            osVersion: "macOS 15.3",
            architecture: "arm64",
            hubURL: "wss://hub.example.com/ws/agent",
            connectionState: "stopped",
            apiTokenConfigured: true,
            enrollmentTokenConfigured: true,
            assetID: "",
            groupID: "",
            pid: nil,
            uptime: nil,
            tlsSkipVerify: false,
            dockerMode: "auto",
            filesRootMode: "home",
            allowRemoteOverrides: false,
            logLevel: "info",
            webrtcEnabled: false,
            screenSharingEnabled: false,
            screenSharingControlAccess: false,
            validationErrors: [],
            secretPersistenceErrors: [],
            logSummaryLines: []
        )

        XCTAssertTrue(report.contains("API Token: configured"))
        XCTAssertTrue(report.contains("Enrollment Token: configured"))
        XCTAssertFalse(report.contains("secret"))
    }

    func testCollectIncludesValidationErrors() {
        let report = DiagnosticsCollector.collect(
            appVersion: "1.0.0",
            buildNumber: "1",
            agentVersion: nil,
            osVersion: "macOS 15.3",
            architecture: "arm64",
            hubURL: "",
            connectionState: "stopped",
            apiTokenConfigured: false,
            enrollmentTokenConfigured: false,
            assetID: "",
            groupID: "",
            pid: nil,
            uptime: nil,
            tlsSkipVerify: false,
            dockerMode: "auto",
            filesRootMode: "home",
            allowRemoteOverrides: false,
            logLevel: "info",
            webrtcEnabled: false,
            screenSharingEnabled: false,
            screenSharingControlAccess: false,
            validationErrors: ["Hub URL is required."],
            secretPersistenceErrors: [],
            logSummaryLines: []
        )

        XCTAssertTrue(report.contains("Hub URL is required."))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DiagnosticsCollectorTests 2>&1 | tail -20`
Expected: Compilation error — `DiagnosticsCollector` not found

- [ ] **Step 3: Create `DiagnosticsCollector`**

Create `Sources/LabTetherAgent/Services/DiagnosticsCollector.swift`:

```swift
import Foundation

/// Builds a diagnostics report string from application state.
/// All parameters are plain values — no dependency on observable objects.
enum DiagnosticsCollector {
    static func collect(
        appVersion: String,
        buildNumber: String,
        agentVersion: String?,
        osVersion: String,
        architecture: String,
        hubURL: String,
        connectionState: String,
        apiTokenConfigured: Bool,
        enrollmentTokenConfigured: Bool,
        assetID: String,
        groupID: String,
        pid: Int32?,
        uptime: String?,
        tlsSkipVerify: Bool,
        dockerMode: String,
        filesRootMode: String,
        allowRemoteOverrides: Bool,
        logLevel: String,
        webrtcEnabled: Bool,
        screenSharingEnabled: Bool,
        screenSharingControlAccess: Bool,
        validationErrors: [String],
        secretPersistenceErrors: [String],
        logSummaryLines: [String]
    ) -> String {
        var lines: [String] = []

        lines.append("## LabTether Diagnostics Report")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")

        // Application
        lines.append("### Application")
        lines.append("- App Version: \(appVersion) (\(buildNumber))")
        lines.append("- Agent Version: \(agentVersion ?? "Not running")")
        lines.append("- OS: \(osVersion) (\(architecture))")
        lines.append("")

        // Connection
        lines.append("### Connection")
        lines.append("- Hub URL: \(hubURL.isEmpty ? "(not set)" : hubURL)")
        lines.append("- Connection State: \(connectionState)")
        lines.append("- API Token: \(apiTokenConfigured ? "configured" : "not configured")")
        lines.append("- Enrollment Token: \(enrollmentTokenConfigured ? "configured" : "not configured")")
        lines.append("- Asset ID: \(assetID.isEmpty ? "(auto)" : assetID)")
        lines.append("- Group ID: \(groupID.isEmpty ? "(none)" : groupID)")
        if let pid {
            lines.append("- PID: \(pid)")
        }
        if let uptime {
            lines.append("- Uptime: \(uptime)")
        }
        lines.append("")

        // Configuration
        lines.append("### Configuration")
        lines.append("- TLS Skip Verify: \(tlsSkipVerify)")
        lines.append("- Docker Mode: \(dockerMode)")
        lines.append("- Files Root Mode: \(filesRootMode)")
        lines.append("- Allow Remote Overrides: \(allowRemoteOverrides)")
        lines.append("- Log Level: \(logLevel)")
        lines.append("- WebRTC Enabled: \(webrtcEnabled)")
        lines.append("")

        // Screen Sharing
        lines.append("### Screen Sharing")
        lines.append("- Status: \(screenSharingEnabled ? "enabled" : "disabled")")
        lines.append("- Control Access: \(screenSharingControlAccess ? "full control" : "observe-only or none")")
        lines.append("")

        // Issues
        if !validationErrors.isEmpty || !secretPersistenceErrors.isEmpty {
            lines.append("### Issues")
            for error in validationErrors {
                lines.append("- Validation: \(error)")
            }
            for error in secretPersistenceErrors {
                lines.append("- Secret: \(error)")
            }
            lines.append("")
        }

        // Log Summary
        if !logSummaryLines.isEmpty {
            lines.append("### Log Summary")
            for line in logSummaryLines {
                lines.append(line)
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter DiagnosticsCollectorTests 2>&1 | tail -20`
Expected: All 3 tests PASS

- [ ] **Step 5: Add `architecture` property to `BundleHelper`**

In `BundleHelper.swift`, add after `buildNumber`:

```swift
/// CPU architecture (e.g. "arm64", "x86_64").
static var architecture: String {
    var sysinfo = utsname()
    uname(&sysinfo)
    return withUnsafePointer(to: &sysinfo.machine) {
        $0.withMemoryRebound(to: CChar.self, capacity: 1) {
            String(cString: $0)
        }
    }
}
```

- [ ] **Step 6: Refactor `MenuBarView.copyDiagnostics()` to use `DiagnosticsCollector`**

In `MenuBarView.swift`, replace the `copyDiagnostics()` method (lines 134-172) and remove the `diagnosticsHubSummary` computed property (lines 174-187). Replace with:

```swift
private func copyDiagnostics() {
    let logSummary = DiagnosticsLogSummary(logLines: logBuffer.logLines)
    let report = DiagnosticsCollector.collect(
        appVersion: BundleHelper.appVersion,
        buildNumber: BundleHelper.buildNumber,
        agentVersion: apiClient.metadata.snapshot.agentVersion,
        osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
        architecture: BundleHelper.architecture,
        hubURL: settings.hubURL,
        connectionState: status.state.rawValue,
        apiTokenConfigured: !settings.apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        enrollmentTokenConfigured: !settings.enrollmentToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        assetID: status.assetID.isEmpty ? settings.assetID : status.assetID,
        groupID: settings.groupID,
        pid: status.pid,
        uptime: status.uptime,
        tlsSkipVerify: settings.tlsSkipVerify,
        dockerMode: settings.normalizedDockerMode(),
        filesRootMode: settings.normalizedFilesRootMode(),
        allowRemoteOverrides: settings.allowRemoteOverrides,
        logLevel: settings.normalizedLogLevel(),
        webrtcEnabled: settings.effectiveWebRTCEnabled,
        screenSharingEnabled: screenSharing.isEnabled,
        screenSharingControlAccess: screenSharing.hasControlAccess,
        validationErrors: settings.validationErrors(),
        secretPersistenceErrors: settings.secretPersistenceErrors,
        logSummaryLines: logSummary.reportLines
    )
    copyToClipboard(report, label: "Diagnostics")
}
```

`MenuBarView` already has access to `screenSharing: ScreenSharingMonitor` (line 7), `status: AgentStatus` (line 4), and all other needed objects.

- [ ] **Step 7: Run full test suite**

Run: `swift test 2>&1 | tail -20`
Expected: All tests PASS

- [ ] **Step 8: Commit**

```bash
git add Sources/LabTetherAgent/Services/DiagnosticsCollector.swift \
  Tests/LabTetherAgentTests/DiagnosticsCollectorTests.swift \
  Sources/LabTetherAgent/Views/MenuBar/MenuBarView.swift \
  Sources/LabTetherAgent/App/BundleHelper.swift
git commit -m "refactor: extract DiagnosticsCollector from inline copyDiagnostics"
```

---

### Task 3: Create `ConnectionTester` service

**Files:**
- Create: `Sources/LabTetherAgent/Services/ConnectionTester.swift`
- Test: `Tests/LabTetherAgentTests/ConnectionTesterTests.swift`

- [ ] **Step 1: Write failing test for result model and URL derivation**

Create `Tests/LabTetherAgentTests/ConnectionTesterTests.swift`:

```swift
import XCTest
@testable import LabTetherAgent

final class ConnectionTesterTests: XCTestCase {
    func testDeriveHTTPBaseURLFromWebSocketURL() {
        XCTAssertEqual(
            ConnectionTester.httpBaseURL(from: "wss://hub.example.com:8443/ws/agent"),
            URL(string: "https://hub.example.com:8443")
        )
        XCTAssertEqual(
            ConnectionTester.httpBaseURL(from: "ws://localhost:8080/ws/agent"),
            URL(string: "http://localhost:8080")
        )
        XCTAssertNil(ConnectionTester.httpBaseURL(from: ""))
        XCTAssertNil(ConnectionTester.httpBaseURL(from: "not-a-url"))
    }

    func testQuickTestResultTypes() {
        let success = ConnectionTestResult.success(responseTimeMs: 42)
        let failure = ConnectionTestResult.failure(error: "Connection refused")

        switch success {
        case .success(let ms): XCTAssertEqual(ms, 42)
        case .failure: XCTFail("Expected success")
        }

        switch failure {
        case .success: XCTFail("Expected failure")
        case .failure(let err): XCTAssertEqual(err, "Connection refused")
        }
    }

    func testDiagnosticStepStatusTransitions() {
        var step = DiagnosticStep(name: "DNS Resolution")
        XCTAssertEqual(step.status, .pending)

        step.status = .running
        XCTAssertEqual(step.status, .running)

        step.status = .success("Resolved: 1.2.3.4")
        if case .success(let detail) = step.status {
            XCTAssertEqual(detail, "Resolved: 1.2.3.4")
        } else {
            XCTFail("Expected success")
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ConnectionTesterTests 2>&1 | tail -20`
Expected: Compilation error — `ConnectionTester` not found

- [ ] **Step 3: Create `ConnectionTester`**

Create `Sources/LabTetherAgent/Services/ConnectionTester.swift`:

```swift
import Foundation
import Network

/// Result of a quick connection test.
enum ConnectionTestResult: Equatable {
    case success(responseTimeMs: Int)
    case failure(error: String)
}

/// Status of a single diagnostic step.
enum StepStatus: Equatable {
    case pending
    case running
    case success(String)
    case failure(String)
}

/// A single step in a full connection diagnostic.
struct DiagnosticStep: Identifiable {
    let id = UUID()
    let name: String
    var status: StepStatus = .pending
}

/// Tests connectivity to the LabTether hub.
enum ConnectionTester {

    /// Derive an HTTP base URL from a WebSocket URL string.
    static func httpBaseURL(from wsURLString: String) -> URL? {
        let trimmed = wsURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var urlString = trimmed
        urlString = urlString.replacingOccurrences(of: "wss://", with: "https://")
        urlString = urlString.replacingOccurrences(of: "ws://", with: "http://")

        guard let url = URL(string: urlString),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = ""
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    /// Quick connectivity check — HTTP GET to the hub base URL.
    /// Returns success with response time or failure with error description.
    static func quickTest(hubURL: String, tlsSkipVerify: Bool = false) async -> ConnectionTestResult {
        guard let url = httpBaseURL(from: hubURL) else {
            return .failure(error: "Invalid hub URL")
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        let session: URLSession
        if tlsSkipVerify {
            session = URLSession(configuration: config, delegate: TLSSkipDelegate(), delegateQueue: nil)
        } else {
            session = URLSession(configuration: config)
        }
        defer { session.invalidateAndCancel() }

        let start = CFAbsoluteTimeGetCurrent()
        do {
            let (_, response) = try await session.data(from: url)
            let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            if let http = response as? HTTPURLResponse, (200..<500).contains(http.statusCode) {
                return .success(responseTimeMs: elapsed)
            }
            return .failure(error: "Unexpected response")
        } catch {
            return .failure(error: error.localizedDescription)
        }
    }

    /// Run full connection diagnostics — DNS, TCP, TLS, HTTP.
    /// Calls `onUpdate` after each step completes so the UI can show progress.
    static func fullDiagnostics(
        hubURL: String,
        tlsSkipVerify: Bool = false,
        onUpdate: @escaping ([DiagnosticStep]) -> Void
    ) async {
        guard let url = httpBaseURL(from: hubURL),
              let host = url.host else {
            var steps = [DiagnosticStep(name: "URL Parsing")]
            steps[0].status = .failure("Invalid hub URL")
            onUpdate(steps)
            return
        }
        let port = url.port ?? (url.scheme == "https" ? 443 : 80)
        let isSecure = url.scheme == "https"

        var steps = [
            DiagnosticStep(name: "DNS Resolution"),
            DiagnosticStep(name: "TCP Connection"),
            DiagnosticStep(name: "TLS Handshake"),
            DiagnosticStep(name: "HTTP Reachability"),
        ]

        // Step 1: DNS
        steps[0].status = .running
        onUpdate(steps)
        let dnsResult = await resolveDNS(host: host)
        steps[0].status = dnsResult
        onUpdate(steps)
        if case .failure = dnsResult { return }

        // Step 2: TCP
        steps[1].status = .running
        onUpdate(steps)
        let tcpResult = await checkTCP(host: host, port: port)
        steps[1].status = tcpResult
        onUpdate(steps)
        if case .failure = tcpResult { return }

        // Step 3: TLS
        if isSecure {
            steps[2].status = .running
            onUpdate(steps)
            let tlsResult = await checkTLS(host: host, port: port, skipVerify: tlsSkipVerify)
            steps[2].status = tlsResult
            onUpdate(steps)
            if case .failure = tlsResult { return }
        } else {
            steps[2].status = .success("Not applicable (HTTP)")
            onUpdate(steps)
        }

        // Step 4: HTTP
        steps[3].status = .running
        onUpdate(steps)
        let httpResult = await checkHTTP(url: url, tlsSkipVerify: tlsSkipVerify)
        steps[3].status = httpResult
        onUpdate(steps)
    }

    // MARK: - Private Diagnostic Steps

    private static func resolveDNS(host: String) async -> StepStatus {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                var hints = addrinfo()
                hints.ai_family = AF_UNSPEC
                hints.ai_socktype = SOCK_STREAM
                var result: UnsafeMutablePointer<addrinfo>?
                let status = getaddrinfo(host, nil, &hints, &result)
                defer { if let result { freeaddrinfo(result) } }

                if status != 0 {
                    let message = String(cString: gai_strerror(status))
                    continuation.resume(returning: .failure(message))
                    return
                }

                var addresses: [String] = []
                var current = result
                while let info = current {
                    var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen,
                                   &buffer, socklen_t(buffer.count),
                                   nil, 0, NI_NUMERICHOST) == 0 {
                        addresses.append(String(cString: buffer))
                    }
                    current = info.pointee.ai_next
                }
                let unique = Array(Set(addresses)).sorted()
                continuation.resume(returning: .success("Resolved: \(unique.joined(separator: ", "))"))
            }
        }
    }

    private static func checkTCP(host: String, port: Int) async -> StepStatus {
        await withCheckedContinuation { continuation in
            let nwHost = NWEndpoint.Host(host)
            let nwPort = NWEndpoint.Port(integerLiteral: UInt16(port))
            let connection = NWConnection(host: nwHost, port: nwPort, using: .tcp)
            let start = CFAbsoluteTimeGetCurrent()
            let resumed = OSAllocatedUnfairLock(initialState: false)

            func resumeOnce(_ result: StepStatus) {
                let alreadyResumed = resumed.withLock { val -> Bool in
                    let was = val; val = true; return was
                }
                guard !alreadyResumed else { return }
                connection.cancel()
                continuation.resume(returning: result)
            }

            let timeout = DispatchWorkItem {
                resumeOnce(.failure("Connection timed out (5s)"))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    timeout.cancel()
                    let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                    resumeOnce(.success("Connected in \(elapsed)ms"))
                case .failed(let error):
                    timeout.cancel()
                    resumeOnce(.failure(error.localizedDescription))
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }

    private static func checkTLS(host: String, port: Int, skipVerify: Bool) async -> StepStatus {
        await withCheckedContinuation { continuation in
            let tlsOptions = NWProtocolTLS.Options()
            if skipVerify {
                sec_protocol_options_set_verify_block(
                    tlsOptions.securityProtocolOptions,
                    { _, _, completionHandler in completionHandler(true) },
                    .global()
                )
            }
            let params = NWParameters(tls: tlsOptions)
            let nwHost = NWEndpoint.Host(host)
            let nwPort = NWEndpoint.Port(integerLiteral: UInt16(port))
            let connection = NWConnection(host: nwHost, port: nwPort, using: params)
            let resumed = OSAllocatedUnfairLock(initialState: false)

            func resumeOnce(_ result: StepStatus) {
                let alreadyResumed = resumed.withLock { val -> Bool in
                    let was = val; val = true; return was
                }
                guard !alreadyResumed else { return }
                connection.cancel()
                continuation.resume(returning: result)
            }

            let timeout = DispatchWorkItem {
                resumeOnce(.failure("TLS handshake timed out (5s)"))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    timeout.cancel()
                    resumeOnce(.success("TLS handshake successful"))
                case .failed(let error):
                    timeout.cancel()
                    resumeOnce(.failure(error.localizedDescription))
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }

    private static func checkHTTP(url: URL, tlsSkipVerify: Bool) async -> StepStatus {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        let session: URLSession
        if tlsSkipVerify {
            session = URLSession(configuration: config, delegate: TLSSkipDelegate(), delegateQueue: nil)
        } else {
            session = URLSession(configuration: config)
        }
        defer { session.invalidateAndCancel() }

        let start = CFAbsoluteTimeGetCurrent()
        do {
            let (_, response) = try await session.data(from: url)
            let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            if let http = response as? HTTPURLResponse {
                return .success("HTTP \(http.statusCode) in \(elapsed)ms")
            }
            return .failure("Unexpected response type")
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// Formats diagnostic steps as a copyable text report.
    static func formatDiagnosticsReport(_ steps: [DiagnosticStep], hubURL: String) -> String {
        var lines = ["Connection Diagnostics for \(hubURL)", ""]
        for step in steps {
            let icon: String
            let detail: String
            switch step.status {
            case .pending: icon = "○"; detail = "Not started"
            case .running: icon = "◉"; detail = "Running..."
            case .success(let msg): icon = "✓"; detail = msg
            case .failure(let msg): icon = "✗"; detail = msg
            }
            lines.append("\(icon) \(step.name): \(detail)")
        }
        return lines.joined(separator: "\n")
    }
}

/// URLSession delegate that skips TLS certificate verification.
private final class TLSSkipDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            return (.useCredential, URLCredential(trust: trust))
        }
        return (.performDefaultHandling, nil)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ConnectionTesterTests 2>&1 | tail -20`
Expected: All 3 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/LabTetherAgent/Services/ConnectionTester.swift \
  Tests/LabTetherAgentTests/ConnectionTesterTests.swift
git commit -m "feat: add ConnectionTester service for hub connectivity checks"
```

---

### Task 4: Add `hasCompletedOnboarding` and `shouldShowOnboarding` flag

**Files:**
- Modify: `Sources/LabTetherAgent/Settings/AgentSettings.swift` (add property)
- Modify: `Sources/LabTetherAgent/App/AppState.swift` (add flag + logic)

- [ ] **Step 1: Add `hasCompletedOnboarding` to `AgentSettings`**

In `AgentSettings.swift`, after line 79 (`startAtLogin`), add:

```swift
@AppStorage("hasCompletedOnboarding", store: settingsStore) var hasCompletedOnboarding: Bool = false
```

- [ ] **Step 2: Add `shouldShowOnboarding` to `AppState`**

In `AppState.swift`, add a published property:

```swift
@Published var shouldShowOnboarding = false
```

Then at the end of `init()`, after the existing auto-start logic, add:

```swift
// Trigger onboarding if not configured and hasn't been completed
if !settings.isConfigured && !settings.hasCompletedOnboarding {
    shouldShowOnboarding = true
}
```

- [ ] **Step 3: Build to verify compilation**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add Sources/LabTetherAgent/Settings/AgentSettings.swift \
  Sources/LabTetherAgent/App/AppState.swift
git commit -m "feat: add hasCompletedOnboarding flag and shouldShowOnboarding trigger"
```

---

## Chunk 2: UI Views

### Task 5: Create Onboarding Views

**Files:**
- Create: `Sources/LabTetherAgent/Views/Onboarding/OnboardingView.swift`
- Create: `Sources/LabTetherAgent/Views/Onboarding/OnboardingWelcomeStep.swift`
- Create: `Sources/LabTetherAgent/Views/Onboarding/OnboardingAuthStep.swift`
- Create: `Sources/LabTetherAgent/Views/Onboarding/OnboardingIdentityStep.swift`

- [ ] **Step 1: Create `OnboardingView.swift`**

```swift
import SwiftUI

/// Token type selection for onboarding authentication step.
enum OnboardingTokenType: String, CaseIterable {
    case enrollment = "Enrollment Token"
    case apiToken = "API Token"
}

/// Holds draft values during the onboarding wizard. Only writes to AgentSettings on finish.
@MainActor
final class OnboardingState: ObservableObject {
    @Published var hubURL: String
    @Published var tokenType: OnboardingTokenType = .enrollment
    @Published var tokenValue: String = ""
    @Published var assetID: String = ""
    @Published var groupID: String = ""
    @Published var currentStep: Int = 0
    @Published var connectionTestResult: ConnectionTestResult?
    @Published var isTesting: Bool = false

    init(defaultHubURL: String = "wss://localhost:8443/ws/agent") {
        self.hubURL = defaultHubURL
    }

    var canAdvanceFromStep0: Bool {
        !hubURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canAdvanceFromStep1: Bool {
        !tokenValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func testConnection(tlsSkipVerify: Bool) async {
        isTesting = true
        connectionTestResult = nil
        connectionTestResult = await ConnectionTester.quickTest(
            hubURL: hubURL,
            tlsSkipVerify: tlsSkipVerify
        )
        isTesting = false
    }

    func applyToSettings(_ settings: AgentSettings) {
        settings.hubURL = hubURL.trimmingCharacters(in: .whitespacesAndNewlines)
        switch tokenType {
        case .enrollment:
            settings.enrollmentToken = tokenValue.trimmingCharacters(in: .whitespacesAndNewlines)
        case .apiToken:
            settings.apiToken = tokenValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let trimmedAsset = assetID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAsset.isEmpty { settings.assetID = trimmedAsset }
        let trimmedGroup = groupID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedGroup.isEmpty { settings.groupID = trimmedGroup }
        settings.hasCompletedOnboarding = true
        settings.markChanged()
    }
}

/// Multi-step onboarding wizard for first-time setup.
struct OnboardingView: View {
    @ObservedObject var settings: AgentSettings
    @ObservedObject var agentProcess: AgentProcess
    @StateObject private var state = OnboardingState()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            HStack(spacing: LT.space8) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(index == state.currentStep ? LT.accent : Color.white.opacity(0.2))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, LT.space16)

            // Step content
            Group {
                switch state.currentStep {
                case 0:
                    OnboardingWelcomeStep(state: state)
                case 1:
                    OnboardingAuthStep(state: state)
                case 2:
                    OnboardingIdentityStep(
                        state: state,
                        settings: settings,
                        agentProcess: agentProcess,
                        onFinish: {
                            state.applyToSettings(settings)
                            agentProcess.start()
                            dismiss()
                        }
                    )
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Navigation
            HStack {
                if state.currentStep > 0 {
                    Button("Back") {
                        withAnimation(LT.springSmooth) {
                            state.currentStep -= 1
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(LT.textSecondary)
                }

                Spacer()

                if state.currentStep < 2 {
                    let canAdvance = state.currentStep == 0
                        ? state.canAdvanceFromStep0
                        : state.canAdvanceFromStep1
                    Button("Next") {
                        withAnimation(LT.springSmooth) {
                            state.currentStep += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(LT.accent)
                    .disabled(!canAdvance)
                }
            }
            .padding(LT.space20)
        }
        .frame(width: 500, height: 450)
        .background(LT.bg)
        .onAppear {
            state.hubURL = settings.hubURL
        }
    }
}
```

- [ ] **Step 2: Create `OnboardingWelcomeStep.swift`**

```swift
import SwiftUI

/// Step 1: Welcome message and Hub URL entry.
struct OnboardingWelcomeStep: View {
    @ObservedObject var state: OnboardingState

    var body: some View {
        VStack(spacing: LT.space16) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            Text("Welcome to LabTether")
                .font(LT.sora(22, weight: .semibold))
                .foregroundColor(LT.textPrimary)

            Text("Connect this Mac to your LabTether hub\nfor remote management.")
                .font(LT.inter(14))
                .foregroundColor(LT.textSecondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: LT.space6) {
                Text("HUB URL")
                    .font(LT.mono(10, weight: .medium))
                    .foregroundColor(LT.textMuted)

                HStack(spacing: LT.space6) {
                    TextField("wss://hub.example.com/ws/agent", text: $state.hubURL)
                        .textFieldStyle(.plain)
                        .font(LT.mono(13))
                        .foregroundColor(LT.textPrimary)
                        .padding(LT.space8)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(LT.radiusSm)

                    Button {
                        if let clip = NSPasteboard.general.string(forType: .string) {
                            state.hubURL = clip
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .foregroundColor(LT.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Paste from Clipboard")
                }
            }
            .padding(.horizontal, LT.space24)

            Spacer()
        }
    }
}
```

- [ ] **Step 3: Create `OnboardingAuthStep.swift`**

```swift
import SwiftUI

/// Step 2: Token type selection and entry.
struct OnboardingAuthStep: View {
    @ObservedObject var state: OnboardingState
    @State private var showToken = false

    var body: some View {
        VStack(spacing: LT.space16) {
            Spacer()

            Image(systemName: "key.fill")
                .font(.system(size: 40))
                .foregroundColor(LT.accent)

            Text("Authentication")
                .font(LT.sora(22, weight: .semibold))
                .foregroundColor(LT.textPrimary)

            Text("Use an enrollment token to register this device,\nor an API token if already enrolled.")
                .font(LT.inter(13))
                .foregroundColor(LT.textSecondary)
                .multilineTextAlignment(.center)

            Picker("", selection: $state.tokenType) {
                ForEach(OnboardingTokenType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, LT.space24)

            VStack(alignment: .leading, spacing: LT.space6) {
                Text(state.tokenType.rawValue.uppercased())
                    .font(LT.mono(10, weight: .medium))
                    .foregroundColor(LT.textMuted)

                HStack(spacing: LT.space6) {
                    Group {
                        if showToken {
                            TextField("Paste your token", text: $state.tokenValue)
                        } else {
                            SecureField("Paste your token", text: $state.tokenValue)
                        }
                    }
                    .textFieldStyle(.plain)
                    .font(LT.mono(13))
                    .foregroundColor(LT.textPrimary)
                    .padding(LT.space8)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(LT.radiusSm)

                    Button {
                        showToken.toggle()
                    } label: {
                        Image(systemName: showToken ? "eye.slash" : "eye")
                            .foregroundColor(LT.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, LT.space24)

            Spacer()
        }
    }
}
```

- [ ] **Step 4: Create `OnboardingIdentityStep.swift`**

```swift
import SwiftUI

/// Step 3: Optional identity fields and connection test.
struct OnboardingIdentityStep: View {
    @ObservedObject var state: OnboardingState
    @ObservedObject var settings: AgentSettings
    @ObservedObject var agentProcess: AgentProcess
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: LT.space16) {
            Spacer()

            Image(systemName: "person.badge.shield.checkmark.fill")
                .font(.system(size: 40))
                .foregroundColor(LT.accent)

            Text("Identity (Optional)")
                .font(LT.sora(22, weight: .semibold))
                .foregroundColor(LT.textPrimary)

            Text("Set an asset ID and group, or leave blank\nfor automatic detection.")
                .font(LT.inter(13))
                .foregroundColor(LT.textSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: LT.space12) {
                VStack(alignment: .leading, spacing: LT.space4) {
                    Text("ASSET ID")
                        .font(LT.mono(10, weight: .medium))
                        .foregroundColor(LT.textMuted)
                    TextField("Auto-detected from hostname", text: $state.assetID)
                        .textFieldStyle(.plain)
                        .font(LT.mono(13))
                        .foregroundColor(LT.textPrimary)
                        .padding(LT.space8)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(LT.radiusSm)
                }

                VStack(alignment: .leading, spacing: LT.space4) {
                    Text("GROUP ID")
                        .font(LT.mono(10, weight: .medium))
                        .foregroundColor(LT.textMuted)
                    TextField("Optional group assignment", text: $state.groupID)
                        .textFieldStyle(.plain)
                        .font(LT.mono(13))
                        .foregroundColor(LT.textPrimary)
                        .padding(LT.space8)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(LT.radiusSm)
                }
            }
            .padding(.horizontal, LT.space24)

            // Test Connection
            HStack(spacing: LT.space8) {
                Button {
                    Task { await state.testConnection(tlsSkipVerify: settings.tlsSkipVerify) }
                } label: {
                    HStack(spacing: LT.space6) {
                        if state.isTesting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                        }
                        Text("Test Connection")
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(LT.accent)
                .disabled(state.isTesting)

                if let result = state.connectionTestResult {
                    switch result {
                    case .success(let ms):
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(LT.ok)
                            Text("Connected (\(ms)ms)")
                                .font(LT.mono(11))
                                .foregroundColor(LT.ok)
                        }
                    case .failure(let error):
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(LT.bad)
                            Text(error)
                                .font(LT.mono(11))
                                .foregroundColor(LT.bad)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Spacer()

            // Finish button (replaces Next in navigation)
            Button {
                onFinish()
            } label: {
                Text("Finish & Start Agent")
                    .font(LT.inter(14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LT.space8)
            }
            .buttonStyle(.borderedProminent)
            .tint(LT.accent)
            .padding(.horizontal, LT.space24)
            .padding(.bottom, LT.space4)
        }
    }
}
```

- [ ] **Step 5: Build to verify compilation**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 6: Commit**

```bash
git add Sources/LabTetherAgent/Views/Onboarding/
git commit -m "feat: add onboarding wizard views (welcome, auth, identity steps)"
```

---

### Task 6: Create About Window

**Files:**
- Create: `Sources/LabTetherAgent/Views/About/AboutView.swift`

- [ ] **Step 1: Create `AboutView.swift`**

```swift
import SwiftUI

/// Standard About window showing app version, agent version, and system info.
struct AboutView: View {
    @ObservedObject var metadata: LocalAPIMetadataStore
    let deviceFingerprintPath: String

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    private var osVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    private var deviceFingerprint: String? {
        try? String(contentsOfFile: deviceFingerprintPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: LT.space12) {
            Spacer().frame(height: LT.space8)

            // App icon
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            // Title
            Text("LabTether Agent")
                .font(LT.sora(18, weight: .semibold))
                .foregroundColor(LT.textPrimary)

            // Version info
            VStack(spacing: LT.space4) {
                Text("Version \(appVersion) (\(buildNumber))")
                    .font(LT.mono(12))
                    .foregroundColor(LT.textSecondary)

                Text("Agent: \(metadata.snapshot.agentVersion ?? "Not running")")
                    .font(LT.mono(12))
                    .foregroundColor(LT.textSecondary)

                Text("macOS \(osVersion)")
                    .font(LT.mono(12))
                    .foregroundColor(LT.textMuted)
            }

            // Device fingerprint
            if let fp = deviceFingerprint, !fp.isEmpty {
                HStack(spacing: LT.space6) {
                    let truncated = fp.count > 16 ? String(fp.prefix(16)) + "..." : fp
                    Text("Device: \(truncated)")
                        .font(LT.mono(11))
                        .foregroundColor(LT.textMuted)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(fp, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundColor(LT.textMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Copy full fingerprint")
                }
            }

            Divider()
                .background(Color.white.opacity(0.1))
                .padding(.horizontal, LT.space24)

            // Links
            HStack(spacing: LT.space16) {
                if let url = URL(string: "https://labtether.com") {
                    Link("Website", destination: url)
                        .font(LT.inter(12))
                        .foregroundColor(LT.accent)
                }
                if let url = URL(string: "https://docs.labtether.com") {
                    Link("Documentation", destination: url)
                        .font(LT.inter(12))
                        .foregroundColor(LT.accent)
                }
                if let url = URL(string: "https://labtether.com/support") {
                    Link("Support", destination: url)
                        .font(LT.inter(12))
                        .foregroundColor(LT.accent)
                }
            }

            Text("\u{00A9} 2026 LabTether")
                .font(LT.inter(11))
                .foregroundColor(LT.textMuted)

            Spacer().frame(height: LT.space8)
        }
        .frame(width: 340, height: 380)
        .background(LT.bg)
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/LabTetherAgent/Views/About/AboutView.swift
git commit -m "feat: add About window showing version, agent, and system info"
```

---

### Task 7: Create Connection Diagnostics Sheet

**Files:**
- Create: `Sources/LabTetherAgent/Views/Settings/ConnectionDiagnosticsSheet.swift`

- [ ] **Step 1: Create `ConnectionDiagnosticsSheet.swift`**

```swift
import SwiftUI

/// Sheet that runs and displays full connection diagnostics step by step.
struct ConnectionDiagnosticsSheet: View {
    let hubURL: String
    let tlsSkipVerify: Bool
    @State private var steps: [DiagnosticStep] = []
    @State private var isRunning = false
    @State private var hasRun = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: LT.space16) {
            Text("Connection Diagnostics")
                .font(LT.sora(16, weight: .semibold))
                .foregroundColor(LT.textPrimary)

            Text(hubURL)
                .font(LT.mono(12))
                .foregroundColor(LT.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Divider().background(Color.white.opacity(0.1))

            if steps.isEmpty && !isRunning {
                Text("Press Run to start diagnostics.")
                    .font(LT.inter(13))
                    .foregroundColor(LT.textMuted)
            }

            ForEach(steps) { step in
                HStack(spacing: LT.space8) {
                    stepIcon(step.status)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.name)
                            .font(LT.inter(13, weight: .medium))
                            .foregroundColor(LT.textPrimary)

                        switch step.status {
                        case .success(let detail):
                            Text(detail)
                                .font(LT.mono(11))
                                .foregroundColor(LT.ok)
                        case .failure(let error):
                            Text(error)
                                .font(LT.mono(11))
                                .foregroundColor(LT.bad)
                        default:
                            EmptyView()
                        }
                    }

                    Spacer()
                }
            }

            Spacer()

            HStack {
                if hasRun {
                    Button("Copy Results") {
                        let report = ConnectionTester.formatDiagnosticsReport(steps, hubURL: hubURL)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(report, forType: .string)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(LT.accent)
                }

                Spacer()

                if !isRunning {
                    Button(hasRun ? "Re-run" : "Run") {
                        runDiagnostics()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(LT.accent)
                }

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(LT.textSecondary)
            }
        }
        .padding(LT.space20)
        .frame(width: 420, minHeight: 360)
        .background(LT.bg)
        .onAppear {
            runDiagnostics()
        }
    }

    @ViewBuilder
    private func stepIcon(_ status: StepStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .foregroundColor(LT.textMuted)
        case .running:
            ProgressView()
                .controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(LT.ok)
        case .failure:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(LT.bad)
        }
    }

    private func runDiagnostics() {
        isRunning = true
        hasRun = false
        steps = []
        Task {
            await ConnectionTester.fullDiagnostics(
                hubURL: hubURL,
                tlsSkipVerify: tlsSkipVerify
            ) { updatedSteps in
                Task { @MainActor in
                    steps = updatedSteps
                }
            }
            await MainActor.run {
                isRunning = false
                hasRun = true
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/LabTetherAgent/Views/Settings/ConnectionDiagnosticsSheet.swift
git commit -m "feat: add ConnectionDiagnosticsSheet for step-by-step hub diagnostics"
```

---

## Chunk 3: Integration

### Task 8: Wire up windows in `App.swift`

**Files:**
- Modify: `Sources/LabTetherAgent/App/App.swift`

- [ ] **Step 1: Add Onboarding and About windows to `App.swift`**

After the existing `Window("Agent Logs", ...)` scene (line 66), add:

```swift
Window("Welcome to LabTether", id: "onboarding") {
    OnboardingView(
        settings: appState.settings,
        agentProcess: appState.agentProcess
    )
}
.windowResizability(.contentSize)

Window("About LabTether", id: "about") {
    AboutView(
        metadata: appState.apiClient.metadata,
        deviceFingerprintPath: appState.settings.deviceFingerprintFilePath
    )
}
.windowResizability(.contentSize)
```

Then add an `.onChange` modifier to the `MenuBarExtra` body to trigger onboarding. After the `.onDisappear` block (around line 37), add:

```swift
.onChange(of: appState.shouldShowOnboarding) { shouldShow in
    if shouldShow {
        openWindow(id: "onboarding")
        appState.shouldShowOnboarding = false
    }
}
```

And add the environment action at the top of the struct:

```swift
@Environment(\.openWindow) private var openWindow
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/LabTetherAgent/App/App.swift
git commit -m "feat: register onboarding and about windows in app scene"
```

---

### Task 9: Add Test Connection and Copy Diagnostics to Settings Connection Tab

**Files:**
- Modify: `Sources/LabTetherAgent/Views/Settings/SettingsConnectionTab.swift`

- [ ] **Step 1: Add state and UI to `SettingsConnectionTab`**

Add state properties to the view:

```swift
@State private var connectionTestResult: ConnectionTestResult?
@State private var isTestingConnection = false
@State private var showDiagnosticsSheet = false
```

After the Hub URL text field, add a Test Connection row:

```swift
HStack(spacing: LT.space8) {
    Button {
        Task {
            isTestingConnection = true
            connectionTestResult = nil
            connectionTestResult = await ConnectionTester.quickTest(
                hubURL: settings.hubURL,
                tlsSkipVerify: settings.tlsSkipVerify
            )
            isTestingConnection = false
        }
    } label: {
        HStack(spacing: LT.space6) {
            if isTestingConnection {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right")
            }
            Text("Test Connection")
        }
        .font(LT.inter(12))
    }
    .buttonStyle(.plain)
    .foregroundColor(LT.accent)
    .disabled(isTestingConnection)

    if let result = connectionTestResult {
        switch result {
        case .success(let ms):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(LT.ok)
                Text("\(ms)ms")
                    .font(LT.mono(11))
                    .foregroundColor(LT.ok)
            }
        case .failure(let error):
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(LT.bad)
                Text(error)
                    .font(LT.mono(11))
                    .foregroundColor(LT.bad)
                    .lineLimit(1)
            }
        }
    }

    Spacer()

    if connectionTestResult != nil {
        Button("Full Diagnostics...") {
            showDiagnosticsSheet = true
        }
        .buttonStyle(.plain)
        .font(LT.inter(11))
        .foregroundColor(LT.textSecondary)
    }
}
.sheet(isPresented: $showDiagnosticsSheet) {
    ConnectionDiagnosticsSheet(
        hubURL: settings.hubURL,
        tlsSkipVerify: settings.tlsSkipVerify
    )
}
```

**Note:** Copy Diagnostics is not added to the settings tab — it remains accessible from the menu bar quick actions where all required dependencies are already available. This avoids threading `logBuffer`, `screenSharing`, and `apiClient` through `SettingsView` and `SettingsConnectionTab`. No changes needed to `SettingsView.swift` call sites.

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/LabTetherAgent/Views/Settings/SettingsConnectionTab.swift
git commit -m "feat: add test connection and full diagnostics to settings"
```

---

### Task 10: Update Menu Bar Footer and Quick Actions

**Files:**
- Modify: `Sources/LabTetherAgent/Views/MenuBar/MenuBarFooterSection.swift`
- Modify: `Sources/LabTetherAgent/Views/MenuBar/MenuBarQuickActionsSection.swift`

- [ ] **Step 1: Add About and Setup Wizard to `MenuBarFooterSection`**

The current footer is a compact brand bar with version + quit. Add `settings: AgentSettings` as a new parameter to `MenuBarFooterSection`. Add `@Environment(\.openWindow) private var openWindow` to the view.

Above the existing branding row, add a row of utility links:

```swift
HStack(spacing: LT.space12) {
    Button("About") {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "about")
    }
    .buttonStyle(.plain)
    .font(LT.inter(11))
    .foregroundColor(LT.textSecondary)

    Button("Setup Wizard") {
        settings.hasCompletedOnboarding = false
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "onboarding")
    }
    .buttonStyle(.plain)
    .font(LT.inter(11))
    .foregroundColor(LT.textSecondary)

    Spacer()
}
.padding(.horizontal, LT.space12)
.padding(.bottom, LT.space4)
```

Then update the call site in `MenuBarView.swift` (line 84) to pass `settings`:

```swift
MenuBarFooterSection(metadata: apiClient.metadata, agentProcess: agentProcess, settings: settings)
```

- [ ] **Step 2: Add Test Connection to `MenuBarQuickActionsSection`**

Add `onTestConnection` callback to `MenuBarQuickActionsSection`'s parameters (matching the existing `onCopyDiagnostics` pattern). Add a row before "Copy Diagnostics":

```swift
LTMenuRow(
    icon: "antenna.radiowaves.left.and.right",
    label: "Test Connection",
    action: onTestConnection
)
```

Then wire it in `MenuBarView.swift` where `MenuBarQuickActionsSection` is created (around line 52). Add the callback:

```swift
onTestConnection: {
    Task {
        let result = await ConnectionTester.quickTest(
            hubURL: settings.hubURL,
            tlsSkipVerify: settings.tlsSkipVerify
        )
        let message: String
        switch result {
        case .success(let ms):
            message = "Connection successful (\(ms)ms)"
        case .failure(let error):
            message = "Connection failed: \(error)"
        }
        copyToClipboard(message, label: "Test")
    }
},
```

This reuses the existing toast mechanism (`copyToClipboard` → `copyToast`) to show the result inline in the menu bar, which is simpler and more consistent than using `NotificationManager`.

- [ ] **Step 3: Build to verify compilation**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add Sources/LabTetherAgent/Views/MenuBar/MenuBarFooterSection.swift \
  Sources/LabTetherAgent/Views/MenuBar/MenuBarQuickActionsSection.swift \
  Sources/LabTetherAgent/Views/MenuBar/MenuBarView.swift
git commit -m "feat: add about, setup wizard, and test connection to menu bar"
```

---

### Task 11: Final Integration and Test

**Files:**
- All modified files

- [ ] **Step 1: Run full test suite**

Run: `swift test 2>&1 | tail -30`
Expected: All tests PASS

- [ ] **Step 2: Build release configuration**

Run: `swift build -c release 2>&1 | tail -10`
Expected: Build succeeds with no warnings

- [ ] **Step 3: Manual smoke test checklist**

Verify the following by launching the app:
- [ ] First launch (reset `hasCompletedOnboarding`): Onboarding window appears
- [ ] Onboarding wizard: 3 steps navigate correctly, tokens save
- [ ] Test Connection: Works from onboarding, settings, and menu bar
- [ ] Full Diagnostics: Opens sheet from settings, runs 4 steps
- [ ] About window: Opens from menu bar footer, shows version info
- [ ] Copy Diagnostics: Copies report from menu bar and settings
- [ ] Setup Wizard: Menu bar footer item reopens onboarding

- [ ] **Step 4: Final commit (if any remaining changes)**

```bash
git status
# Stage only files that were modified for this batch
git commit -m "feat: complete batch 1 — onboarding, connection testing, about window, diagnostics"
```
