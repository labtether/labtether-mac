import Foundation

/// Safely converts a Double to Int, returning 0 for NaN/infinity.
private func safePercent(_ value: Double) -> Int {
    guard value.isFinite else { return 0 }
    return Int(value.rounded())
}

struct MenuBarLabelPresentation: Equatable {
    let kind: MenuBarIconKind
    let primaryMetricsText: String?
    let secondaryMetricsText: String?

    /// The figures shown next to the glyph, in one run of text ("23% 61%").
    var metricsText: String? {
        guard let primaryMetricsText else { return nil }
        guard let secondaryMetricsText else { return primaryMetricsText }
        return "\(primaryMetricsText) \(secondaryMetricsText)"
    }

    static func resolve(
        displayMode: String,
        statusState: ConnectionState,
        hubConnectionState: String,
        isReachable: Bool,
        metrics: MetricsSnapshot?,
        hasFiringAlerts: Bool,
        hasCriticalAlert: Bool = false
    ) -> MenuBarLabelPresentation {
        let kind = MenuBarIconResolver.resolve(
            statusState: statusState,
            hubConnectionState: hubConnectionState,
            isReachable: isReachable,
            metrics: metrics,
            hasFiringAlerts: hasFiringAlerts,
            hasCriticalAlert: hasCriticalAlert
        )

        guard displayMode != "compact", let metrics, isReachable else {
            return MenuBarLabelPresentation(kind: kind, primaryMetricsText: nil, secondaryMetricsText: nil)
        }

        return MenuBarLabelPresentation(
            kind: kind,
            primaryMetricsText: "\(safePercent(metrics.cpuPercent))% \(safePercent(metrics.memoryPercent))%",
            secondaryMetricsText: displayMode == "verbose" ? "\(safePercent(metrics.diskPercent))%" : nil
        )
    }
}
