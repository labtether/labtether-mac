import Foundation
import Network
import os

// MARK: - Result types

/// The outcome of a quick connectivity probe to the hub.
enum ConnectionTestResult: Equatable {
    /// The server replied within the timeout; `responseTimeMs` is the round-trip time.
    case success(responseTimeMs: Int)
    /// The probe failed; `error` contains a human-readable reason.
    case failure(error: String)
}

/// The lifecycle state of a single diagnostic step.
enum StepStatus: Equatable {
    case pending
    case running
    case success(String)
    case failure(String)
}

/// One row in the full-diagnostics waterfall.
struct DiagnosticStep: Identifiable {
    let id = UUID()
    let name: String
    var status: StepStatus = .pending
}

// MARK: - ConnectionTester

/// Namespace for hub connectivity probes used by the onboarding wizard, settings,
/// and menu bar quick actions.
enum ConnectionTester {

    static let maxProbeBodyBytes = 8 * 1_024

    // MARK: URL helpers

    /// Canonicalizes an accepted hub URL and converts it to its HTTP base URL
    /// (origin only — no path, query, or fragment).
    ///
    /// - `wss://` becomes `https://`
    /// - `ws://` becomes `http://`
    /// - `https://`, `http://`, and bare hosts are normalized exactly as they
    ///   are by `AgentSettings` before conversion.
    /// - Any path is stripped.
    /// - User information, queries, and fragments are rejected instead of silently
    ///   changing which endpoint is verified.
    /// - Returns `nil` for any input that is not a valid supported hub URL.
    static func httpBaseURL(from wsURLString: String) -> URL? {
        guard let canonical = AgentSettingsNormalization.canonicalHubWebSocketURL(from: wsURLString),
              var components = URLComponents(string: canonical),
              let scheme = components.scheme?.lowercased()
        else { return nil }

        guard components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil
        else { return nil }

        switch scheme {
        case "wss":
            components.scheme = "https"
        case "ws":
            components.scheme = "http"
        default:
            return nil
        }

        guard let host = components.host, !host.isEmpty else { return nil }

        // Strip the WebSocket path — probe only the hub's canonical root endpoint.
        components.path = ""

        return components.url
    }

    // MARK: Quick test

    /// Performs a single HTTP GET to the hub base URL and verifies the canonical
    /// LabTether hub identity response.
    ///
    /// - Parameters:
    ///   - hubURL: The WebSocket hub URL (e.g. `wss://host:port/ws/agent`).
    ///   - tlsSkipVerify: When `true`, server certificate errors are ignored.
    /// - Returns: `.success(responseTimeMs:)` or `.failure(error:)`.
    static func quickTest(hubURL: String, tlsSkipVerify: Bool = false) async -> ConnectionTestResult {
        guard let baseURL = httpBaseURL(from: hubURL) else {
            return .failure(error: "Invalid hub URL.")
        }

        let start = Date()
        do {
            let response = try await probeHub(url: baseURL, tlsSkipVerify: tlsSkipVerify)
            let elapsed = Int(Date().timeIntervalSince(start) * 1_000)
            if let validationError = hubIdentityValidationError(
                statusCode: response.statusCode,
                expectedContentLength: response.expectedContentLength,
                body: response.body
            ) {
                return .failure(error: validationError)
            }
            return .success(responseTimeMs: elapsed)
        } catch {
            return .failure(error: probeFailureMessage(error))
        }
    }

    // MARK: Full diagnostics

