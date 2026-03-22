import Foundation
import Security
import SwiftUI

private struct AgentSettingsSecretError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

/// Maps @AppStorage UserDefaults properties to Go agent environment variables.
final class AgentSettings: ObservableObject {
    enum RuntimeSecretFileAction: Equatable {
        case persist
        case remove
    }

    private static let settingsStore: UserDefaults = .standard
    private static let apiTokenAccount = "apiToken"
    private static let enrollmentTokenAccount = "enrollmentToken"
    private static let webrtcTurnPassAccount = "webrtcTurnPass"
    static let webRTCRuntimeSupported = true
    static let shared = AgentSettings()

    // swiftlint:disable:next private_over_fileprivate
    static let allowedDockerModes: Set<String> = ["auto", "true", "false"]
    // swiftlint:disable:next private_over_fileprivate
    static let allowedFileRootModes: Set<String> = ["home", "full"]
    // swiftlint:disable:next private_over_fileprivate
    static let allowedLogLevels: Set<String> = ["debug", "info", "warn", "error"]
    private var isLoadingSecrets = false
    private var secretPersistenceIssueMap: [String: String] = [:]
    private(set) var localAPIAuthToken: String = ""

    // Default to local secure hub.
    @AppStorage("hubURL", store: settingsStore) var hubURL: String = "wss://localhost:8443/ws/agent"
    @Published var enrollmentToken: String = "" {
        didSet { persistSecret(enrollmentToken, account: Self.enrollmentTokenAccount) }
    }
    @Published var apiToken: String = "" {
        didSet { persistSecret(apiToken, account: Self.apiTokenAccount) }
    }
    @AppStorage("assetID", store: settingsStore) var assetID: String = ""
    @AppStorage("groupID", store: settingsStore) var groupID: String = ""
    @AppStorage("agentPort", store: settingsStore) var agentPort: String = "8091"
    @AppStorage("tlsSkipVerify", store: settingsStore) var tlsSkipVerify: Bool = false
    @AppStorage("tlsCAFile", store: settingsStore) var tlsCAFile: String = ""
    @AppStorage("dockerEnabled", store: settingsStore) var dockerEnabled: String = "auto"
    @AppStorage("dockerEndpoint", store: settingsStore) var dockerEndpoint: String = "/var/run/docker.sock"
    @AppStorage("dockerDiscoveryIntervalSec", store: settingsStore) var dockerDiscoveryIntervalSec: String = "30"
    @AppStorage("filesRootMode", store: settingsStore) var filesRootMode: String = "home"
    @AppStorage("autoUpdateEnabled", store: settingsStore) var autoUpdateEnabled: Bool = true
    @AppStorage("allowRemoteOverrides", store: settingsStore) var allowRemoteOverrides: Bool = false
    @AppStorage("logLevel", store: settingsStore) var logLevel: String = "info"
    @AppStorage("webrtcEnabled", store: settingsStore) var webrtcEnabled: Bool = true
    @AppStorage("webrtcStunURL", store: settingsStore) var webrtcStunURL: String = "stun:stun.l.google.com:19302"
    @AppStorage("webrtcTurnURL", store: settingsStore) var webrtcTurnURL: String = ""
    @AppStorage("webrtcTurnUser", store: settingsStore) var webrtcTurnUser: String = ""
    @Published var webrtcTurnPass: String = "" {
        didSet { persistSecret(webrtcTurnPass, account: Self.webrtcTurnPassAccount) }
    }
    @AppStorage("captureFPS", store: settingsStore) var captureFPS: String = "30"

