import Foundation
import Security
import SwiftUI

struct AgentSettingsSecretError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

/// Owns preferences and credentials for one app state directory.
final class AgentSettings: ObservableObject {
    enum RuntimeSecretFileAction: Equatable {
        case persist
        case preserve
        case remove
    }

    static let apiTokenAccount = "apiToken"
    static let enrollmentTokenAccount = "enrollmentToken"
    static let webrtcTurnPassAccount = "webrtcTurnPass"
    // The bundled Go runtime supports WebRTC on Linux; macOS uses Screen Sharing.
    static let webRTCRuntimeSupported = false
    static let shared: AgentSettings = {
        do { return try AgentSettings(location: AppStateLocation.current) }
        catch { fputs("LabTether: state settings could not be loaded.\n", stderr); exit(78) }
    }()

    // swiftlint:disable:next private_over_fileprivate
    static let allowedDockerModes: Set<String> = ["auto", "true", "false"]
    // swiftlint:disable:next private_over_fileprivate
    static let allowedFileRootModes: Set<String> = ["home", "full"]
    // swiftlint:disable:next private_over_fileprivate
    static let allowedLogLevels: Set<String> = ["debug", "info", "warn", "error"]
    var isLoadingSecrets = false
    var secretPersistenceIssueMap: [String: String] = [:]
    let stateLocation: AppStateLocation?
    private let preferences: AgentPreferences
    private var loadingPreferences = false
    private var failedPreferences = Set<String>()
    private var defaultsObserver: NSObjectProtocol?
    let bootstrapSecrets: AgentBootstrapSecrets
    private let appSupportDirectoryOverride: URL?
    var allowsSystemIntegration: Bool { stateLocation?.isolated == false }
    @Published private(set) var preferencePersistenceError: String?
    var localAPIAuthToken: String = ""

    // Default to local secure hub.
    @Published var hubURL: String = "wss://localhost:8443/ws/agent" {
        didSet { savePreference(hubURL, key: "hubURL") }
    }
    @Published var enrollmentToken: String = "" {
        didSet { persistSecret(enrollmentToken, account: Self.enrollmentTokenAccount) }
    }
    @Published var apiToken: String = "" {
        didSet { persistSecret(apiToken, account: Self.apiTokenAccount) }
    }
    @Published var assetID: String = "" {
        didSet { savePreference(assetID, key: "assetID") }
    }
    @Published var groupID: String = "" {
        didSet { savePreference(groupID, key: "groupID") }
    }
    @Published var agentPort: String = "8091" {
        didSet { savePreference(agentPort, key: "agentPort") }
    }
    @Published var tlsSkipVerify: Bool = false {
        didSet { savePreference(tlsSkipVerify, key: "tlsSkipVerify") }
    }
    @Published var tlsCAFile: String = "" {
        didSet { savePreference(tlsCAFile, key: "tlsCAFile") }
    }
    @Published var dockerEnabled: String = "auto" {
        didSet { savePreference(dockerEnabled, key: "dockerEnabled") }
    }
    @Published var dockerEndpoint: String = "/var/run/docker.sock" {
        didSet { savePreference(dockerEndpoint, key: "dockerEndpoint") }
    }
    @Published var dockerDiscoveryIntervalSec: String = "30" {
        didSet { savePreference(dockerDiscoveryIntervalSec, key: "dockerDiscoveryIntervalSec") }
    }
    @Published var filesRootMode: String = "home" {
        didSet { savePreference(filesRootMode, key: "filesRootMode") }
    }
    @Published var allowRemoteOverrides: Bool = false {
        didSet { savePreference(allowRemoteOverrides, key: "allowRemoteOverrides") }
    }
    @Published var logLevel: String = "info" {
        didSet { savePreference(logLevel, key: "logLevel") }
    }
    @Published var webrtcEnabled: Bool = true {
        didSet { savePreference(webrtcEnabled, key: "webrtcEnabled") }
    }
    @Published var webrtcStunURL: String = "stun:stun.l.google.com:19302" {
        didSet { savePreference(webrtcStunURL, key: "webrtcStunURL") }
    }
    @Published var webrtcTurnURL: String = "" {
        didSet { savePreference(webrtcTurnURL, key: "webrtcTurnURL") }
    }
    @Published var webrtcTurnUser: String = "" {
        didSet { savePreference(webrtcTurnUser, key: "webrtcTurnUser") }
    }
    @Published var webrtcTurnPass: String = "" {
        didSet { persistSecret(webrtcTurnPass, account: Self.webrtcTurnPassAccount) }
    }
    @Published var captureFPS: String = "30" {
        didSet { savePreference(captureFPS, key: "captureFPS") }
    }

