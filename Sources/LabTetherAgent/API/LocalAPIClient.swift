import Foundation
import Network

struct LocalAPIRuntimeSnapshot: Equatable {
    var isReachable = false
    var hubConnectionState = "disconnected"
    var uptime: String?
    var lastError: String?
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

// MARK: - LocalAPIClient

/// Polls the Go agent's local HTTP API for metrics, status, and alerts.
///
/// Polling strategy:
/// - Any visible surface (menu popover or pop-out panel): 5s base interval.
/// - Fully hidden: 30s base interval (slow path to reduce background overhead).
/// - Exponential backoff on consecutive failures: base × 2^(n-1), capped at 60s.
/// - NWPathMonitor triggers an immediate poll and interval reset on network recovery.
/// - Visibility-aware polling is controlled by `setMenuVisible(_:)` and
///   `setPanelVisible(_:)`.
@MainActor
final class LocalAPIClient: ObservableObject {
    @Published private(set) var status: AgentStatusResponse?
    let runtime = LocalAPIRuntimeStore()
    let metrics = LocalAPIMetricsStore()
    let alerts = LocalAPIAlertsStore()
    let metadata = LocalAPIMetadataStore()

    private var statusTimer: Timer?
    private var pollTask: Task<Void, Never>?
    private var isPolling: Bool = false
    private let session: URLSession
    private var baseURL: String = "http://127.0.0.1:8091"
    private var authToken: String?
    private(set) var knownAlertIDs: Set<String> = []
    private var statusETag: String?
    private var latestStatusSnapshot: AgentStatusResponse?
    private var latestReachable: Bool = false
    private var latestHubConnectionState: String = "disconnected"

    // Surface visibility state controls the base poll interval.
    let visibility = VisibilityGate()

    // Exponential backoff state
    private var consecutiveFailures: Int = 0
    private let maxInterval: TimeInterval = 60
    private let knownAlertIDsLimit: Int = 500

    // Network path monitoring
    private var pathMonitor: NWPathMonitor?
    private var monitorQueue = DispatchQueue(label: "com.labtether.network-monitor")

    weak var notifications: NotificationManager?

    private enum LocalStatusFetchResult: Sendable {
        case notModified
        case unauthorized
        case success(AgentStatusResponse, etag: String?, payloadBytes: Int)
        case failure(httpStatus: Int?)
    }

    /// `true` when either interactive UI surface is visible.
    var animationsActive: Bool { visibility.anySurfaceVisible }

    var isReachable: Bool { runtime.snapshot.isReachable }
    var hubConnectionState: String { runtime.snapshot.hubConnectionState }
    var metricsHistory: MetricsHistory { metrics.snapshot.history }

    /// The base poll interval determined by visibility (5s visible, 30s hidden).
    private var baseInterval: TimeInterval { animationsActive ? 5 : 30 }

    /// Exposed for UI redraw control in MenuBarExtra label updates.
    var isMenuVisible: Bool { visibility.menuVisible }

    /// Effective interval after applying exponential backoff from consecutive failures.
    private var effectiveInterval: TimeInterval {
        guard consecutiveFailures > 0 else { return baseInterval }
        let backoff = baseInterval * pow(2, Double(consecutiveFailures - 1))
        return min(backoff, maxInterval)
    }

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    func start(port: String, authToken: String?) {
        baseURL = "http://127.0.0.1:\(port)"
        let trimmedAuthToken = authToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.authToken = trimmedAuthToken.isEmpty ? nil : trimmedAuthToken
        isPolling = true
        consecutiveFailures = 0
        status = nil
        runtime.reset()
        metrics.reset(clearHistory: true)
        alerts.reset()
        metadata.reset()
        statusETag = nil
        latestStatusSnapshot = nil
        latestReachable = false
        latestHubConnectionState = "disconnected"
        poll()
        scheduleNextPoll()
        startNetworkMonitor()
    }

    func stop() {
        isPolling = false
        statusTimer?.invalidate()
        statusTimer = nil
        pollTask?.cancel()
        pollTask = nil
        pathMonitor?.cancel()
        pathMonitor = nil
        status = nil
        runtime.reset()
        metrics.reset(clearHistory: true)
        alerts.reset()
        metadata.reset()
        statusETag = nil
        authToken = nil
        latestStatusSnapshot = nil
        latestReachable = false
        latestHubConnectionState = "disconnected"
        knownAlertIDs.removeAll()
        visibility.reset()
    }

    /// Notifies the client whether the menu bar popover is currently visible.
    ///
    /// When visible, polling switches to the fast interval (5s) and an immediate
    /// refresh is triggered so the UI shows current data as soon as the popover opens.
    /// When hidden, polling drops to the slow interval (30s) to reduce background load.
    /// Backoff multipliers continue to apply on top of whichever base interval is active.
    func setMenuVisible(_ visible: Bool) {
        guard visibility.setMenuVisible(visible) else { return }
        handleVisibilityTransition(becameVisible: visible)
    }

