import Foundation

/// Response from the agent's /agent/status endpoint.
struct AgentStatusResponse: Codable, Equatable, Sendable {
    let agentName: String
    let assetID: String
    let groupID: String?
    let port: String
    let deviceFingerprint: String?
    let deviceKeyAlgorithm: String?
    let connected: Bool
    let connectionState: String?   // "connected", "connecting", "auth_failed", "disconnected"
    let disconnectedAt: Date?
    let lastError: String?
    let uptime: String?
    let startedAt: Date?
    let localBindAddress: String?
    let localAuthEnabled: Bool?
    let allowInsecureTransport: Bool?
    let metrics: MetricsSnapshot
    let alerts: [AlertSnapshot]
    let agentVersion: String?
    let updateAvailable: Bool?
    let latestVersion: String?

    enum CodingKeys: String, CodingKey {
        case agentName = "agent_name"
        case assetID = "asset_id"
        case groupID = "group_id"
        case port, connected, uptime
        case deviceFingerprint = "device_fingerprint"
        case deviceKeyAlgorithm = "device_key_algorithm"
        case connectionState = "connection_state"
        case disconnectedAt = "disconnected_at"
        case lastError = "last_error"
        case startedAt = "started_at"
        case localBindAddress = "local_bind_address"
        case localAuthEnabled = "local_auth_enabled"
        case allowInsecureTransport = "allow_insecure_transport"
        case metrics, alerts
        case agentVersion = "agent_version"
        case updateAvailable = "update_available"
        case latestVersion = "latest_version"
    }
}

struct MetricsSnapshot: Codable, Equatable, Sendable {
    let cpuPercent: Double
    let memoryPercent: Double
    let diskPercent: Double
    let netRXBytesPerSec: Double
    let netTXBytesPerSec: Double
    let tempCelsius: Double?
    let collectedAt: Date?

    enum CodingKeys: String, CodingKey {
        case cpuPercent = "cpu_percent"
        case memoryPercent = "memory_percent"
        case diskPercent = "disk_percent"
        case netRXBytesPerSec = "net_rx_bytes_per_sec"
        case netTXBytesPerSec = "net_tx_bytes_per_sec"
        case tempCelsius = "temp_celsius"
        case collectedAt = "collected_at"
    }
}

struct AlertSnapshot: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let severity: String
    let title: String
    let summary: String
    let state: String
    let timestamp: Date?
}
