import Foundation
import os

// Every date in `/agent/status` is display-only: no date decides the
// connection state, the status word or the line under it. So a date the app
// cannot read becomes nil and is logged once per field, and the rest of the
// status still shows. Before, one unreadable date failed the whole read and
// the menu stayed on "Status unavailable". A date of the wrong JSON type
// (not a string) still fails: the contract allows only strings there.

enum StatusDateLog {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.labtether.agent",
        category: "LocalAPI"
    )
    private static let logged = OSAllocatedUnfairLock(initialState: Set<String>())

    static func unreadable(_ field: String) {
        let first = logged.withLock { $0.insert(field).inserted }
        if first {
            logger.error("Agent status: \(field, privacy: .public) is not a readable time; shown as unknown")
        }
    }
}

extension KeyedDecodingContainer {
    /// A date through the decoder's date strategy, or nil when it is absent,
    /// null or unreadable text.
    func decodeStatusDate(forKey key: Key, field: String) throws -> Date? {
        do {
            return try decodeIfPresent(Date.self, forKey: key)
        } catch DecodingError.dataCorrupted {
            StatusDateLog.unreadable(field)
            return nil
        }
    }
}

extension AgentStatusResponse {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            agentName: try c.decode(String.self, forKey: .agentName),
            assetID: try c.decode(String.self, forKey: .assetID),
            groupID: try c.decodeIfPresent(String.self, forKey: .groupID),
            port: try c.decode(String.self, forKey: .port),
            deviceFingerprint: try c.decodeIfPresent(String.self, forKey: .deviceFingerprint),
            deviceKeyAlgorithm: try c.decodeIfPresent(String.self, forKey: .deviceKeyAlgorithm),
            connected: try c.decode(Bool.self, forKey: .connected),
            connectionState: try c.decodeIfPresent(String.self, forKey: .connectionState),
            disconnectedAt: try c.decodeStatusDate(forKey: .disconnectedAt, field: "disconnected_at"),
            lastError: try c.decodeIfPresent(String.self, forKey: .lastError),
            lastErrorReason: try c.decodeIfPresent(String.self, forKey: .lastErrorReason),
            uptime: try c.decodeIfPresent(String.self, forKey: .uptime),
            startedAt: try c.decodeStatusDate(forKey: .startedAt, field: "started_at"),
            localBindAddress: try c.decodeIfPresent(String.self, forKey: .localBindAddress),
            localAuthEnabled: try c.decodeIfPresent(Bool.self, forKey: .localAuthEnabled),
            allowInsecureTransport: try c.decodeIfPresent(Bool.self, forKey: .allowInsecureTransport),
            metrics: try c.decode(MetricsSnapshot.self, forKey: .metrics),
            alerts: try c.decode([AlertSnapshot].self, forKey: .alerts),
            agentVersion: try c.decodeIfPresent(String.self, forKey: .agentVersion),
            updateAvailable: try c.decodeIfPresent(Bool.self, forKey: .updateAvailable),
            latestVersion: try c.decodeIfPresent(String.self, forKey: .latestVersion),
            enrollmentError: try c.decodeIfPresent(String.self, forKey: .enrollmentError)
        )
    }
}

extension MetricsSnapshot {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            cpuPercent: try c.decode(Double.self, forKey: .cpuPercent),
            memoryPercent: try c.decode(Double.self, forKey: .memoryPercent),
            diskPercent: try c.decode(Double.self, forKey: .diskPercent),
            netRXBytesPerSec: try c.decode(Double.self, forKey: .netRXBytesPerSec),
            netTXBytesPerSec: try c.decode(Double.self, forKey: .netTXBytesPerSec),
            tempCelsius: try c.decodeIfPresent(Double.self, forKey: .tempCelsius),
            collectedAt: try c.decodeStatusDate(forKey: .collectedAt, field: "metrics.collected_at")
        )
    }
}

extension AlertSnapshot {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            severity: try c.decode(String.self, forKey: .severity),
            title: try c.decode(String.self, forKey: .title),
            summary: try c.decode(String.self, forKey: .summary),
            state: try c.decode(String.self, forKey: .state),
            timestamp: try c.decodeStatusDate(forKey: .timestamp, field: "alerts.timestamp")
        )
    }
}