    /// Notifies the client whether the pop-out panel is currently visible.
    ///
    /// This keeps polling fast while operators use the detached panel.
    func setPanelVisible(_ visible: Bool) {
        guard visibility.setPanelVisible(visible) else { return }
        handleVisibilityTransition(becameVisible: visible)
    }

    private func handleVisibilityTransition(becameVisible: Bool) {
        guard isPolling else { return }
        if becameVisible {
            applyLatestSnapshotToPublishedState()
            // Immediately refresh so newly visible UI opens with fresh data.
            consecutiveFailures = 0
            poll()
        }
        // Reschedule with the updated base interval (and current backoff, if any).
        scheduleNextPoll()
    }

    private func applyLatestSnapshotToPublishedState() {
        if let latestStatusSnapshot {
            applyStatusSnapshot(latestStatusSnapshot, appendHistory: animationsActive)
        } else {
            publishRuntimeSnapshot(
                isReachable: latestReachable,
                hubConnectionState: latestHubConnectionState,
                uptime: nil,
                lastError: nil
            )
        }
    }

    func applyStatusSnapshot(_ decoded: AgentStatusResponse, appendHistory: Bool) {
        if status != decoded {
            status = decoded
        }
        publishRuntimeSnapshot(
            isReachable: true,
            hubConnectionState: decoded.connectionState ?? (decoded.connected ? "connected" : "disconnected"),
            uptime: decoded.uptime,
            lastError: decoded.lastError
        )
        publishMetricsSnapshot(decoded.metrics, appendHistory: appendHistory)
        alerts.publish(LocalAPIAlertsSnapshot(alerts: decoded.alerts))
        metadata.publish(
            LocalAPIMetadataSnapshot(
                agentVersion: decoded.agentVersion,
                updateAvailable: decoded.updateAvailable ?? false,
                latestVersion: decoded.latestVersion,
                deviceFingerprint: decoded.deviceFingerprint,
                localBindAddress: decoded.localBindAddress,
                localAuthEnabled: decoded.localAuthEnabled,
                allowInsecureTransport: decoded.allowInsecureTransport
            )
        )
    }

    private func publishRuntimeSnapshot(
        isReachable: Bool,
        hubConnectionState: String,
        uptime: String?,
        lastError: String?
    ) {
        runtime.publish(
            LocalAPIRuntimeSnapshot(
                isReachable: isReachable,
                hubConnectionState: hubConnectionState,
                uptime: uptime,
                lastError: lastError
            )
        )
    }

    private func publishMetricsSnapshot(_ snapshot: MetricsSnapshot, appendHistory: Bool) {
        var nextMetrics = metrics.snapshot
        nextMetrics.current = snapshot
        if appendHistory {
            let lastCollectedAt = nextMetrics.history.samples.last?.collectedAt
            if lastCollectedAt != snapshot.collectedAt {
                nextMetrics.history.append(snapshot)
            }
        }
        nextMetrics.presentation = LocalAPIMetricsPresentation.build(current: snapshot, history: nextMetrics.history)
        metrics.publish(nextMetrics)
    }

    // MARK: - Scheduling