    var effectiveWebRTCEnabled: Bool {
        Self.webRTCRuntimeSupported && webrtcEnabled
    }
    @Published var servicesDiscoveryDockerEnabled: Bool = true {
        didSet { savePreference(servicesDiscoveryDockerEnabled, key: "servicesDiscoveryDockerEnabled") }
    }
    @Published var servicesDiscoveryProxyEnabled: Bool = true {
        didSet { savePreference(servicesDiscoveryProxyEnabled, key: "servicesDiscoveryProxyEnabled") }
    }
    @Published var servicesDiscoveryProxyTraefikEnabled: Bool = true {
        didSet { savePreference(servicesDiscoveryProxyTraefikEnabled, key: "servicesDiscoveryProxyTraefikEnabled") }
    }
    @Published var servicesDiscoveryProxyCaddyEnabled: Bool = true {
        didSet { savePreference(servicesDiscoveryProxyCaddyEnabled, key: "servicesDiscoveryProxyCaddyEnabled") }
    }
    @Published var servicesDiscoveryProxyNPMEnabled: Bool = true {
        didSet { savePreference(servicesDiscoveryProxyNPMEnabled, key: "servicesDiscoveryProxyNPMEnabled") }
    }
    @Published var servicesDiscoveryPortScanEnabled: Bool = true {
        didSet { savePreference(servicesDiscoveryPortScanEnabled, key: "servicesDiscoveryPortScanEnabled") }
    }
    @Published var servicesDiscoveryPortScanIncludeListening: Bool = true {
        didSet { savePreference(servicesDiscoveryPortScanIncludeListening, key: "servicesDiscoveryPortScanIncludeListening") }
    }
    @Published var servicesDiscoveryPortScanPorts: String = "" {
        didSet { savePreference(servicesDiscoveryPortScanPorts, key: "servicesDiscoveryPortScanPorts") }
    }
    @Published var servicesDiscoveryLANScanEnabled: Bool = false {
        didSet { savePreference(servicesDiscoveryLANScanEnabled, key: "servicesDiscoveryLANScanEnabled") }
    }
    @Published var servicesDiscoveryLANScanCIDRs: String = "" {
        didSet { savePreference(servicesDiscoveryLANScanCIDRs, key: "servicesDiscoveryLANScanCIDRs") }
    }
    @Published var servicesDiscoveryLANScanPorts: String = "" {
        didSet { savePreference(servicesDiscoveryLANScanPorts, key: "servicesDiscoveryLANScanPorts") }
    }
    @Published var servicesDiscoveryLANScanMaxHosts: String = "64" {
        didSet { savePreference(servicesDiscoveryLANScanMaxHosts, key: "servicesDiscoveryLANScanMaxHosts") }
    }
    @Published var startAtLogin: Bool = false {
        didSet { savePreference(startAtLogin, key: "startAtLogin") }
    }
    @Published var hasCompletedOnboarding: Bool = false {
        didSet { savePreference(hasCompletedOnboarding, key: "hasCompletedOnboarding") }
    }
    @Published var autoStart: Bool = true {
        didSet { savePreference(autoStart, key: "autoStart") }
    }
    @Published var menuBarDisplayMode: String = "standard" {
        didSet { savePreference(menuBarDisplayMode, key: "menuBarDisplayMode") }
    }
    /// Notify-only check for a newer signed app release. It never downloads.
    @Published var checkForAppUpdates: Bool = true {
        didSet { savePreference(checkForAppUpdates, key: "checkForAppUpdates") }
    }

    /// Incremented when settings are saved to signal a restart is needed.
    @Published var settingsVersion: Int = 0
    @Published var secretPersistenceErrors: [String] = []