    /// Runs four sequential network checks and calls `onUpdate` after each step completes.
    ///
    /// Steps, in order:
    /// 1. DNS resolution
    /// 2. TCP connect
    /// 3. TLS handshake
    /// 4. LabTether hub identity verification
    ///
    /// - Parameters:
    ///   - hubURL: The WebSocket hub URL.
    ///   - tlsSkipVerify: When `true`, TLS certificate verification is skipped.
    ///   - onUpdate: Called on an unspecified thread after each step changes state.
    static func fullDiagnostics(
        hubURL: String,
        tlsSkipVerify: Bool,
        onUpdate: @escaping ([DiagnosticStep]) -> Void
    ) async {
        var steps = [
            DiagnosticStep(name: "DNS Resolution"),
            DiagnosticStep(name: "TCP Connect"),
            DiagnosticStep(name: "TLS Handshake"),
            DiagnosticStep(name: "HTTP Reachability"),
        ]
        onUpdate(steps)

        guard let baseURL = httpBaseURL(from: hubURL),
              let host = baseURL.host
        else {
            for index in steps.indices {
                steps[index].status = .failure("Invalid hub URL")
            }
            onUpdate(steps)
            return
        }

        let port = baseURL.port ?? defaultPort(for: baseURL)
        let isTLS = baseURL.scheme?.lowercased() == "https"

        // Step 0 — DNS
        steps[0].status = .running
        onUpdate(steps)
        let dnsResult = await resolveDNS(host: host)
        steps[0].status = dnsResult
        onUpdate(steps)

        guard case .success = dnsResult else {
            for index in 1..<steps.count {
                steps[index].status = .failure("Skipped (DNS failed)")
            }
            onUpdate(steps)
            return
        }

        // Step 1 — TCP
        steps[1].status = .running
        onUpdate(steps)
        let tcpResult = await checkTCP(host: host, port: port)
        steps[1].status = tcpResult
        onUpdate(steps)

        guard case .success = tcpResult else {
            for index in 2..<steps.count {
                steps[index].status = .failure("Skipped (TCP failed)")
            }
            onUpdate(steps)
            return
        }

        // Step 2 — TLS (only meaningful for wss:// / https:// targets)
        steps[2].status = .running
        onUpdate(steps)
        let tlsResult: StepStatus
        if isTLS {
            tlsResult = await checkTLS(host: host, port: port, skipVerify: tlsSkipVerify)
        } else {
            tlsResult = .success("Skipped (plain HTTP)")
        }
        steps[2].status = tlsResult
        onUpdate(steps)

        guard case .success = tlsResult else {
            steps[3].status = .failure("Skipped (TLS failed)")
            onUpdate(steps)
            return
        }

        // Step 3 — HTTP
        steps[3].status = .running
        onUpdate(steps)
        let httpResult = await checkHTTP(url: baseURL, tlsSkipVerify: tlsSkipVerify)
        steps[3].status = httpResult
        onUpdate(steps)
    }

    // MARK: Report formatter

    /// Formats the diagnostics waterfall as a copyable plain-text report.
    static func formatDiagnosticsReport(_ steps: [DiagnosticStep], hubURL: String) -> String {
        var lines: [String] = []
        lines.append("Connection Diagnostics Report")
        lines.append("Hub: \(redactedHubURL(hubURL))")
        lines.append(String(repeating: "-", count: 40))

        for step in steps {
            let marker: String
            let detail: String
            switch step.status {
            case .pending:
                marker = "[ ]"
                detail = "pending"
            case .running:
                marker = "[~]"
                detail = "running"
            case .success(let msg):
                marker = "[OK]"
                detail = msg
            case .failure(let msg):
                marker = "[FAIL]"
                detail = msg
            }
            lines.append("\(marker) \(step.name): \(detail)")
        }

        lines.append(String(repeating: "-", count: 40))
        lines.append("Generated: \(ISO8601DateFormatter().string(from: Date()))")
        return lines.joined(separator: "\n")
    }

    // MARK: - Private helpers

    private struct HubProbeResponse {
        let statusCode: Int
        let expectedContentLength: Int64
        let body: Data
    }

    private enum HubProbeError: Error {
        case invalidHTTPResponse
        case responseTooLarge
    }

    /// Validates the bounded response returned by the hub root endpoint. This is
    /// internal so the identity contract can be exercised without a live server.
    static func hubIdentityValidationError(
        statusCode: Int?,
        expectedContentLength: Int64 = NSURLSessionTransferSizeUnknown,
        body: Data
    ) -> String? {
        guard let statusCode else {
            return "The endpoint returned an invalid HTTP response."
        }
        guard statusCode == 200 else {
            return "Hub verification failed (HTTP \(statusCode))."
        }
        guard expectedContentLength <= maxProbeBodyBytes,
              body.count <= maxProbeBodyBytes
        else {
            return "Hub verification response is too large."
        }

        guard let object = try? JSONSerialization.jsonObject(with: body),
              let payload = object as? [String: Any],
              let service = payload["service"] as? String
        else {
            return "The endpoint returned an invalid hub response."
        }
        guard service == "labtether-hub" else {
            return "The endpoint is not a LabTether hub."
        }
        return nil
    }

