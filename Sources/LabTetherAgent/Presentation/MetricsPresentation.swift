import Foundation
import SwiftUI

struct MetricGaugePresentation: Equatable {
    let rawValue: Double
    let roundedPercent: Int
    let percentText: String
    let fraction: Double
    let sparkline: SparklineSeries

    var color: Color {
        if rawValue >= 90 { return LT.bad }
        if rawValue >= 75 { return LT.warn }
        return LT.ok
    }

    static func thresholdColor(for value: Double) -> Color {
        if value >= 90 { return LT.bad }
        if value >= 75 { return LT.warn }
        return LT.ok
    }
}

struct MetricsNetworkPresentation: Equatable {
    let menuRXText: String
    let menuTXText: String
    let popOutRXText: String
    let popOutTXText: String
    let temperatureCelsius: Double?
    let menuTemperatureText: String?
    let popOutTemperatureText: String?
    let relativeSyncText: String?
}

struct LocalAPIMetricsPresentation: Equatable {
    let cpu: MetricGaugePresentation
    let memory: MetricGaugePresentation
    let disk: MetricGaugePresentation
    let network: MetricsNetworkPresentation

    static func build(current: MetricsSnapshot, history: MetricsHistory) -> LocalAPIMetricsPresentation {
        LocalAPIMetricsPresentation(
            cpu: MetricGaugePresentation(
                rawValue: current.cpuPercent,
                roundedPercent: roundedPercent(current.cpuPercent),
                percentText: "\(roundedPercent(current.cpuPercent))%",
                fraction: clampedFraction(current.cpuPercent),
                sparkline: history.cpuSparkline
            ),
            memory: MetricGaugePresentation(
                rawValue: current.memoryPercent,
                roundedPercent: roundedPercent(current.memoryPercent),
                percentText: "\(roundedPercent(current.memoryPercent))%",
                fraction: clampedFraction(current.memoryPercent),
                sparkline: history.memSparkline
            ),
            disk: MetricGaugePresentation(
                rawValue: current.diskPercent,
                roundedPercent: roundedPercent(current.diskPercent),
                percentText: "\(roundedPercent(current.diskPercent))%",
                fraction: clampedFraction(current.diskPercent),
                sparkline: history.diskSparkline
            ),
            network: MetricsNetworkPresentation(
                menuRXText: formatBinaryRate(current.netRXBytesPerSec),
                menuTXText: formatBinaryRate(current.netTXBytesPerSec),
                popOutRXText: formatDecimalRate(current.netRXBytesPerSec),
                popOutTXText: formatDecimalRate(current.netTXBytesPerSec),
                temperatureCelsius: current.tempCelsius,
                menuTemperatureText: formattedTemperature(current.tempCelsius),
                popOutTemperatureText: formattedTemperature(current.tempCelsius),
                relativeSyncText: current.collectedAt.map(relativeSyncText)
            )
        )
    }

    private static func roundedPercent(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(value.rounded())
    }

    private static func clampedFraction(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value / 100.0, 0), 1)
    }

    private static func formattedTemperature(_ value: Double?) -> String? {
        guard let value, value.isFinite else { return nil }
        return "\(Int(value.rounded()))°C"
    }

    private static func formatBinaryRate(_ bytesPerSec: Double) -> String {
        guard bytesPerSec.isFinite else { return "0 B/s" }
        let kb = 1_024.0
        let mb = kb * 1_024
        let gb = mb * 1_024

        switch bytesPerSec {
        case ..<kb:
            return "\(Int(bytesPerSec)) B/s"
        case ..<mb:
            return String(format: "%.1f KB/s", bytesPerSec / kb)
        case ..<gb:
            return String(format: "%.1f MB/s", bytesPerSec / mb)
        default:
            return String(format: "%.2f GB/s", bytesPerSec / gb)
        }
    }

    private static func formatDecimalRate(_ bytesPerSec: Double) -> String {
        guard bytesPerSec.isFinite else { return "0 B/s" }
        if bytesPerSec >= 1_000_000 {
            return String(format: "%.1f MB/s", bytesPerSec / 1_000_000)
        }
        if bytesPerSec >= 1_000 {
            return String(format: "%.0f KB/s", bytesPerSec / 1_000)
        }
        return String(format: "%.0f B/s", bytesPerSec)
    }

    private static func relativeSyncText(_ date: Date) -> String {
        let seconds = max(0, Int(-date.timeIntervalSinceNow))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}
