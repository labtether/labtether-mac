import XCTest
@testable import LabTetherAgent

final class AgentHeroPresentationTests: XCTestCase {
    func testResolvePrefersAuthFailureOverWrapperConnectedState() {
        let presentation = AgentHeroPresentation.resolve(
            processIsRunning: true,
            processIsStarting: false,
            statusState: .connected,
            statusLastError: "",
            statusUptime: "8m",
            apiUptime: nil,
            apiLastError: nil,
            hubConnectionState: "auth_failed",
            isReachable: false
        )

        XCTAssertEqual(presentation.label, "Auth Failed")
        XCTAssertEqual(presentation.subtitle, "Local status authentication failed")
        XCTAssertEqual(presentation.tone, .bad)
    }

    func testResolveShowsStatusUnavailableWhenProcessRunsWithoutTrustedLocalStatus() {
        let presentation = AgentHeroPresentation.resolve(
            processIsRunning: true,
            processIsStarting: false,
            statusState: .connected,
            statusLastError: "",
            statusUptime: "8m",
            apiUptime: nil,
            apiLastError: nil,
            hubConnectionState: "disconnected",
            isReachable: false
        )

        XCTAssertEqual(presentation.label, "Status Unavailable")
        XCTAssertEqual(presentation.subtitle, "Waiting for local status response")
        XCTAssertEqual(presentation.tone, .warn)
    }

    func testResolveUsesTrustedLocalUptimeWhenConnected() {
        let presentation = AgentHeroPresentation.resolve(
            processIsRunning: true,
            processIsStarting: false,
            statusState: .connected,
            statusLastError: "",
            statusUptime: "2m",
            apiUptime: "15m",
            apiLastError: nil,
            hubConnectionState: "connected",
            isReachable: true
        )

        XCTAssertEqual(presentation.label, "Connected")
        XCTAssertEqual(presentation.subtitle, "15m · all clear")
        XCTAssertEqual(presentation.tone, .ok)
    }
}

final class DiagnosticsLogSummaryTests: XCTestCase {
    func testReportLinesSummarizeCountsWithoutIncludingRawLogText() {
        let lines = [
            LogLine(id: 1, raw: "[app] failed token=super-secret-token"),
            LogLine(id: 2, raw: "2026/03/08 12:00:00 warn reconnect timeout"),
            LogLine(id: 3, raw: "2026/03/08 12:00:01 connected to hub")
        ]

        let summary = DiagnosticsLogSummary(logLines: lines)
        let report = summary.reportLines.joined(separator: "\n")

        XCTAssertEqual(summary.totalCount, 3)
        XCTAssertEqual(summary.errorCount, 1)
        XCTAssertEqual(summary.warningCount, 1)
        XCTAssertEqual(summary.infoCount, 1)
        XCTAssertTrue(report.contains("Buffered Logs: 3 total"))
        XCTAssertTrue(report.contains("omitted from clipboard diagnostics"))
        XCTAssertFalse(report.contains("super-secret-token"))
    }
}

final class MetricsAndAlertsPresentationTests: XCTestCase {
    func testMetricsPresentationBuildsDisplayReadyGaugeAndNetworkValues() {
        var history = MetricsHistory()
        let collectedAt = Date().addingTimeInterval(-120)
        history.append(
            MetricsSnapshot(
                cpuPercent: 12,
                memoryPercent: 34,
                diskPercent: 56,
                netRXBytesPerSec: 1_536,
                netTXBytesPerSec: 2_500_000,
                tempCelsius: 72,
                collectedAt: collectedAt
            )
        )

        let presentation = LocalAPIMetricsPresentation.build(
            current: MetricsSnapshot(
                cpuPercent: 87.2,
                memoryPercent: 63.8,
                diskPercent: 41.4,
                netRXBytesPerSec: 1_536,
                netTXBytesPerSec: 2_500_000,
                tempCelsius: 72,
                collectedAt: collectedAt
            ),
            history: history
        )

        XCTAssertEqual(presentation.cpu.roundedPercent, 87)
        XCTAssertEqual(presentation.cpu.percentText, "87%")
        XCTAssertEqual(presentation.memory.percentText, "64%")
        XCTAssertEqual(presentation.disk.percentText, "41%")
        XCTAssertEqual(presentation.network.menuRXText, "1.5 KB/s")
        XCTAssertEqual(presentation.network.popOutTXText, "2.5 MB/s")
        XCTAssertEqual(presentation.network.menuTemperatureText, "72°C")
        XCTAssertEqual(presentation.network.popOutTemperatureText, "72°C")
        XCTAssertEqual(presentation.cpu.sparkline.normalizedValues.count, 1)
        XCTAssertEqual(presentation.network.relativeSyncText, "2m ago")
    }

    func testAlertsSnapshotCachesFiringAndCriticalState() {
        let snapshot = LocalAPIAlertsSnapshot(
            alerts: [
                AlertSnapshot(
                    id: "a",
                    severity: "critical",
                    title: "CPU hot",
                    summary: "",
                    state: "firing",
                    timestamp: nil
                ),
                AlertSnapshot(
                    id: "b",
                    severity: "medium",
                    title: "Recovered",
                    summary: "",
                    state: "resolved",
                    timestamp: nil
                )
            ]
        )

        XCTAssertEqual(snapshot.firingAlerts.map(\.id), ["a"])
        XCTAssertTrue(snapshot.hasCriticalFiring)
    }
}
