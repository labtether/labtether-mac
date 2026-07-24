import LocalAuthentication
import XCTest
@testable import LabTetherAgent

final class AgentSettingsNormalizationTests: XCTestCase {
    func testKeychainSecretLoadsNeverRequestInteractiveAuthorization() {
        let query = KeychainSecretStore.loadQuery(account: "enrollmentToken")

        let context = query[kSecUseAuthenticationContext as String] as? LAContext
        XCTAssertEqual(context?.interactionNotAllowed, true)
        XCTAssertEqual(query["u_AuthUI"] as? String, "u_AuthUIF")
    }

    func testKeychainSecretLoadReturnsWhenSecurityFrameworkDoesNot() {
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)

        let result = KeychainSecretStore.boundedLoad(timeout: .milliseconds(20)) {
            started.signal()
            release.wait()
            return "late-secret"
        }

        XCTAssertEqual(started.wait(timeout: .now()), .success)
        XCTAssertNil(result)
        release.signal()
    }

    func testKeychainSecretLoadReturnsCompletedValue() {
        XCTAssertEqual(
            KeychainSecretStore.boundedLoad(timeout: .seconds(1)) { "available-secret" },
            "available-secret"
        )
    }

    func testCanonicalHubURLFromBareHost() {
        let result = AgentSettingsNormalization.canonicalHubWebSocketURL(from: "hub.example.com")
        XCTAssertEqual(result, "wss://hub.example.com/ws/agent")
    }

    func testCanonicalHubURLConvertsHTTPSAndAddsDefaultPath() {
        let result = AgentSettingsNormalization.canonicalHubWebSocketURL(from: "https://hub.example.com:8443")
        XCTAssertEqual(result, "wss://hub.example.com:8443/ws/agent")
    }

    func testCanonicalHubURLConvertsHTTPWithoutUpgradingTransport() {
        let result = AgentSettingsNormalization.canonicalHubWebSocketURL(from: "http://127.0.0.1:23000")
        XCTAssertEqual(result, "ws://127.0.0.1:23000/ws/agent")
        let environment = AgentEnvironmentBuilder.hubEnvironment(for: result!)
        XCTAssertEqual(environment["LABTETHER_WS_URL"], "ws://127.0.0.1:23000/ws/agent")
        XCTAssertEqual(environment["LABTETHER_API_BASE_URL"], "http://127.0.0.1:23000")
        XCTAssertEqual(environment["LABTETHER_ALLOW_INSECURE_TRANSPORT"], "true")
        XCTAssertEqual(environment["LABTETHER_OUTBOUND_ALLOW_LOOPBACK"], "true")

        let secureEnvironment = AgentEnvironmentBuilder.hubEnvironment(
            for: "wss://hub.example.com/ws/agent"
        )
        XCTAssertEqual(secureEnvironment["LABTETHER_API_BASE_URL"], "https://hub.example.com")
        XCTAssertNil(secureEnvironment["LABTETHER_ALLOW_INSECURE_TRANSPORT"])
        XCTAssertNil(secureEnvironment["LABTETHER_OUTBOUND_ALLOW_LOOPBACK"])
    }

    func testCanonicalHubURLPreservesExplicitPath() {
        let result = AgentSettingsNormalization.canonicalHubWebSocketURL(from: "ws://hub.example.com/custom/path")
        XCTAssertEqual(result, "ws://hub.example.com/custom/path")
    }

    func testCanonicalHubURLRejectsUnsupportedScheme() {
        XCTAssertNil(AgentSettingsNormalization.canonicalHubWebSocketURL(from: "ftp://hub.example.com"))
    }

    func testCanonicalHubURLRejectsCredentialsAndQueryFragments() {
        XCTAssertNil(AgentSettingsNormalization.canonicalHubWebSocketURL(from: "wss://user:pass@hub.example.com/ws/agent"))
        XCTAssertNil(AgentSettingsNormalization.canonicalHubWebSocketURL(from: "wss://hub.example.com/ws/agent?token=abc"))
        XCTAssertNil(AgentSettingsNormalization.canonicalHubWebSocketURL(from: "wss://hub.example.com/ws/agent#frag"))
    }

    func testLoopbackHubURLsAllowLoopbackOutbound() {
        XCTAssertTrue(AgentEnvironmentBuilder.allowsLoopbackOutbound(for: "wss://localhost:29443/ws/agent"))
        XCTAssertTrue(AgentEnvironmentBuilder.allowsLoopbackOutbound(for: "wss://127.0.0.1:29443/ws/agent"))
        XCTAssertTrue(AgentEnvironmentBuilder.allowsLoopbackOutbound(for: "wss://[::1]:29443/ws/agent"))
        XCTAssertFalse(AgentEnvironmentBuilder.allowsLoopbackOutbound(for: "wss://hub.example.com/ws/agent"))
    }

    func testDockerEndpointValidationAllowsAbsolutePathAndHTTPSURL() {
        XCTAssertNil(AgentSettingsNormalization.dockerEndpointValidationError("/var/run/docker.sock"))
        XCTAssertNil(AgentSettingsNormalization.dockerEndpointValidationError("unix:///var/run/docker.sock"))
        XCTAssertNil(AgentSettingsNormalization.dockerEndpointValidationError("https://docker.local:2376"))
    }

    func testDockerEndpointValidationRejectsInvalidUnixPathAndInsecureSchemes() {
        XCTAssertEqual(
            AgentSettingsNormalization.dockerEndpointValidationError("unix://relative/path"),
            "Docker endpoint unix:// path must be absolute."
        )
        XCTAssertEqual(
            AgentSettingsNormalization.dockerEndpointValidationError("tcp://docker.local:2375"),
            "Docker endpoint URL scheme must be https."
        )
        XCTAssertEqual(
            AgentSettingsNormalization.dockerEndpointValidationError("http://docker.local:2375"),
            "Docker endpoint URL scheme must be https."
        )
    }

    func testNormalizedPortListSortsAndDeduplicates() {
        XCTAssertEqual(
            AgentSettingsNormalization.normalizedPortList("443, 80 443;3000"),
            "80,443,3000"
        )
        XCTAssertNil(AgentSettingsNormalization.normalizedPortList("80,99999"))
    }

    func testStrictDecimalIntegerRejectsSignedAndMalformedValues() {
        XCTAssertEqual(AgentSettingsNormalization.strictDecimalInteger("0005", in: 1...10), 5)
        XCTAssertNil(AgentSettingsNormalization.strictDecimalInteger("+5", in: 1...10))
        XCTAssertNil(AgentSettingsNormalization.strictDecimalInteger("-5", in: 1...10))
        XCTAssertNil(AgentSettingsNormalization.strictDecimalInteger("1e3", in: 1...10_000))
        XCTAssertNil(AgentSettingsNormalization.strictDecimalInteger("30abc", in: 1...10_000))
        XCTAssertNil(AgentSettingsNormalization.strictDecimalInteger("１２", in: 1...100))
    }

    func testPortListRejectsSignedAndMalformedPorts() {
        XCTAssertNil(AgentSettingsNormalization.normalizedPortList("+443,80"))
        XCTAssertNil(AgentSettingsNormalization.normalizedPortList("443,80abc"))
        XCTAssertEqual(
            AgentSettingsNormalization.portListValidationError("+443"),
            "must contain only TCP ports between 1 and 65535."
        )
    }

    func testCIDRNormalizationAndValidation() {
        XCTAssertEqual(
            AgentSettingsNormalization.normalizedCIDRList("192.168.1.5/24,10.0.0.3/8,192.168.1.0/24"),
            "10.0.0.0/8,192.168.1.0/24"
        )
        XCTAssertEqual(
            AgentSettingsNormalization.cidrListValidationError("8.8.8.0/24"),
            "only private/local CIDR ranges are allowed."
        )
        XCTAssertEqual(
            AgentSettingsNormalization.cidrListValidationError("not-a-cidr"),
            "must contain valid CIDR values."
        )
        XCTAssertEqual(
            AgentSettingsNormalization.cidrListValidationError("192.168.1.0/+24"),
            "must contain valid CIDR values."
        )
    }

    func testRuntimeAPITokenFileActionPreservesEnrollmentIssuedCredential() {
        XCTAssertEqual(
            AgentSettings.runtimeAPITokenFileAction(
                apiToken: "",
                enrollmentToken: "",
                hasPersistedAgentToken: false
            ),
            .remove
        )
        XCTAssertEqual(
            AgentSettings.runtimeAPITokenFileAction(
                apiToken: "",
                enrollmentToken: "one-use-token",
                hasPersistedAgentToken: false
            ),
            .preserve
        )
        XCTAssertEqual(
            AgentSettings.runtimeAPITokenFileAction(
                apiToken: "",
                enrollmentToken: "",
                hasPersistedAgentToken: true
            ),
            .preserve
        )
        XCTAssertEqual(
            AgentSettings.runtimeAPITokenFileAction(
                apiToken: "agent-token",
                enrollmentToken: "",
                hasPersistedAgentToken: false
            ),
            .persist
        )
    }

    func testMinimumCredentialsIncludePrivatePersistedAgentToken() throws {
        XCTAssertTrue(
            AgentSettings.minimumCredentialConfigured(
                apiToken: "",
                enrollmentToken: "",
                hasPersistedAgentToken: true
            )
        )
        XCTAssertFalse(
            AgentSettings.minimumCredentialConfigured(
                apiToken: "",
                enrollmentToken: "",
                hasPersistedAgentToken: false
            )
        )
        XCTAssertTrue(
            AgentSettings.minimumCredentialConfigured(
                apiToken: "",
                enrollmentToken: "",
                hasPersistedAgentToken: false,
                hasPersistedEnrollmentToken: true
            )
        )

        let tokenFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("labtether-agent-token-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tokenFile) }
        try Data("secret\n".utf8).write(to: tokenFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenFile.path)
        XCTAssertTrue(AgentSettings.hasPrivatePersistedAgentToken(at: tokenFile.path))

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: tokenFile.path)
        XCTAssertFalse(AgentSettings.hasPrivatePersistedAgentToken(at: tokenFile.path))
    }

    func testRuntimeEnrollmentTokenFileActionPreservesHeadlessToken() {
        XCTAssertEqual(
            AgentSettings.runtimeEnrollmentTokenFileAction(
                enrollmentToken: "",
                hasPersistedEnrollmentToken: true
            ),
            .preserve
        )
        XCTAssertEqual(
            AgentSettings.runtimeEnrollmentTokenFileAction(
                enrollmentToken: "one-use-token",
                hasPersistedEnrollmentToken: true
            ),
            .persist
        )
        XCTAssertEqual(
            AgentSettings.runtimeEnrollmentTokenFileAction(
                enrollmentToken: "",
                hasPersistedEnrollmentToken: false
            ),
            .remove
        )
    }
}