    private static func probeHub(url: URL, tlsSkipVerify: Bool) async throws -> HubProbeResponse {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10

        // The delegate is always installed so redirect refusal cannot be bypassed
        // when certificate verification remains enabled.
        let delegate = HubProbeSessionDelegate(tlsSkipVerify: tlsSkipVerify)
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HubProbeError.invalidHTTPResponse
        }
        if http.expectedContentLength > maxProbeBodyBytes {
            throw HubProbeError.responseTooLarge
        }

        var body = Data()
        body.reserveCapacity(min(maxProbeBodyBytes, max(0, Int(http.expectedContentLength))))
        for try await byte in bytes {
            guard body.count < maxProbeBodyBytes else {
                throw HubProbeError.responseTooLarge
            }
            body.append(byte)
        }

        return HubProbeResponse(
            statusCode: http.statusCode,
            expectedContentLength: http.expectedContentLength,
            body: body
        )
    }

    private static func probeFailureMessage(_ error: Error) -> String {
        if let probeError = error as? HubProbeError {
            switch probeError {
            case .invalidHTTPResponse:
                return "The endpoint returned an invalid HTTP response."
            case .responseTooLarge:
                return "Hub verification response is too large."
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "Connection timed out."
            case .serverCertificateHasBadDate,
                 .serverCertificateNotYetValid,
                 .serverCertificateUntrusted,
                 .serverCertificateHasUnknownRoot,
                 .secureConnectionFailed,
                 .clientCertificateRejected,
                 .clientCertificateRequired:
                return "TLS certificate verification failed."
            default:
                return "Connection failed."
            }
        }

        return "Unexpected connection error."
    }

    private static func redactedHubURL(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: normalized),
              components.scheme != nil,
              components.host != nil
        else {
            return "<invalid>"
        }
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.string ?? "<invalid>"
    }

    private static func defaultPort(for url: URL) -> Int {
        switch url.scheme?.lowercased() {
        case "https": return 443
        default: return 80
        }
    }

    /// Resolves `host` to at least one address using `getaddrinfo`.
    private static func resolveDNS(host: String) async -> StepStatus {
        await Task.detached(priority: .userInitiated) {
            var hints = addrinfo()
            hints.ai_family = AF_UNSPEC
            hints.ai_socktype = SOCK_STREAM

            var result: UnsafeMutablePointer<addrinfo>?
            let status = getaddrinfo(host, nil, &hints, &result)
            defer { if result != nil { freeaddrinfo(result) } }

            if status != 0 {
                let message = String(cString: gai_strerror(status))
                return StepStatus.failure("DNS lookup failed: \(message)")
            }

            // Collect resolved addresses for the detail string.
            var addresses: [String] = []
            var cursor = result
            while let node = cursor {
                let addr = node.pointee.ai_addr
                let family = Int32(node.pointee.ai_family)
                if family == AF_INET {
                    var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    var sin = sockaddr_in()
                    withUnsafeBytes(of: addr!.pointee) { raw in
                        _ = raw.load(as: sockaddr_in.self)
                        memcpy(&sin, raw.baseAddress!, MemoryLayout<sockaddr_in>.size)
                    }
                    if inet_ntop(AF_INET, &sin.sin_addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil {
                        addresses.append(String(cString: buf))
                    }
                } else if family == AF_INET6 {
                    var buf = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                    var sin6 = sockaddr_in6()
                    _ = withUnsafeBytes(of: addr!.pointee) { raw in
                        memcpy(&sin6, raw.baseAddress!, MemoryLayout<sockaddr_in6>.size)
                    }
                    if inet_ntop(AF_INET6, &sin6.sin6_addr, &buf, socklen_t(INET6_ADDRSTRLEN)) != nil {
                        addresses.append(String(cString: buf))
                    }
                }
                cursor = node.pointee.ai_next
            }

            let detail = addresses.isEmpty ? host : addresses.prefix(3).joined(separator: ", ")
            return StepStatus.success("Resolved: \(detail)")
        }.value
    }

    /// Attempts a raw TCP connection to `host:port` with a 5-second timeout.
    private static func checkTCP(host: String, port: Int) async -> StepStatus {
        await withCheckedContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(integerLiteral: UInt16(clamping: port))
            )
            let connection = NWConnection(to: endpoint, using: .tcp)

            @Sendable func resumeOnce(_ result: StepStatus) {
                let alreadyResumed = resumed.withLock { val -> Bool in
                    let was = val
                    val = true
                    return was
                }
                guard !alreadyResumed else { return }
                connection.cancel()
                continuation.resume(returning: result)
            }

            let timeout = DispatchWorkItem {
                resumeOnce(.failure("TCP connect timed out"))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    timeout.cancel()
                    resumeOnce(.success("Connected to \(host):\(port)"))
                case .failed(let error):
                    timeout.cancel()
                    resumeOnce(.failure(error.localizedDescription))
                case .cancelled:
                    timeout.cancel()
                    resumeOnce(.failure("Connection cancelled"))
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }

    /// Attempts a TLS handshake with `host:port` with a 5-second timeout.
    private static func checkTLS(host: String, port: Int, skipVerify: Bool) async -> StepStatus {
        await withCheckedContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)

            let tlsOptions = NWProtocolTLS.Options()
            if skipVerify {
                sec_protocol_options_set_verify_block(
                    tlsOptions.securityProtocolOptions,
                    { _, _, completionHandler in completionHandler(true) },
                    .global()
                )
            }
            let params = NWParameters(tls: tlsOptions)

            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(integerLiteral: UInt16(clamping: port))
            )
            let connection = NWConnection(to: endpoint, using: params)

            @Sendable func resumeOnce(_ result: StepStatus) {
                let alreadyResumed = resumed.withLock { val -> Bool in
                    let was = val
                    val = true
                    return was
                }
                guard !alreadyResumed else { return }
                connection.cancel()
                continuation.resume(returning: result)
            }

            let timeout = DispatchWorkItem {
                resumeOnce(.failure("TLS handshake timed out"))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    timeout.cancel()
                    resumeOnce(.success("TLS handshake succeeded"))
                case .failed(let error):
                    timeout.cancel()
                    resumeOnce(.failure(error.localizedDescription))
                case .cancelled:
                    timeout.cancel()
                    resumeOnce(.failure("Connection cancelled"))
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }

    /// Performs a bounded, non-redirecting HTTP GET to `url` and verifies the
    /// canonical LabTether hub identity response.
    private static func checkHTTP(url: URL, tlsSkipVerify: Bool) async -> StepStatus {
        do {
            let response = try await probeHub(url: url, tlsSkipVerify: tlsSkipVerify)
            if let validationError = hubIdentityValidationError(
                statusCode: response.statusCode,
                expectedContentLength: response.expectedContentLength,
                body: response.body
            ) {
                return .failure(validationError)
            }
            return .success("Verified LabTether hub")
        } catch {
            return .failure(probeFailureMessage(error))
        }
    }
}

// MARK: - HubProbeSessionDelegate

/// A probe delegate that refuses redirects and only accepts an untrusted server
/// certificate when the user explicitly enabled `tlsSkipVerify`.
private final class HubProbeSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    private let tlsSkipVerify: Bool

    init(tlsSkipVerify: Bool) {
        self.tlsSkipVerify = tlsSkipVerify
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handle(challenge, completionHandler: completionHandler)
    }

    // URLSession.bytes(for:) delivers server-trust challenges through the
    // task-level delegate callback on macOS. Keep the session-level callback
    // above for the other URLSession APIs, and route both through one policy.
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handle(challenge, completionHandler: completionHandler)
    }

    private func handle(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard tlsSkipVerify,
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
