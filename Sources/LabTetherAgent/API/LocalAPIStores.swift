import Foundation

// Published snapshots of the agent's local status, one store per screen area.

struct LocalAPIRuntimeSnapshot: Equatable {
    var isReachable = false
    var hubConnectionState = "disconnected"
    /// The agent's time for the end of the last connection, when it sent one.
    var disconnectedAt: Date?
    var assetID: String?
    var uptime: String?
    var lastError: String?
    var lastErrorReason: String?
    /// The Hub's words for a refused enrollment, while not connected.
    var enrollmentError: String?
    /// The agent's local endpoint refused this app's token (HTTP 401). This
    /// says nothing about the Hub, so `hubConnectionState` stays unknown.
    var localStatusRefused = false
}

@MainActor
final class LocalAPIRuntimeStore: ObservableObject {
    @Published private(set) var snapshot = LocalAPIRuntimeSnapshot()

    func publish(_ nextSnapshot: LocalAPIRuntimeSnapshot) {
        guard snapshot != nextSnapshot else { return }
        snapshot = nextSnapshot
    }

    func reset() {
        publish(LocalAPIRuntimeSnapshot())
    }
}

struct LocalAPIMetricsSnapshot: Equatable {
    var current: MetricsSnapshot?
    var history = MetricsHistory()
    var presentation: LocalAPIMetricsPresentation?
}

@MainActor
final class LocalAPIMetricsStore: ObservableObject {
    @Published private(set) var snapshot = LocalAPIMetricsSnapshot()

    func publish(_ nextSnapshot: LocalAPIMetricsSnapshot) {
        guard snapshot != nextSnapshot else { return }
        snapshot = nextSnapshot
    }

    func reset(clearHistory: Bool = true) {
        let history = clearHistory ? MetricsHistory() : snapshot.history
        publish(
            LocalAPIMetricsSnapshot(
                current: nil,
                history: history,
                presentation: nil
            )
        )
    }
}

struct LocalAPIAlertsSnapshot: Equatable {
    var alerts: [AlertSnapshot] = []
    var firingAlerts: [AlertSnapshot] = []
    var hasCriticalFiring = false

    init(alerts: [AlertSnapshot] = []) {
        self.alerts = alerts
        self.firingAlerts = alerts.filter { $0.state == "firing" }
        self.hasCriticalFiring = firingAlerts.contains { $0.severity == "critical" }
    }
}

@MainActor
final class LocalAPIAlertsStore: ObservableObject {
    @Published private(set) var snapshot = LocalAPIAlertsSnapshot()

    func publish(_ nextSnapshot: LocalAPIAlertsSnapshot) {
        guard snapshot != nextSnapshot else { return }
        snapshot = nextSnapshot
    }

    func reset() {
        publish(LocalAPIAlertsSnapshot())
    }
}

struct LocalAPIMetadataSnapshot: Equatable {
    var agentVersion: String?
    var updateAvailable = false
    var latestVersion: String?
    var deviceFingerprint: String?
    var localBindAddress: String?
    var localAuthEnabled: Bool?
    var allowInsecureTransport: Bool?
}

@MainActor
final class LocalAPIMetadataStore: ObservableObject {
    @Published private(set) var snapshot = LocalAPIMetadataSnapshot()

    func publish(_ nextSnapshot: LocalAPIMetadataSnapshot) {
        guard snapshot != nextSnapshot else { return }
        snapshot = nextSnapshot
    }

    func reset() {
        publish(LocalAPIMetadataSnapshot())
    }
}