    var effectiveWebRTCEnabled: Bool {
        Self.webRTCRuntimeSupported && webrtcEnabled
    }
    @AppStorage("servicesDiscoveryDockerEnabled", store: settingsStore) var servicesDiscoveryDockerEnabled: Bool = true
    @AppStorage("servicesDiscoveryProxyEnabled", store: settingsStore) var servicesDiscoveryProxyEnabled: Bool = true
    @AppStorage("servicesDiscoveryProxyTraefikEnabled", store: settingsStore) var servicesDiscoveryProxyTraefikEnabled: Bool = true
    @AppStorage("servicesDiscoveryProxyCaddyEnabled", store: settingsStore) var servicesDiscoveryProxyCaddyEnabled: Bool = true
    @AppStorage("servicesDiscoveryProxyNPMEnabled", store: settingsStore) var servicesDiscoveryProxyNPMEnabled: Bool = true
    @AppStorage("servicesDiscoveryPortScanEnabled", store: settingsStore) var servicesDiscoveryPortScanEnabled: Bool = true
    @AppStorage("servicesDiscoveryPortScanIncludeListening", store: settingsStore) var servicesDiscoveryPortScanIncludeListening: Bool = true
    @AppStorage("servicesDiscoveryPortScanPorts", store: settingsStore) var servicesDiscoveryPortScanPorts: String = ""
    @AppStorage("servicesDiscoveryLANScanEnabled", store: settingsStore) var servicesDiscoveryLANScanEnabled: Bool = false
    @AppStorage("servicesDiscoveryLANScanCIDRs", store: settingsStore) var servicesDiscoveryLANScanCIDRs: String = ""
    @AppStorage("servicesDiscoveryLANScanPorts", store: settingsStore) var servicesDiscoveryLANScanPorts: String = ""
    @AppStorage("servicesDiscoveryLANScanMaxHosts", store: settingsStore) var servicesDiscoveryLANScanMaxHosts: String = "64"
    @AppStorage("startAtLogin", store: settingsStore) var startAtLogin: Bool = false
    @AppStorage("hasCompletedOnboarding", store: settingsStore) var hasCompletedOnboarding: Bool = false
    @AppStorage("autoStart", store: settingsStore) var autoStart: Bool = true
    @AppStorage("menuBarDisplayMode", store: settingsStore) var menuBarDisplayMode: String = "standard"

    /// Incremented when settings are saved to signal a restart is needed.
    @Published var settingsVersion: Int = 0
    @Published private(set) var secretPersistenceErrors: [String] = []

    private init() {
        loadSecretsFromKeychain()
    }

    /// Whether the minimum required config is present to start the agent.
    var isConfigured: Bool {
        normalizedHubWebSocketURL() != nil &&
        (!apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !enrollmentToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// Bump the settings version to signal that a restart may be needed.
    func markChanged() {
        settingsVersion += 1
    }

    var appSupportDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("LabTether")
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        return dir
    }

    /// Token file path in Application Support (user-writable, no root needed).
    var tokenFilePath: String {
        appSupportDirectory.appendingPathComponent("agent-token").path
    }

    var enrollmentTokenFilePath: String {
        appSupportDirectory.appendingPathComponent("enrollment-token").path
    }

    var webrtcTurnPassFilePath: String {
        appSupportDirectory.appendingPathComponent("webrtc-turn-pass").path
    }

    var localAPIAuthTokenFilePath: String {
        appSupportDirectory.appendingPathComponent("local-api-auth-token").path
    }

    /// Persisted runtime setting overrides file (avoids non-writable /etc defaults on macOS).
    var agentSettingsFilePath: String {
        appSupportDirectory.appendingPathComponent("agent-config.json").path
    }

    /// Device identity paths (private/public/fingerprint).
    var deviceKeyFilePath: String {
        appSupportDirectory.appendingPathComponent("device-key").path
    }

    var devicePublicKeyFilePath: String {
        appSupportDirectory.appendingPathComponent("device-key.pub").path
    }

    var deviceFingerprintFilePath: String {
        appSupportDirectory.appendingPathComponent("device-fingerprint").path
    }

    /// Derive HTTP console URL from the configured WebSocket URL.
    /// Preserves the user's explicit port; defaults to 3000 only if no port is specified.
    var consoleURL: URL? {
        guard let wsURL = normalizedHubWebSocketURL() else { return nil }
        var urlString = wsURL
        urlString = urlString.replacingOccurrences(of: "ws://", with: "http://")
        urlString = urlString.replacingOccurrences(of: "wss://", with: "https://")
        guard let url = URL(string: urlString),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.path = ""
        // Only default to port 3000 if the user's URL has no explicit port
        if components.port == nil {
            components.port = 3000
        }
        return components.url
    }

    /// Build the environment dictionary for the Go agent process.
    func buildEnvironment() throws -> [String: String] {
        try AgentEnvironmentBuilder.buildEnvironment(from: self)
    }

    func validationErrors() -> [String] {
        AgentSettingsValidator.validationErrors(for: self)
    }

    func normalizedHubWebSocketURL() -> String? {
        AgentSettingsNormalization.canonicalHubWebSocketURL(from: hubURL)
    }

    static func runtimeAPITokenFileAction(apiToken: String) -> RuntimeSecretFileAction {
        let trimmed = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? .remove : .persist
    }

    func normalizedDockerMode() -> String {
        let mode = dockerEnabled.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if Self.allowedDockerModes.contains(mode) {
            return mode
        }
        return "auto"
    }

    func normalizedDockerEndpoint() -> String {
        let endpoint = dockerEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if endpoint.isEmpty {
            return "/var/run/docker.sock"
        }
        return endpoint
    }

    func normalizedDockerDiscoveryInterval() -> String {
        let trimmed = dockerDiscoveryIntervalSec.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed) else { return "30" }
        if value < 5 { return "5" }
        if value > 3600 { return "3600" }
        return String(value)
    }

