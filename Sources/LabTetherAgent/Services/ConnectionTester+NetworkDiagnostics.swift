import Foundation
import Network
import os
import Security

extension ConnectionTester {
    /// Resolves `host` to at least one address using `getaddrinfo`.
    static func resolveDNS(host: String) async -> StepStatus {
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
    static func checkTCP(host: String, port: Int) async -> StepStatus {
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
    static func checkTLS(
        host: String,
        port: Int,
        skipVerify: Bool,
        caFile: String
    ) async -> StepStatus {
        let customCertificates: [SecCertificate]
        do {
            customCertificates = try Self.trustedCertificates(for: caFile)
        } catch {
            return .failure("The configured CA certificate could not be loaded.")
        }

        return await withCheckedContinuation { (continuation: CheckedContinuation<StepStatus, Never>) in
            let resumed = OSAllocatedUnfairLock(initialState: false)

            let tlsOptions = NWProtocolTLS.Options()
            if AgentEnvironmentBuilder.effectiveTLSSkipVerify(skipVerify, caFile: caFile) {
                sec_protocol_options_set_verify_block(
                    tlsOptions.securityProtocolOptions,
                    { _, _, completionHandler in completionHandler(true) },
                    .global()
                )
            } else if !customCertificates.isEmpty {
                sec_protocol_options_set_verify_block(
                    tlsOptions.securityProtocolOptions,
                    { _, trust, completionHandler in
                        let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
                        SecTrustSetAnchorCertificates(secTrust, customCertificates as CFArray)
                        SecTrustSetAnchorCertificatesOnly(secTrust, false)
                        completionHandler(SecTrustEvaluateWithError(secTrust, nil))
                    },
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

}
