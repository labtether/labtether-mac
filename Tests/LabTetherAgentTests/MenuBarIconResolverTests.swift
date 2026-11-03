import XCTest
@testable import LabTetherAgent

final class MenuBarIconResolverTests: XCTestCase {
    func testResolvePrefersAlertBadgeOverEverythingElse() {
        XCTAssertEqual(
            MenuBarIconResolver.resolve(
                statusState: .connected,
                hubConnectionState: "connected",
                isReachable: true,
                metrics: makeMetrics(cpu: 12, memory: 34, disk: 56),
                hasFiringAlerts: true
            ),
            .alert
        )
    }

    func testResolveShowsOfflineBadgeForReachableDisconnectedHub() {
        XCTAssertEqual(
            MenuBarIconResolver.resolve(
                statusState: .connected,
                hubConnectionState: "disconnected",
                isReachable: true,
                metrics: makeMetrics(cpu: 12, memory: 34, disk: 56),
                hasFiringAlerts: false
            ),
            .offline
        )
    }

    func testResolveShowsErrorBadgeForAuthFailure() {
        XCTAssertEqual(
            MenuBarIconResolver.resolve(
                statusState: .connected,
                hubConnectionState: "auth_failed",
                isReachable: true,
                metrics: makeMetrics(cpu: 12, memory: 34, disk: 56),
                hasFiringAlerts: false
            ),
            .error
        )
    }

    func testResolveShowsErrorBadgeForAuthFailureWithoutFreshMetrics() {
        XCTAssertEqual(
            MenuBarIconResolver.resolve(
                statusState: .connected,
                hubConnectionState: "auth_failed",
                isReachable: false,
                metrics: nil,
                hasFiringAlerts: false
            ),
            .error
        )
    }

    func testResolveUsesWarningAndCriticalThresholdsBeforeConnectedState() {
        XCTAssertEqual(
            MenuBarIconResolver.resolve(
                statusState: .connected,
                hubConnectionState: "connected",
                isReachable: true,
                metrics: makeMetrics(cpu: 81, memory: 34, disk: 56),
                hasFiringAlerts: false
            ),
            .warning
        )

        XCTAssertEqual(
            MenuBarIconResolver.resolve(
                statusState: .connected,
                hubConnectionState: "connected",
                isReachable: true,
                metrics: makeMetrics(cpu: 12, memory: 96, disk: 56),
                hasFiringAlerts: false
            ),
            .critical
        )
    }

    func testResolveFallsBackToProcessStateWhenLocalAPIIsUnavailable() {
        XCTAssertEqual(
            MenuBarIconResolver.resolve(
                statusState: .reconnecting,
                hubConnectionState: "disconnected",
                isReachable: false,
                metrics: nil,
                hasFiringAlerts: false
            ),
            .connecting
        )

        XCTAssertEqual(
            MenuBarIconResolver.resolve(
                statusState: .stopped,
                hubConnectionState: "disconnected",
                isReachable: false,
                metrics: nil,
                hasFiringAlerts: false
            ),
            .stopped
        )
    }

    func testLabelPresentationHidesMetricsInCompactModeAndWhenUnreachable() {
        let compact = MenuBarLabelPresentation.resolve(
            displayMode: "compact",
            statusState: .connected,
            hubConnectionState: "connected",
            isReachable: true,
            metrics: makeMetrics(cpu: 12, memory: 34, disk: 56),
            hasFiringAlerts: false
        )
        XCTAssertNil(compact.primaryMetricsText)
        XCTAssertNil(compact.secondaryMetricsText)

        let unreachable = MenuBarLabelPresentation.resolve(
            displayMode: "verbose",
            statusState: .connected,
            hubConnectionState: "connected",
            isReachable: false,
            metrics: makeMetrics(cpu: 12, memory: 34, disk: 56),
            hasFiringAlerts: false
        )
        XCTAssertNil(unreachable.primaryMetricsText)
        XCTAssertNil(unreachable.secondaryMetricsText)
    }

    func testLabelPresentationFormatsStandardAndVerboseMetricText() {
        let standard = MenuBarLabelPresentation.resolve(
            displayMode: "standard",
            statusState: .connected,
            hubConnectionState: "connected",
            isReachable: true,
            metrics: makeMetrics(cpu: 12.4, memory: 34.4, disk: 56.4),
            hasFiringAlerts: false
        )
        XCTAssertEqual(standard.primaryMetricsText, "12% 34%")
        XCTAssertNil(standard.secondaryMetricsText)

        let verbose = MenuBarLabelPresentation.resolve(
            displayMode: "verbose",
            statusState: .connected,
            hubConnectionState: "connected",
            isReachable: true,
            metrics: makeMetrics(cpu: 12.4, memory: 34.4, disk: 56.6),
            hasFiringAlerts: false
        )
        XCTAssertEqual(verbose.primaryMetricsText, "12% 34%")
        XCTAssertEqual(verbose.secondaryMetricsText, "57%")
    }

    func testLabelPresentationCarriesResolvedIconState() {
        let presentation = MenuBarLabelPresentation.resolve(
            displayMode: "standard",
            statusState: .connected,
            hubConnectionState: "auth_failed",
            isReachable: false,
            metrics: makeMetrics(cpu: 12, memory: 34, disk: 56),
            hasFiringAlerts: false
        )
        XCTAssertEqual(presentation.kind, .error)
    }

    // Risk: the menu bar glyph is the only signal while the window is closed.
    // A firing alert or refused token must draw the dot (red only for critical
    // or auth), and calm or stopped states must not draw one.
    func testAttentionDotFollowsAlertSeverityAndConnectionState() {
        func resolve(
            hub: String = "connected",
            state: ConnectionState = .connected,
            reachable: Bool = true,
            alerts: Bool = false,
            critical: Bool = false
        ) -> MenuBarIconKind {
            MenuBarIconResolver.resolve(
                statusState: state,
                hubConnectionState: hub,
                isReachable: reachable,
                metrics: reachable ? makeMetrics(cpu: 12, memory: 34, disk: 56) : nil,
                hasFiringAlerts: alerts,
                hasCriticalAlert: critical
            )
        }

        XCTAssertEqual(resolve(alerts: true).dot, .warn)
        XCTAssertEqual(resolve(alerts: true, critical: true).dot, .bad)
        XCTAssertEqual(resolve(hub: "auth_failed").dot, .bad)
        XCTAssertEqual(resolve().dot, .none)
        XCTAssertFalse(resolve().isDimmed)

        let stopped = resolve(hub: "disconnected", state: .stopped, reachable: false)
        XCTAssertEqual(stopped.dot, .none)
        XCTAssertTrue(stopped.isDimmed)
        let offline = resolve(hub: "disconnected")
        XCTAssertEqual(offline.dot, .none)
        XCTAssertTrue(offline.isDimmed)
    }

    private func makeMetrics(cpu: Double, memory: Double, disk: Double) -> MetricsSnapshot {
        MetricsSnapshot(
            cpuPercent: cpu,
            memoryPercent: memory,
            diskPercent: disk,
            netRXBytesPerSec: 0,
            netTXBytesPerSec: 0,
            tempCelsius: nil,
            collectedAt: nil
        )
    }
}