    init(location: AppStateLocation) throws {
        stateLocation = location
        appSupportDirectoryOverride = location.root
        preferences = location.isolated ? try AgentPreferences(location: location) : AgentPreferences(defaults: .standard)
        bootstrapSecrets = AgentBootstrapSecrets(usesKeychain: !location.isolated)
        loadPreferences()
        loadSecretsFromKeychain()
        observeDefaults()
    }

    /// Test suites never read or write the owner's defaults or Keychain.
    init(testSettingsStore: UserDefaults, appSupportDirectory: URL) {
        stateLocation = nil
        appSupportDirectoryOverride = appSupportDirectory
        preferences = AgentPreferences(defaults: testSettingsStore)
        bootstrapSecrets = AgentBootstrapSecrets(usesKeychain: false)
        loadPreferences()
        observeDefaults()
    }

    deinit {
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
    }

    private func observeDefaults() {
        defaultsObserver = preferences.observeChanges { [weak self] in
            DispatchQueue.main.async { [weak self] in self?.loadPreferences() }
        }
    }

    private func savePreference(_ value: Any, key: String) {
        guard !loadingPreferences else { return }
        do { try preferences.set(value, key: key); failedPreferences.remove(key) }
        catch { failedPreferences.insert(key) }
        preferencePersistenceError = failedPreferences.isEmpty ? nil : "Settings could not be saved to the selected state directory."
    }

    private func loadPreferences() {
        loadingPreferences = true
        defer { loadingPreferences = false }
        hubURL = preferences.string("hubURL", default: "wss://localhost:8443/ws/agent")
        assetID = preferences.string("assetID", default: "")
        groupID = preferences.string("groupID", default: "")
        agentPort = preferences.string("agentPort", default: "8091")
        tlsSkipVerify = preferences.bool("tlsSkipVerify", default: false)
        tlsCAFile = preferences.string("tlsCAFile", default: "")
        dockerEnabled = preferences.string("dockerEnabled", default: "auto")
        dockerEndpoint = preferences.string("dockerEndpoint", default: "/var/run/docker.sock")
        dockerDiscoveryIntervalSec = preferences.string("dockerDiscoveryIntervalSec", default: "30")
        filesRootMode = preferences.string("filesRootMode", default: "home")
        allowRemoteOverrides = preferences.bool("allowRemoteOverrides", default: false)
        logLevel = preferences.string("logLevel", default: "info")
        webrtcEnabled = preferences.bool("webrtcEnabled", default: true)
        webrtcStunURL = preferences.string("webrtcStunURL", default: "stun:stun.l.google.com:19302")
        webrtcTurnURL = preferences.string("webrtcTurnURL", default: "")
        webrtcTurnUser = preferences.string("webrtcTurnUser", default: "")
        captureFPS = preferences.string("captureFPS", default: "30")
        servicesDiscoveryDockerEnabled = preferences.bool("servicesDiscoveryDockerEnabled", default: true)
        servicesDiscoveryProxyEnabled = preferences.bool("servicesDiscoveryProxyEnabled", default: true)
        servicesDiscoveryProxyTraefikEnabled = preferences.bool("servicesDiscoveryProxyTraefikEnabled", default: true)
        servicesDiscoveryProxyCaddyEnabled = preferences.bool("servicesDiscoveryProxyCaddyEnabled", default: true)
        servicesDiscoveryProxyNPMEnabled = preferences.bool("servicesDiscoveryProxyNPMEnabled", default: true)
        servicesDiscoveryPortScanEnabled = preferences.bool("servicesDiscoveryPortScanEnabled", default: true)
        servicesDiscoveryPortScanIncludeListening = preferences.bool("servicesDiscoveryPortScanIncludeListening", default: true)
        servicesDiscoveryPortScanPorts = preferences.string("servicesDiscoveryPortScanPorts", default: "")
        servicesDiscoveryLANScanEnabled = preferences.bool("servicesDiscoveryLANScanEnabled", default: false)
        servicesDiscoveryLANScanCIDRs = preferences.string("servicesDiscoveryLANScanCIDRs", default: "")
        servicesDiscoveryLANScanPorts = preferences.string("servicesDiscoveryLANScanPorts", default: "")
        servicesDiscoveryLANScanMaxHosts = preferences.string("servicesDiscoveryLANScanMaxHosts", default: "64")
        startAtLogin = preferences.bool("startAtLogin", default: false)
        hasCompletedOnboarding = preferences.bool("hasCompletedOnboarding", default: false)
        autoStart = preferences.bool("autoStart", default: true)
        menuBarDisplayMode = preferences.string("menuBarDisplayMode", default: "standard")
        checkForAppUpdates = preferences.bool("checkForAppUpdates", default: true)
    }

