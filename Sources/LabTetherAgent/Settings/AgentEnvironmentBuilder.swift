import Foundation

/// Builds the environment dictionary for the Go agent process from AgentSettings.
enum AgentEnvironmentBuilder {
    static func buildEnvironment(from settings: AgentSettings) throws -> [String: String] {
        var env: [String: String] = [:]

        if let normalizedWS = settings.normalizedHubWebSocketURL() {
            env["LABTETHER_WS_URL"] = normalizedWS
            // Derive HTTP API base URL from WS URL for heartbeat fallback
            // ws://host:8080/ws/agent -> http://host:8080
            var apiBase = normalizedWS
            apiBase = apiBase.replacingOccurrences(of: "wss://", with: "https://")
            apiBase = apiBase.replacingOccurrences(of: "ws://", with: "http://")
            if let url = URL(string: apiBase),
               var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                components.path = ""
                if let base = components.url?.absoluteString {
                    env["LABTETHER_API_BASE_URL"] = base
                }
            }
        }
        let trimmedEnrollmentToken = settings.enrollmentToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIToken = settings.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedEnrollmentToken.isEmpty {
            try settings.persistRuntimeSecret(
                trimmedEnrollmentToken,
                to: settings.enrollmentTokenFilePath,
                issueKey: "runtime.enrollmentToken",
                label: "Enrollment token"
            )
            env["LABTETHER_ENROLLMENT_TOKEN_FILE"] = settings.enrollmentTokenFilePath
        } else {
            try settings.removeRuntimeSecretIfNeeded(
                at: settings.enrollmentTokenFilePath,
                issueKey: "runtime.enrollmentToken",
                label: "Enrollment token"
            )
        }
        switch AgentSettings.runtimeAPITokenFileAction(apiToken: trimmedAPIToken) {
        case .persist:
            try settings.persistRuntimeSecret(
                trimmedAPIToken,
                to: settings.tokenFilePath,
                issueKey: "runtime.apiToken",
                label: "API token"
            )
        case .remove:
            try settings.removeRuntimeSecretIfNeeded(
                at: settings.tokenFilePath,
                issueKey: "runtime.apiToken",
                label: "API token"
            )
        }
        if !settings.assetID.isEmpty { env["AGENT_ASSET_ID"] = settings.assetID }
        if !settings.groupID.isEmpty { env["AGENT_GROUP_ID"] = settings.groupID }
        env["AGENT_PORT"] = settings.agentPort
        if settings.tlsSkipVerify { env["LABTETHER_TLS_SKIP_VERIFY"] = "true" }
        if !settings.tlsCAFile.isEmpty { env["LABTETHER_TLS_CA_FILE"] = settings.tlsCAFile }
        env["LABTETHER_DOCKER_ENABLED"] = settings.normalizedDockerMode()
        env["LABTETHER_DOCKER_SOCKET"] = settings.normalizedDockerEndpoint()
        env["LABTETHER_DOCKER_DISCOVERY_INTERVAL"] = settings.normalizedDockerDiscoveryInterval()
        env["LABTETHER_FILES_ROOT_MODE"] = settings.normalizedFilesRootMode()
        env["LABTETHER_AUTO_UPDATE"] = settings.autoUpdateEnabled ? "true" : "false"
        env["LABTETHER_ALLOW_REMOTE_OVERRIDES"] = settings.allowRemoteOverrides ? "true" : "false"
        env["LABTETHER_LOG_LEVEL"] = settings.normalizedLogLevel()
        // Background `log stream --style ndjson` parsing is a measurable idle CPU hotspot
        // on macOS. Default this menu-bar runtime to on-demand logs only.
        let inheritedLogStream = ProcessInfo.processInfo.environment["LABTETHER_LOG_STREAM_ENABLED"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let inheritedLogStream, !inheritedLogStream.isEmpty {
            env["LABTETHER_LOG_STREAM_ENABLED"] = inheritedLogStream
        } else {
            env["LABTETHER_LOG_STREAM_ENABLED"] = "false"
        }
        env["LABTETHER_WEBRTC_ENABLED"] = settings.effectiveWebRTCEnabled ? "true" : "false"
        env["LABTETHER_WEBRTC_STUN_URL"] = settings.normalizedWebRTCSTUNURL()
        let turnURL = settings.webrtcTurnURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !turnURL.isEmpty {
            env["LABTETHER_WEBRTC_TURN_URL"] = turnURL
        }
        let turnUser = settings.webrtcTurnUser.trimmingCharacters(in: .whitespacesAndNewlines)
        if !turnUser.isEmpty {
            env["LABTETHER_WEBRTC_TURN_USER"] = turnUser
        }
        let turnPass = settings.webrtcTurnPass.trimmingCharacters(in: .whitespacesAndNewlines)
        if !turnPass.isEmpty {
            try settings.persistRuntimeSecret(
                turnPass,
                to: settings.webrtcTurnPassFilePath,
                issueKey: "runtime.turnPass",
                label: "WebRTC TURN password"
            )
            env["LABTETHER_WEBRTC_TURN_PASS_FILE"] = settings.webrtcTurnPassFilePath
        } else {
            try settings.removeRuntimeSecretIfNeeded(
                at: settings.webrtcTurnPassFilePath,
                issueKey: "runtime.turnPass",
                label: "WebRTC TURN password"
            )
        }
        env["LABTETHER_CAPTURE_FPS"] = settings.normalizedCaptureFPS()
        env["LABTETHER_SERVICES_DISCOVERY_DOCKER_ENABLED"] = settings.servicesDiscoveryDockerEnabled ? "true" : "false"
        env["LABTETHER_SERVICES_DISCOVERY_PROXY_ENABLED"] = settings.servicesDiscoveryProxyEnabled ? "true" : "false"
        env["LABTETHER_SERVICES_DISCOVERY_PROXY_TRAEFIK_ENABLED"] = settings.servicesDiscoveryProxyTraefikEnabled ? "true" : "false"
        env["LABTETHER_SERVICES_DISCOVERY_PROXY_CADDY_ENABLED"] = settings.servicesDiscoveryProxyCaddyEnabled ? "true" : "false"
        env["LABTETHER_SERVICES_DISCOVERY_PROXY_NPM_ENABLED"] = settings.servicesDiscoveryProxyNPMEnabled ? "true" : "false"
        env["LABTETHER_SERVICES_DISCOVERY_PORT_SCAN_ENABLED"] = settings.servicesDiscoveryPortScanEnabled ? "true" : "false"
        env["LABTETHER_SERVICES_DISCOVERY_PORT_SCAN_INCLUDE_LISTENING"] = settings.servicesDiscoveryPortScanIncludeListening ? "true" : "false"
        env["LABTETHER_SERVICES_DISCOVERY_PORT_SCAN_PORTS"] = settings.normalizedPortList(settings.servicesDiscoveryPortScanPorts)
        env["LABTETHER_SERVICES_DISCOVERY_LAN_SCAN_ENABLED"] = settings.servicesDiscoveryLANScanEnabled ? "true" : "false"
        env["LABTETHER_SERVICES_DISCOVERY_LAN_SCAN_CIDRS"] = settings.normalizedCIDRList(settings.servicesDiscoveryLANScanCIDRs)
        env["LABTETHER_SERVICES_DISCOVERY_LAN_SCAN_PORTS"] = settings.normalizedPortList(settings.servicesDiscoveryLANScanPorts)
        env["LABTETHER_SERVICES_DISCOVERY_LAN_SCAN_MAX_HOSTS"] = settings.normalizedLANScanMaxHosts()
        env["LABTETHER_TOKEN_FILE"] = settings.tokenFilePath
        env["LABTETHER_AGENT_SETTINGS_FILE"] = settings.agentSettingsFilePath
        env["LABTETHER_DEVICE_KEY_FILE"] = settings.deviceKeyFilePath
        env["LABTETHER_DEVICE_PUBLIC_KEY_FILE"] = settings.devicePublicKeyFilePath
        env["LABTETHER_DEVICE_FINGERPRINT_FILE"] = settings.deviceFingerprintFilePath
        env["LABTETHER_AGENT_LOCAL_AUTH_TOKEN_FILE"] = try settings.ensureLocalAPIAuthToken()

        // Include common GUI-safe executable paths so tools like tailscale are discoverable.
        env["PATH"] = settings.mergedExecutablePath()
        // Inherit HOME for SSH key operations
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            env["HOME"] = home
        }

        return env
    }
}
