import CryptoKit
import Foundation
import Security

/// The Hub's own CA, offered for the person to compare and trust.
struct HubCAOffer: Equatable {
    /// The CA certificate as PEM, as it is saved once trusted.
    let pem: String
    /// SHA-256 of the CA certificate's DER bytes: 64 lowercase hex characters,
    /// the same value the Hub shows in the console and in `/api/v1/tls/info`.
    let fingerprint: String
    /// A different CA is already saved for this Mac's Hub.
    var replacesSavedCA = false

    /// The fingerprint as people compare it: groups of 4, in two rows of 8.
    var groupedRows: [String] {
        let groups = HubCATrust.groups(fingerprint)
        let half = (groups.count + 1) / 2
        return [groups.prefix(half), groups.dropFirst(half)].map { $0.joined(separator: " ") }.filter { !$0.isEmpty }
    }
}

/// What a look at the Hub's TLS certificate found.
enum HubCACheck: Equatable {
    /// Verifies with the system's roots or the CA saved for this Hub.
    case trusted
    /// Everything is in order except that the issuer is not known yet.
    case offer(HubCAOffer)
    /// Not trusted, and never offered for trust: the words say why.
    case refused(String)
    case unreachable
}

/// "Trust this Hub": a home Hub signs its certificate with its own CA. Setup
/// reads that CA without sending anything, checks that the Hub's certificate
/// really chains to it for this host name, and shows its fingerprint. Only an
/// unknown issuer is ever offered; an expired certificate or a wrong host
/// name stays an error.
enum HubCATrust {
    static let noOwnCAMessage = "This Hub's certificate is not trusted. Add its CA certificate in Settings › Security."
    static let expiredMessage = "The Hub's certificate has expired."
    static let wrongHostMessage = "The Hub's certificate is for another host name."
    static let mismatchMessage = "The Hub's certificate was not issued by the certificate the Hub offers."

    // MARK: Fingerprint and PEM

    static func fingerprint(of certificate: SecCertificate) -> String {
        SHA256.hash(data: SecCertificateCopyData(certificate) as Data).map { String(format: "%02x", $0) }.joined()
    }

    static func groups(_ hex: String) -> [String] {
        let characters = Array(hex)
        return stride(from: 0, to: characters.count, by: 4).map { String(characters[$0..<min($0 + 4, characters.count)]) }
    }

    static func pem(of certificate: SecCertificate) -> String {
        let base64 = (SecCertificateCopyData(certificate) as Data).base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN CERTIFICATE-----\n\(base64)\n-----END CERTIFICATE-----\n"
    }