    private func scheduleNextPoll() {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: effectiveInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
                self?.scheduleNextPoll()
            }
        }
    }

    /// Thread-safe guard used to skip the initial NWPathMonitor callback.
    private final class FirstFireGuard: @unchecked Sendable {
        var fired = false
    }

    private func startNetworkMonitor() {
        pathMonitor?.cancel()
        let monitor = NWPathMonitor()
        // NWPathMonitor fires its handler immediately with the current state.
        // Skip the first callback to avoid a redundant double-poll on start().
        let firstFire = FirstFireGuard()
        monitor.pathUpdateHandler = { [weak self] path in
            if !firstFire.fired {
                firstFire.fired = true
                return
            }
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isPolling else { return }
                self.consecutiveFailures = 0
                self.poll()
                self.scheduleNextPoll()
            }
        }
        monitor.start(queue: monitorQueue)
        pathMonitor = monitor
    }

    // MARK: - Polling

    private func poll() {
        guard isPolling else { return }
        pollTask?.cancel()
        guard let url = URL(string: "\(baseURL)/agent/status") else { return }

        var request = URLRequest(url: url)
        if let authToken, !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        if let statusETag {
            request.setValue(statusETag, forHTTPHeaderField: "If-None-Match")
        }

        let session = self.session
        pollTask = Task.detached(priority: .utility) { [weak self, request, session] in
            let signpostID = LTPerformanceSignposts.beginLocalStatusPoll()
            do {
                let result = try await Self.fetchStatus(session: session, request: request)
                guard !Task.isCancelled else { return }
                guard let owner = self else {
                    LTPerformanceSignposts.endLocalStatusPoll(signpostID, outcome: 4)
                    return
                }

                let signpost = await MainActor.run { () -> (Int, Int, Int) in
                    guard owner.isPolling else {
                        return (4, 0, 0)
                    }

                    switch result {
                    case .notModified:
                        owner.applyNotModifiedPollResult()
                        return (1, 304, 0)
                    case .unauthorized:
                        owner.applyPollAuthFailure()
                        return (2, 401, 0)
                    case .success(let decoded, let etag, let payloadBytes):
                        if let etag, !etag.isEmpty {
                            owner.statusETag = etag
                        }
                        owner.applySuccessfulPollResult(decoded)
                        return (0, 200, payloadBytes)
                    case .failure(let httpStatus):
                        owner.applyPollFailure()
                        return (httpStatus == nil ? 4 : 3, httpStatus ?? 0, 0)
                    }
                }

                LTPerformanceSignposts.endLocalStatusPoll(
                    signpostID,
                    outcome: signpost.0,
                    httpStatus: signpost.1,
                    payloadBytes: signpost.2
                )
            } catch {
                guard !Task.isCancelled else { return }
                guard let owner = self else { return }
                let shouldRecord = await MainActor.run { () -> Bool in
                    guard owner.isPolling else { return false }
                    owner.applyPollFailure()
                    return true
                }
                if shouldRecord {
                    LTPerformanceSignposts.endLocalStatusPoll(signpostID, outcome: 4)
                }
            }
        }
    }

    func applyNotModifiedPollResult() {
        latestReachable = true
        if let latest = latestStatusSnapshot {
            latestHubConnectionState = latest.connectionState ?? (latest.connected ? "connected" : "disconnected")
            if status != latest {
                status = latest
            }
            publishRuntimeSnapshot(
                isReachable: true,
                hubConnectionState: latestHubConnectionState,
                uptime: latest.uptime,
                lastError: latest.lastError
            )
        } else {
            latestHubConnectionState = runtime.snapshot.hubConnectionState
        }
        consecutiveFailures = 0
    }

    func applySuccessfulPollResult(_ decoded: AgentStatusResponse) {
        latestStatusSnapshot = decoded
        latestReachable = true
        latestHubConnectionState = decoded.connectionState ?? (decoded.connected ? "connected" : "disconnected")
        applyStatusSnapshot(decoded, appendHistory: animationsActive)
        consecutiveFailures = 0
        processAlerts(decoded.alerts)
    }

    func applyPollFailure() {
        status = nil
        statusETag = nil
        latestStatusSnapshot = nil
        latestReachable = false
        latestHubConnectionState = "disconnected"
        runtime.reset()
        metrics.publish(
            LocalAPIMetricsSnapshot(
                current: nil,
                history: metrics.snapshot.history,
                presentation: nil
            )
        )
        alerts.reset()
        metadata.reset()
        consecutiveFailures += 1
    }

    func applyPollAuthFailure() {
        status = nil
        statusETag = nil
        latestStatusSnapshot = nil
        latestReachable = false
        latestHubConnectionState = "auth_failed"
        publishRuntimeSnapshot(
            isReachable: false,
            hubConnectionState: "auth_failed",
            uptime: nil,
            lastError: nil
        )
        metrics.publish(
            LocalAPIMetricsSnapshot(
                current: nil,
                history: metrics.snapshot.history,
                presentation: nil
            )
        )
        alerts.reset()
        metadata.reset()
        consecutiveFailures += 1
    }

    // MARK: - Alert Processing

    func processAlerts(_ alerts: [AlertSnapshot]) {
        // Guard against unbounded growth from long-running agents with many alerts.
        if knownAlertIDs.count > knownAlertIDsLimit {
            knownAlertIDs.removeAll()
        }

        let currentIDs = Set(alerts.map(\.id))
        for alert in alerts {
            if !knownAlertIDs.contains(alert.id) && alert.state == "firing" {
                if alert.severity == "critical" || alert.severity == "high" {
                    notifications?.notify(.alertFiring(title: alert.title, severity: alert.severity))
                }
            }
            if knownAlertIDs.contains(alert.id) && alert.state == "resolved" {
                notifications?.notify(.alertResolved(title: alert.title))
            }
        }
        // Merge new IDs into known set rather than replacing — prevents re-notification
        // when alerts cycle through the Go agent's 20-entry cache.
        knownAlertIDs.formUnion(currentIDs)
        // Remove resolved alerts from tracking so they don't grow unbounded.
        let resolvedIDs = Set(alerts.filter { $0.state == "resolved" }.map(\.id))
        knownAlertIDs.subtract(resolvedIDs)
    }

    private static func fetchStatus(
        session: URLSession,
        request: URLRequest
    ) async throws -> LocalStatusFetchResult {
        let (data, response) = try await session.data(for: request)
        guard let httpResp = response as? HTTPURLResponse else {
            return .failure(httpStatus: nil)
        }
        switch httpResp.statusCode {
        case 304:
            return .notModified
        case 401:
            return .unauthorized
        case 200:
            let etag = httpResp.value(forHTTPHeaderField: "ETag")?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let decoded = try await Task.detached(priority: .utility) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode(AgentStatusResponse.self, from: data)
            }.value
            return .success(decoded, etag: etag, payloadBytes: data.count)
        default:
            return .failure(httpStatus: httpResp.statusCode)
        }
    }
}
