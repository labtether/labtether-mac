import CryptoKit
import Foundation
import Security

/// The SHA-256 of the TLS server key a Hub address presents. Two addresses
/// with the same key are served by the same Hub. The TLS handshake is stopped
/// after the certificate is read, so nothing (no token) is ever sent.
enum HubServerKey {
    static func fingerprint(hubURL: String) async -> String? {
        guard let url = ConnectionTester.hubIdentityURL(from: hubURL), url.scheme == "https" else { return nil }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 8
        let capture = KeyCapture()
        let session = URLSession(configuration: config, delegate: capture, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        _ = try? await session.data(from: url)
        return capture.fingerprint
    }

    static func fingerprint(of trust: SecTrust) -> String? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first, let key = SecCertificateCopyKey(leaf),
              let data = SecKeyCopyExternalRepresentation(key, nil) as Data? else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private final class KeyCapture: NSObject, URLSessionTaskDelegate {
        private let lock = NSLock()
        private var value: String?
        var fingerprint: String? { lock.lock(); defer { lock.unlock() }; return value }

        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            handle(challenge, completionHandler)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            handle(challenge, completionHandler)
        }

        private func handle(_ challenge: URLAuthenticationChallenge,
                            _ completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
               let trust = challenge.protectionSpace.serverTrust {
                let key = HubServerKey.fingerprint(of: trust)
                lock.lock(); value = key; lock.unlock()
            }
            completionHandler(.cancelAuthenticationChallenge, nil)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