    /// Update-check bookkeeping. Values stay strings because isolated JSON
    /// preferences accept only strings and booleans.
    func appUpdateRecord(_ key: String) -> String {
        preferences.string(key, default: "")
    }

    func setAppUpdateRecord(_ value: String, key: String) {
        savePreference(value, key: key)
    }

    /// Whether the minimum required config is present to start the agent.
    var isConfigured: Bool {
        normalizedHubWebSocketURL() != nil &&
        Self.minimumCredentialConfigured(
            apiToken: apiToken,
            enrollmentToken: enrollmentToken,
            hasPersistedAgentToken: hasPersistedAgentToken,
            hasPersistedEnrollmentToken: hasPersistedEnrollmentToken
        )
    }

    /// Whether a previously enrolled agent credential is available on disk.
    /// The Go child owns and validates the credential contents; the native host
    /// only treats a non-empty, private regular file as configured state.
    var hasPersistedAgentToken: Bool {
        Self.hasPrivatePersistedAgentToken(at: tokenFilePath)
    }

    /// Whether a local installer or automation supplied the private,
    /// non-empty enrollment-token file consumed by the bundled Go agent.
    var hasPersistedEnrollmentToken: Bool {
        Self.hasPrivatePersistedAgentToken(at: enrollmentTokenFilePath)
    }

    /// Bump the settings version to signal that a restart may be needed.
    func markChanged() {
        settingsVersion += 1
    }

    var appSupportDirectory: URL {
        if let stateLocation { return stateLocation.root }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupportDirectoryOverride ?? appSupport.appendingPathComponent("LabTether")
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

    static func runtimeAPITokenFileAction(
        apiToken: String,
        enrollmentToken: String,
        hasPersistedAgentToken: Bool
    ) -> RuntimeSecretFileAction {
        let trimmed = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return .persist
        }
        if !enrollmentToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            hasPersistedAgentToken {
            return .preserve
        }
        return .remove
    }

    static func minimumCredentialConfigured(
        apiToken: String,
        enrollmentToken: String,
        hasPersistedAgentToken: Bool,
        hasPersistedEnrollmentToken: Bool = false
    ) -> Bool {
        !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !enrollmentToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            hasPersistedAgentToken ||
            hasPersistedEnrollmentToken
    }

    static func runtimeEnrollmentTokenFileAction(
        enrollmentToken: String,
        hasPersistedEnrollmentToken: Bool
    ) -> RuntimeSecretFileAction {
        if !enrollmentToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .persist
        }
        return hasPersistedEnrollmentToken ? .preserve : .remove
    }

    static func hasPrivatePersistedAgentToken(at path: String) -> Bool {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber,
              size.intValue > 0,
              let permissions = attributes[.posixPermissions] as? NSNumber else {
            return false
        }
        return permissions.intValue & 0o077 == 0
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

    func normalizedAgentPort() -> String {
        let trimmed = agentPort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = AgentSettingsNormalization.strictDecimalInteger(trimmed, in: 1...65535) else {
            return "8091"
        }
        return String(value)
    }

    func normalizedDockerDiscoveryInterval() -> String {
        let trimmed = dockerDiscoveryIntervalSec.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = AgentSettingsNormalization.strictDecimalInteger(trimmed) else { return "30" }
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
        guard let value = AgentSettingsNormalization.strictDecimalInteger(trimmed) else { return "30" }
        if value < 5 { return "5" }
        if value > 120 { return "120" }
        return String(value)
    }

    func normalizedLANScanMaxHosts() -> String {
        let trimmed = servicesDiscoveryLANScanMaxHosts.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = AgentSettingsNormalization.strictDecimalInteger(trimmed) else { return "64" }
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

}