    static func certificates(fromPEM text: String) -> [SecCertificate] {
        var found: [SecCertificate] = []
        var body: String?
        for line in text.components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if line == "-----BEGIN CERTIFICATE-----" {
                body = ""
            } else if line == "-----END CERTIFICATE-----" {
                if let body, let data = Data(base64Encoded: body), let certificate = SecCertificateCreateWithData(nil, data as CFData) {
                    found.append(certificate)
                }
                body = nil
            } else if body != nil {
                body?.append(line)
            }
        }
        return found
    }

    // MARK: The decision

    /// `chain` is what the Hub served (leaf first). `fetchedCA` is the Hub's
    /// `/api/v1/ca.crt` when the chain itself carries no CA.
    static func evaluate(
        chain: [SecCertificate],
        host: String,
        savedAnchors: [SecCertificate],
        fetchedCA: SecCertificate?,
        at date: Date? = nil
    ) -> HubCACheck {
        guard !chain.isEmpty else { return .unreachable }
        let usual = verify(chain, host: host, anchors: savedAnchors, anchorsOnly: false, at: date)
        if usual == errSecSuccess { return .trusted }
        guard let candidate = servedCA(in: chain) ?? fetchedCA else {
            return .refused(words(for: usual, otherwise: noOwnCAMessage))
        }
        let result = verify(chain, host: host, anchors: [candidate], anchorsOnly: true, at: date)
        guard result == errSecSuccess else { return .refused(words(for: result, otherwise: mismatchMessage)) }
        let value = fingerprint(of: candidate)
        return .offer(HubCAOffer(
            pem: pem(of: candidate),
            fingerprint: value,
            replacesSavedCA: !savedAnchors.isEmpty && !savedAnchors.contains { fingerprint(of: $0) == value }
        ))
    }

    /// The CA at the end of the served chain, when the Hub sends it along.
    static func servedCA(in chain: [SecCertificate]) -> SecCertificate? {
        chain.count > 1 ? chain.last.flatMap { isSelfIssued($0) ? $0 : nil } : nil
    }

    private static func words(for status: OSStatus, otherwise fallback: String) -> String {
        switch status {
        case errSecCertificateExpired, errSecCertificateNotValidYet: return expiredMessage
        case errSecHostNameMismatch: return wrongHostMessage
        default: return fallback
        }
    }

    /// True when the chain validates for `host` with only `anchors` trusted:
    /// the proof that an address is served by the Hub whose CA is saved.
    static func chainsOnly(to anchors: [SecCertificate], chain: [SecCertificate], host: String, at date: Date? = nil) -> Bool {
        !anchors.isEmpty && !chain.isEmpty && verify(chain, host: host, anchors: anchors, anchorsOnly: true, at: date) == errSecSuccess
    }

    private static func verify(
        _ chain: [SecCertificate], host: String, anchors: [SecCertificate], anchorsOnly: Bool, at date: Date?
    ) -> OSStatus {
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates(chain as CFArray, SecPolicyCreateSSL(true, host as CFString), &trust) == errSecSuccess,
              let trust else { return errSecParam }
        if !anchors.isEmpty {
            SecTrustSetAnchorCertificates(trust, anchors as CFArray)
            SecTrustSetAnchorCertificatesOnly(trust, anchorsOnly)
        } else if anchorsOnly {
            return errSecNotTrusted
        }
        if let date { SecTrustSetVerifyDate(trust, date as CFDate) }
        var error: CFError?
        if SecTrustEvaluateWithError(trust, &error) { return errSecSuccess }
        return OSStatus(error.map { CFErrorGetCode($0) } ?? CFIndex(errSecNotTrusted))
    }

    private static func isSelfIssued(_ certificate: SecCertificate) -> Bool {
        guard let subject = SecCertificateCopyNormalizedSubjectSequence(certificate),
              let issuer = SecCertificateCopyNormalizedIssuerSequence(certificate) else { return false }
        return (subject as Data) == (issuer as Data)
    }

    // MARK: Reading the Hub

    /// Looks at the Hub's certificate. Nothing is sent on the unverified
    /// connection: the TLS handshake is stopped once the chain is read, and
    /// the CA download (only when the chain carries no CA) is a bare GET.
    static func check(hubURL: String, savedCAFile: String) async -> HubCACheck {
        guard let url = ConnectionTester.hubIdentityURL(from: hubURL), url.scheme == "https", let host = url.host else {
            return .unreachable
        }
        let chain = await servedChain(url)
        guard !chain.isEmpty else { return .unreachable }
        let saved = (try? ConnectionTester.trustedCertificates(for: savedCAFile)) ?? []
        let first = evaluate(chain: chain, host: host, savedAnchors: saved, fetchedCA: nil)
        guard case .refused = first, servedCA(in: chain) == nil, let fetched = await downloadedCA(from: url) else { return first }
        return evaluate(chain: chain, host: host, savedAnchors: saved, fetchedCA: fetched)
    }

    enum OwnCAVerdict: Equatable {
        /// A handshake with only this file's certificates as roots finished.
        case verified(fingerprint: String)
        /// The Hub answered, but its certificate does not chain to this file.
        case mismatch
        /// The file holds no certificate.
        case unreadable
        /// Nothing answered with a certificate.
        case unreachable
    }

    /// Whether the CA in `caFile`, alone, verifies the Hub at `hubURL`. The
    /// request is the public identity route and carries nothing.
    static func verifiesAlone(hubURL: String, caFile: String) async -> OwnCAVerdict {
        guard let anchors = try? ConnectionTester.trustedCertificates(for: caFile), let first = anchors.first else {
            return .unreadable
        }
        guard let url = ConnectionTester.hubIdentityURL(from: hubURL), url.scheme == "https" else { return .unreachable }
        let capture = ChainCapture(completeHandshake: true, onlyAnchors: anchors)
        let session = bareSession(capture)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6)
        request.httpShouldHandleCookies = false
        if let (_, response) = try? await session.data(for: request), response is HTTPURLResponse {
            return .verified(fingerprint: fingerprint(of: first))
        }
        return capture.chain.isEmpty ? .unreachable : .mismatch
    }

    /// The fingerprint of the Hub's own CA at `hubURL`, proven: the address
    /// completed a TLS handshake that validates against that CA alone (so it
    /// holds a certificate from that CA for its host name, and its key). With
    /// `among`, only one of those certificates counts. The request is the
    /// public identity route and carries nothing.
    static func provenOwnCA(hubURL: String, among allowed: [SecCertificate]?) async -> String? {
        guard let url = ConnectionTester.hubIdentityURL(from: hubURL), url.scheme == "https" else { return nil }
        let chain = await servedChain(url)
        guard !chain.isEmpty else { return nil }
        var found = servedCA(in: chain)
        if found == nil { found = await downloadedCA(from: url) }
        guard let candidate = found else { return nil }
        let value = fingerprint(of: candidate)
        if let allowed, !allowed.contains(where: { fingerprint(of: $0) == value }) { return nil }
        let session = bareSession(ChainCapture(completeHandshake: true, onlyAnchors: [candidate]))
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpShouldHandleCookies = false
        guard let (_, response) = try? await session.data(for: request), response is HTTPURLResponse else { return nil }
        return value
    }

    /// The request for the Hub's public CA file: no credential, cookie or cache.
    static func caRequest(for hubRoot: URL) -> URLRequest? {
        guard var components = URLComponents(url: hubRoot, resolvingAgainstBaseURL: false) else { return nil }
        components.path = "/api/v1/ca.crt"
        components.query = nil
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.httpShouldHandleCookies = false
        return request
    }

    private static func bareSession(_ delegate: URLSessionDelegate) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    private static func servedChain(_ url: URL) async -> [SecCertificate] {
        let capture = ChainCapture(completeHandshake: false, onlyAnchors: nil)
        let session = bareSession(capture)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.httpShouldHandleCookies = false
        _ = try? await session.data(for: request)
        return capture.chain
    }

    private static func downloadedCA(from url: URL) async -> SecCertificate? {
        guard let request = caRequest(for: url) else { return nil }
        let session = bareSession(ChainCapture(completeHandshake: true, onlyAnchors: nil))
        defer { session.invalidateAndCancel() }
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 65_536,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return certificates(fromPEM: text).first
    }

    /// Reads the served chain. For the chain probe it then stops the handshake;
    /// for the public CA download it lets this one unverified GET through; with
    /// `onlyAnchors` it goes on only when the chain validates against them alone.
    private final class ChainCapture: NSObject, URLSessionTaskDelegate {
        private let completeHandshake: Bool
        private let onlyAnchors: [SecCertificate]?
        private let lock = NSLock()
        private var captured: [SecCertificate] = []
        var chain: [SecCertificate] { lock.lock(); defer { lock.unlock() }; return captured }

        init(completeHandshake: Bool, onlyAnchors: [SecCertificate]?) {
            self.completeHandshake = completeHandshake
            self.onlyAnchors = onlyAnchors
        }

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
                  let trust = challenge.protectionSpace.serverTrust else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            let chain = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
            lock.lock(); captured = chain; lock.unlock()
            if let onlyAnchors {
                SecTrustSetAnchorCertificates(trust, onlyAnchors as CFArray)
                SecTrustSetAnchorCertificatesOnly(trust, true)
                guard SecTrustEvaluateWithError(trust, nil) else {
                    completionHandler(.cancelAuthenticationChallenge, nil)
                    return
                }
            }
            if completeHandshake {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
