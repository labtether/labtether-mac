import Security
import XCTest
@testable import LabTetherAgent

final class ConnectionTesterCATests: XCTestCase {
    func testAcceptsPEMCertificate() throws {
        try withCAFile(Data(Self.publicCertificatePEM.utf8)) { path in
            let certificates = try ConnectionTester.trustedCertificates(for: path)
            XCTAssertEqual(certificates.count, 1)
            XCTAssertEqual(SecCertificateCopyData(try XCTUnwrap(certificates.first)) as Data, try Self.derCertificate())
        }
    }

    func testAcceptsMultiplePEMCertificatesWithCRLF() throws {
        let bundle = (Self.publicCertificatePEM + "\n" + Self.publicCertificatePEM)
            .replacingOccurrences(of: "\n", with: "\r\n")
        try withCAFile(Data(bundle.utf8)) { path in
            XCTAssertEqual(try ConnectionTester.trustedCertificates(for: path).count, 2)
        }
    }

    func testRejectsRawDERUnsupportedByBundledAgent() throws {
        try withCAFile(Self.derCertificate()) { path in
            XCTAssertThrowsError(try ConnectionTester.trustedCertificates(for: path))
        }
    }

    func testRejectsMissingPEMEndMarker() throws {
        let malformed = Self.publicCertificatePEM.replacingOccurrences(of: "-----END CERTIFICATE-----", with: "")
        try assertRejected(malformed)
    }

    func testRejectsMismatchedAndNestedPEMEnvelopes() throws {
        try assertRejected(Self.publicCertificatePEM.replacingOccurrences(
            of: "-----END CERTIFICATE-----", with: "-----END PUBLIC KEY-----"))
        try assertRejected("-----BEGIN CERTIFICATE-----\n" + Self.publicCertificatePEM)
        try assertRejected(" " + Self.publicCertificatePEM)
    }

    func testRejectsMalformedCertificateInsideBundle() throws {
        try assertRejected(Self.publicCertificatePEM + "\n-----BEGIN CERTIFICATE-----\nnot-base64!\n-----END CERTIFICATE-----")
        try assertRejected(Self.publicCertificatePEM + "\n-----BEGIN CERTIFICATE-----\n")
    }

    private func assertRejected(_ pem: String) throws {
        try withCAFile(Data(pem.utf8)) { path in
            XCTAssertThrowsError(try ConnectionTester.trustedCertificates(for: path))
        }
    }

    private func withCAFile(_ data: Data, body: (String) throws -> Void) throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("labtether-public-ca-\(UUID().uuidString).pem")
        try data.write(to: file, options: .atomic)
        defer { try? FileManager.default.removeItem(at: file) }
        try body(file.path)
    }

    private static func derCertificate() throws -> Data {
        let body = publicCertificatePEM.components(separatedBy: "\n")
            .filter { !$0.hasPrefix("-----") }.joined()
        return try XCTUnwrap(Data(base64Encoded: body))
    }

    // Public localhost certificate from Go's net/http/internal/testcert fixture.
    // Go Authors, BSD-3-Clause: https://go.dev/LICENSE. No private key is copied.
    private static let publicCertificatePEM = """
-----BEGIN CERTIFICATE-----
MIIDSDCCAjCgAwIBAgIQEP/md970HysdBTpuzDOf0DANBgkqhkiG9w0BAQsFADAS
MRAwDgYDVQQKEwdBY21lIENvMCAXDTcwMDEwMTAwMDAwMFoYDzIwODQwMTI5MTYw
MDAwWjASMRAwDgYDVQQKEwdBY21lIENvMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A
MIIBCgKCAQEAxcl69ROJdxjN+MJZnbFrYxyQooADCsJ6VDkuMyNQIix/Hk15Nk/u
FyBX1Me++aEpGmY3RIY4fUvELqT/srvAHsTXwVVSttMcY8pcAFmXSqo3x4MuUTG/
jCX3Vftj0r3EM5M8ImY1rzA/jqTTLJg00rD+DmuDABcqQvoXw/RV8w1yTRi5BPoH
DFD/AWTt/YgMvk1l2Yq/xI8VbMUIpjBoGXxWsSevQ5i2s1mk9/yZzu0Ysp1tTlzD
qOPa4ysFjBitdXiwfxjxtv5nXqOCP5rheKO0sWLk0fetMp1OV5JSJMAJw6c2ZMkl
U2WMqAEpRjdE/vHfIuNg+yGaRRqI07NZRQIDAQABo4GXMIGUMA4GA1UdDwEB/wQE
AwICpDATBgNVHSUEDDAKBggrBgEFBQcDATAPBgNVHRMBAf8EBTADAQH/MB0GA1Ud
DgQWBBQR5QIzmacmw78ZI1C4MXw7Q0wJ1jA9BgNVHREENjA0ggtleGFtcGxlLmNv
bYINKi5leGFtcGxlLmNvbYcEfwAAAYcQAAAAAAAAAAAAAAAAAAAAATANBgkqhkiG
9w0BAQsFAAOCAQEACrRNgiioUDzxQftd0fwOa6iRRcPampZRDtuaF68yNHoNWbOu
LUwc05eOWxRq3iABGSk2xg+FXM3DDeW4HhAhCFptq7jbVZ+4Jj6HeJG9mYRatAxR
Y/dEpa0D0EHhDxxVg6UzKOXB355n0IetGE/aWvyTV9SiDs6QsaC57Q9qq1/mitx5
2GFBoapol9L5FxCc77bztzK8CpLujkBi25Vk6GAFbl27opLfpyxkM+rX/T6MXCPO
6/YBacNZ7ff1/57Etg4i5mNA6ubCpuc4Gi9oYqCNNohftr2lkJr7REdDR6OW0lsL
rF7r4gUnKeC7mYIH1zypY7laskopiLFAfe96Kg==
-----END CERTIFICATE-----
"""
}
