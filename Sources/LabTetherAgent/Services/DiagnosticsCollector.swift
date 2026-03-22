import Foundation

/// Builds a markdown-formatted diagnostics report from plain value parameters.
///
/// Accepting plain values (rather than observable objects) makes this type
/// fully testable without instantiating the app's object graph.
enum DiagnosticsCollector {

    // MARK: - Public API

    /// Assembles a diagnostics report string suitable for copying to the clipboard.
    ///
    /// - Parameters:
    ///   - appVersion: Short version string from Info.plist (e.g. "1.0.0").
    ///   - buildNumber: Build number from Info.plist (e.g. "42").
    ///   - agentVersion: Version reported by the running Go agent, or `nil` when not running.
    ///   - osVersion: Human-readable macOS version (e.g. "macOS 15.0 (24A336)").
    ///   - architecture: CPU architecture string (e.g. "arm64").
    ///   - hubURL: Raw hub URL string as entered by the user.
    ///   - connectionState: Current agent connection state raw value (e.g. "connected").
    ///   - apiTokenConfigured: Whether a non-empty API token is stored.
    ///   - enrollmentTokenConfigured: Whether a non-empty enrollment token is stored.
    ///   - assetID: Asset ID, preferring the live value reported by the agent.
    ///   - groupID: Group ID from settings.
    ///   - pid: Process ID of the running agent process, or `nil`.
    ///   - uptime: Human-readable uptime string from the agent, or `nil`.
    ///   - tlsSkipVerify: Whether TLS certificate verification is disabled.
    ///   - dockerMode: Normalised docker mode string (e.g. "auto", "true", "false").
    ///   - filesRootMode: Normalised files root mode (e.g. "home", "full").
    ///   - allowRemoteOverrides: Whether remote setting overrides are enabled.
    ///   - logLevel: Normalised log level string (e.g. "info", "debug").
    ///   - webrtcEnabled: Whether WebRTC is enabled (respects runtime support flag).
    ///   - screenSharingEnabled: Whether macOS Screen Sharing is active.
    ///   - screenSharingControlAccess: Whether the current user has full control (vs. observe-only).
    ///   - validationErrors: Settings validation errors from `AgentSettingsValidator`.
    ///   - secretPersistenceErrors: Keychain/file write errors from `AgentSettings`.
    ///   - logSummaryLines: Pre-built summary lines from `DiagnosticsLogSummary`.
    /// - Returns: A markdown-formatted diagnostics report string.
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
        let iso8601 = ISO8601DateFormatter().string(from: Date())
        var sections: [String] = []

        // Header
        sections.append("## LabTether Diagnostics Report")
        sections.append("Generated: \(iso8601)")

        // Application
        sections.append("""

            ### Application
            - App Version: \(appVersion) (\(buildNumber))
            - Agent Version: \(agentVersion ?? "Not running")
            - OS: \(osVersion) (\(architecture))
            """)

        // Connection
        let groupIDDisplay = groupID.isEmpty ? "(none)" : groupID
        let pidDisplay = pid.map { String($0) } ?? "none"
        let uptimeDisplay = uptime ?? "n/a"
        sections.append("""

            ### Connection
            - Hub URL: \(hubURL)
            - Connection State: \(connectionState)
            - API Token: \(apiTokenConfigured ? "configured" : "not configured")
            - Enrollment Token: \(enrollmentTokenConfigured ? "configured" : "not configured")
            - Asset ID: \(assetID)
            - Group ID: \(groupIDDisplay)
            - PID: \(pidDisplay)
            - Uptime: \(uptimeDisplay)
            """)

        // Configuration
        sections.append("""

            ### Configuration
            - TLS Skip Verify: \(tlsSkipVerify)
            - Docker Mode: \(dockerMode)
            - Files Root Mode: \(filesRootMode)
            - Allow Remote Overrides: \(allowRemoteOverrides)
            - Log Level: \(logLevel)
            - WebRTC Enabled: \(webrtcEnabled)
            """)

        // Screen Sharing
        sections.append("""

            ### Screen Sharing
            - Status: \(screenSharingEnabled ? "enabled" : "disabled")
            - Control Access: \(screenSharingControlAccess ? "full control" : "observe only")
            """)

        // Issues (only when present)
        let allErrors = validationErrors + secretPersistenceErrors
        if !allErrors.isEmpty {
            let errorLines = allErrors.map { "- \($0)" }.joined(separator: "\n")
            sections.append("""

                ### Issues
                \(errorLines)
                """)
        }

        // Log Summary (only when present)
        if !logSummaryLines.isEmpty {
            let logLines = logSummaryLines.map { "- \($0)" }.joined(separator: "\n")
            sections.append("""

                ### Log Summary
                \(logLines)
                """)
        }

        return sections.joined(separator: "\n")
    }
}
