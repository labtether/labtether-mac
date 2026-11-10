import CryptoKit
import Foundation
import Security

/// The TLS server key of a Hub, as proof of which Hub an address is.
///
/// A certificate is public: anyone can copy it and present it. Only a server
/// that finishes the TLS handshake holds the private key. So a key counts
/// here only when the handshake completes; reading the certificate and
/// stopping is never proof. The probe asks for the public identity route and
/// carries no token, cookie or other credential.
enum HubServerKey {
    enum Proof: Equatable {
        /// The address finished a handshake with the expected key.
        case proven
        /// The address answered, but not as the holder of that key.
        case notProven
        /// Nothing answered with a certificate.
        case unreachable
    }

    /// For the record made when the token has just been accepted: the key of
    /// the server that passes this Mac's normal verification for the address
    /// (the system's roots, plus `anchors` for a Hub with its own CA) and
    /// finishes the handshake.
    static func verifiedFingerprint(hubURL: String, anchors: [SecCertificate]) async -> String? {
        let gate = KeyGate(.verified(anchors: anchors))
        guard await completes(hubURL: hubURL, gate: gate) else { return nil }
        return gate.acceptedKey
    }

    /// Whether the server at `hubURL` holds the private key that `expected`
    /// names. The handshake goes on only for a certificate with that key, and
    /// it must finish: a copied certificate cannot finish it.
    static func proves(_ expected: String, hubURL: String) async -> Proof {
        let gate = KeyGate(.expect(key: expected))
        if await completes(hubURL: hubURL, gate: gate) { return .proven }
        return gate.sawCertificate ? .notProven : .unreachable
    }

    static func fingerprint(of trust: SecTrust) -> String? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first, let key = SecCertificateCopyKey(leaf),
              let data = SecKeyCopyExternalRepresentation(key, nil) as Data? else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// True when the identity request got an HTTP answer, which needs a
    /// finished handshake on a connection the gate let through.
    private static func completes(hubURL: String, gate: KeyGate) async -> Bool {
        guard let url = ConnectionTester.hubIdentityURL(from: hubURL), url.scheme == "https" else { return false }
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 8
        let session = URLSession(configuration: config, delegate: gate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpShouldHandleCookies = false
        guard let (_, response) = try? await session.data(for: request) else { return false }
        return response is HTTPURLResponse
    }

    /// Decides, per connection, whether the handshake may go on.
    private final class KeyGate: NSObject, URLSessionTaskDelegate {
        enum Rule {
            case expect(key: String)
            case verified(anchors: [SecCertificate])
        }

        private let rule: Rule
        private let lock = NSLock()
        private var seen = false
        private var accepted: String?
        var sawCertificate: Bool { lock.lock(); defer { lock.unlock() }; return seen }
        var acceptedKey: String? { lock.lock(); defer { lock.unlock() }; return accepted }

        init(_ rule: Rule) { self.rule = rule }

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
            guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  let trust = challenge.protectionSpace.serverTrust,
                  let key = HubServerKey.fingerprint(of: trust) else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            lock.lock(); seen = true; lock.unlock()
            guard HubServerKey.mayContinue(rule, presentedKey: key, trust: trust) else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            lock.lock(); accepted = key; lock.unlock()
            completionHandler(.useCredential, URLCredential(trust: trust))
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private static func mayContinue(_ rule: KeyGate.Rule, presentedKey: String, trust: SecTrust) -> Bool {
        switch rule {
        case .expect(let key):
            return presentedKey == key
        case .verified(let anchors):
            if !anchors.isEmpty {
                // The agent trusts the system's roots plus the Hub's own CA.
                SecTrustSetAnchorCertificates(trust, anchors as CFArray)
                SecTrustSetAnchorCertificatesOnly(trust, false)
            }
            return SecTrustEvaluateWithError(trust, nil)
        }
    }
}