    func normalizedFilesRootMode() -> String {
        let mode = filesRootMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if Self.allowedFileRootModes.contains(mode) {
            return mode
        }
        return "home"
    }

    func normalizedLogLevel() -> String {
        let level = logLevel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if Self.allowedLogLevels.contains(level) {
            return level
        }
        return "info"
    }

    func normalizedWebRTCSTUNURL() -> String {
        let value = webrtcStunURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            return "stun:stun.l.google.com:19302"
        }
        return value
    }

    func normalizedCaptureFPS() -> String {
        let trimmed = captureFPS.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed) else { return "30" }
        if value < 5 { return "5" }
        if value > 120 { return "120" }
        return String(value)
    }

    func normalizedLANScanMaxHosts() -> String {
        let trimmed = servicesDiscoveryLANScanMaxHosts.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed) else { return "64" }
        if value < 1 { return "1" }
        if value > 1024 { return "1024" }
        return String(value)
    }

    func normalizedPortList(_ raw: String) -> String {
        if let normalized = AgentSettingsNormalization.normalizedPortList(raw) {
            return normalized
        }
        return ""
    }

    func normalizedCIDRList(_ raw: String) -> String {
        if let normalized = AgentSettingsNormalization.normalizedCIDRList(raw) {
            return normalized
        }
        return ""
    }

    func dockerEndpointValidationError(_ raw: String) -> String? {
        AgentSettingsNormalization.dockerEndpointValidationError(raw)
    }

    private func loadSecretsFromKeychain() {
        isLoadingSecrets = true
        apiToken = KeychainSecretStore.load(account: Self.apiTokenAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        enrollmentToken = KeychainSecretStore.load(account: Self.enrollmentTokenAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        webrtcTurnPass = KeychainSecretStore.load(account: Self.webrtcTurnPassAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        isLoadingSecrets = false
    }

    private func persistSecret(_ rawValue: String, account: String) {
        if isLoadingSecrets {
            return
        }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let issueKey = keychainIssueKey(for: account)
        if value.isEmpty {
            let status = KeychainSecretStore.deleteStatus(account: account)
            if status == errSecSuccess {
                setSecretPersistenceIssue(key: issueKey, message: nil)
                synchronizeRuntimeSecretFilesAfterSecretChange(account: account)
            } else {
                setSecretPersistenceIssue(
                    key: issueKey,
                    message: "\(secretLabel(for: account)) could not be removed from the macOS Keychain: \(KeychainSecretStore.errorMessage(for: status))"
                )
            }
            return
        }
        let status = KeychainSecretStore.saveStatus(value, account: account)
        if status == errSecSuccess {
            setSecretPersistenceIssue(key: issueKey, message: nil)
        } else {
            setSecretPersistenceIssue(
                key: issueKey,
                message: "\(secretLabel(for: account)) could not be saved to the macOS Keychain: \(KeychainSecretStore.errorMessage(for: status))"
            )
        }
    }

    func mergedExecutablePath() -> String {
        let defaults = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "/Applications/Tailscale.app/Contents/MacOS",
        ]

        var combined: [String] = []
        if let inherited = ProcessInfo.processInfo.environment["PATH"] {
            combined.append(contentsOf: inherited.split(separator: ":").map(String.init))
        }
        combined.append(contentsOf: defaults)

        var seen = Set<String>()
        let deduped = combined.filter { part in
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            if seen.contains(trimmed) { return false }
            seen.insert(trimmed)
            return true
        }
        return deduped.joined(separator: ":")
    }

    func cleanupEphemeralSecrets() {
        try? removeRuntimeSecretIfNeeded(
            at: localAPIAuthTokenFilePath,
            issueKey: "runtime.localAPIAuthToken",
            label: "Local API auth token"
        )
        localAPIAuthToken = ""
    }

    private func synchronizeRuntimeSecretFilesAfterSecretChange(account: String) {
        switch account {
        case Self.apiTokenAccount:
            if Self.runtimeAPITokenFileAction(apiToken: apiToken) == .remove {
                try? removeRuntimeSecretIfNeeded(
                    at: tokenFilePath,
                    issueKey: "runtime.apiToken",
                    label: "API token"
                )
            }
        case Self.enrollmentTokenAccount:
            try? removeRuntimeSecretIfNeeded(
                at: enrollmentTokenFilePath,
                issueKey: "runtime.enrollmentToken",
                label: "Enrollment token"
            )
            if Self.runtimeAPITokenFileAction(apiToken: apiToken) == .remove {
                try? removeRuntimeSecretIfNeeded(
                    at: tokenFilePath,
                    issueKey: "runtime.apiToken",
                    label: "API token"
                )
            }
        case Self.webrtcTurnPassAccount:
            try? removeRuntimeSecretIfNeeded(
                at: webrtcTurnPassFilePath,
                issueKey: "runtime.turnPass",
                label: "WebRTC TURN password"
            )
        default:
            break
        }
    }

    func persistRuntimeSecret(_ value: String, to path: String, issueKey: String, label: String) throws {
        let fileURL = URL(fileURLWithPath: path)
        let parent = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
            try (value + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
            setSecretPersistenceIssue(key: issueKey, message: nil)
        } catch {
            let message = "\(label) could not be written to \(path): \(error.localizedDescription)"
            setSecretPersistenceIssue(key: issueKey, message: message)
            throw AgentSettingsSecretError(message: message)
        }
    }

    func removeRuntimeSecretIfNeeded(at path: String, issueKey: String, label: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            setSecretPersistenceIssue(key: issueKey, message: nil)
            return
        }
        do {
            try FileManager.default.removeItem(atPath: path)
            setSecretPersistenceIssue(key: issueKey, message: nil)
        } catch {
            let message = "\(label) could not be removed from \(path): \(error.localizedDescription)"
            setSecretPersistenceIssue(key: issueKey, message: message)
            throw AgentSettingsSecretError(message: message)
        }
    }

    func ensureLocalAPIAuthToken() throws -> String {
        if localAPIAuthToken.isEmpty {
            localAPIAuthToken = generateLocalAPIAuthToken()
        }
        try persistRuntimeSecret(
            localAPIAuthToken,
            to: localAPIAuthTokenFilePath,
            issueKey: "runtime.localAPIAuthToken",
            label: "Local API auth token"
        )
        return localAPIAuthTokenFilePath
    }

    private func generateLocalAPIAuthToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return bytes.map { String(format: "%02x", $0) }.joined()
        }
        return UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    private func keychainIssueKey(for account: String) -> String {
        "keychain.\(account)"
    }

    private func secretLabel(for account: String) -> String {
        switch account {
        case Self.apiTokenAccount:
            return "API token"
        case Self.enrollmentTokenAccount:
            return "Enrollment token"
        case Self.webrtcTurnPassAccount:
            return "WebRTC TURN password"
        default:
            return "Secret"
        }
    }

    private func setSecretPersistenceIssue(key: String, message: String?) {
        if let message, !message.isEmpty {
            secretPersistenceIssueMap[key] = message
        } else {
            secretPersistenceIssueMap.removeValue(forKey: key)
        }
        secretPersistenceErrors = secretPersistenceIssueMap.keys.sorted().compactMap { secretPersistenceIssueMap[$0] }
    }
}
