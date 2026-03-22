import XCTest
@testable import LabTetherAgent

final class AgentSettingsNormalizationTests: XCTestCase {
    func testCanonicalHubURLFromBareHost() {
        let result = AgentSettingsNormalization.canonicalHubWebSocketURL(from: "hub.example.com")
        XCTAssertEqual(result, "wss://hub.example.com/ws/agent")
    }

    func testCanonicalHubURLConvertsHTTPSAndAddsDefaultPath() {
        let result = AgentSettingsNormalization.canonicalHubWebSocketURL(from: "https://hub.example.com:8443")
        XCTAssertEqual(result, "wss://hub.example.com:8443/ws/agent")
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
    }

    func testRuntimeAPITokenFileActionAlwaysRemovesWhenTokenIsCleared() {
        XCTAssertEqual(AgentSettings.runtimeAPITokenFileAction(apiToken: ""), .remove)
        XCTAssertEqual(AgentSettings.runtimeAPITokenFileAction(apiToken: "   "), .remove)
        XCTAssertEqual(AgentSettings.runtimeAPITokenFileAction(apiToken: "agent-token"), .persist)
    }
}
