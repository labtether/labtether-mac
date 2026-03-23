import SwiftUI

/// A compact card showing CPU, memory, disk gauges, network throughput, and optional temperature.
///
/// Designed to be embedded inside `MenuBarView` (or any container that has a
/// `MetricsSnapshot` available) at 340 pt wide. All colours and type sizes
/// follow the LabTether design token system (`LT` namespace).
struct MetricsView: View {
    let presentation: LocalAPIMetricsPresentation

    init(presentation: LocalAPIMetricsPresentation) {
        self.presentation = presentation
    }

    init(metrics: MetricsSnapshot) {
        self.presentation = LocalAPIMetricsPresentation.build(current: metrics, history: MetricsHistory())
    }

    var body: some View {
        VStack(spacing: 5) {
            gaugeRow("CPU", gauge: presentation.cpu)
            gaugeRow("MEM", gauge: presentation.memory)
            gaugeRow("DISK", gauge: presentation.disk)
            networkRow
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func gaugeRow(_ label: String, gauge: MetricGaugePresentation) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(LT.mono(10, weight: .semibold))
                .foregroundStyle(LT.textMuted)
                .frame(width: 32, alignment: .leading)

            LTMetricBar(fraction: gauge.fraction, color: gauge.color)
            .frame(height: 14)

            Text(gauge.percentText)
                .font(LT.mono(10, weight: .medium))
                .foregroundStyle(gauge.color)
                .frame(width: 30, alignment: .trailing)
        }
    }

    private var networkRow: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(LT.ok)
                    .shadow(color: LT.ok.opacity(0.3), radius: 2)
                VStack(alignment: .leading, spacing: 0) {
                    Text("RX")
                        .font(LT.mono(8, weight: .semibold))
                        .foregroundStyle(LT.textMuted)
                        .tracking(0.5)
                    Text(presentation.network.menuRXText)
                        .font(LT.mono(10, weight: .medium))
                        .foregroundStyle(LT.textSecondary)
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(LT.accent)
                    .shadow(color: LT.accent.opacity(0.3), radius: 2)
                VStack(alignment: .leading, spacing: 0) {
                    Text("TX")
                        .font(LT.mono(8, weight: .semibold))
                        .foregroundStyle(LT.textMuted)
                        .tracking(0.5)
                    Text(presentation.network.menuTXText)
                        .font(LT.mono(10, weight: .medium))
                        .foregroundStyle(LT.textSecondary)
                }
            }

            if let tempText = presentation.network.menuTemperatureText {
                let tempColor = temperatureColor(presentation.network.temperatureCelsius ?? 0)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(tempColor)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("THERM")
                            .font(LT.mono(8, weight: .semibold))
                            .foregroundStyle(LT.textMuted)
                            .tracking(0.5)
                        Text(tempText)
                            .font(LT.mono(10, weight: .medium))
                            .foregroundStyle(tempColor)
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    private func temperatureColor(_ celsius: Double) -> Color {
        switch celsius {
        case ..<70: return LT.ok
        case ..<85: return LT.warn
        default: return LT.bad
        }
    }
}

struct MetricsLoadingView: View {
    var body: some View {
        VStack(spacing: 5) {
            gaugeRow("CPU")
            gaugeRow("MEM")
            gaugeRow("DISK")
            networkRow
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func gaugeRow(_ label: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(LT.mono(10, weight: .semibold))
                .foregroundStyle(LT.textMuted)
                .frame(width: 32, alignment: .leading)

            LTShimmer(height: 6, cornerRadius: 3)
                .frame(height: 14)

            LTShimmer(height: 12, cornerRadius: LT.radiusSm)
                .frame(width: 30)
        }
    }

    private var networkRow: some View {
        HStack(spacing: LT.space12) {
            networkCell(label: "RX")
            Spacer()
            networkCell(label: "TX")
            Spacer()
            networkCell(label: "THERM")
        }
        .padding(.top, 2)
    }

    private func networkCell(label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(LT.mono(8, weight: .semibold))
                .foregroundStyle(LT.textMuted)
                .tracking(0.5)
            LTShimmer(height: 10, cornerRadius: LT.radiusSm)
                .frame(width: 44)
        }
    }
}

#if DEBUG
#Preview("MetricsView — normal load") {
    MetricsView(
        metrics: MetricsSnapshot(
            cpuPercent: 23,
            memoryPercent: 61,
            diskPercent: 45,
            netRXBytesPerSec: 1_258_291,
            netTXBytesPerSec: 348_160,
            tempCelsius: 42,
            collectedAt: Date()
        )
    )
    .frame(width: 340)
    .padding()
    .background(LT.bg)
}

#Preview("MetricsView — high load") {
    MetricsView(
        metrics: MetricsSnapshot(
            cpuPercent: 97,
            memoryPercent: 88,
            diskPercent: 72,
            netRXBytesPerSec: 52_428_800,
            netTXBytesPerSec: 10_485_760,
            tempCelsius: 91,
            collectedAt: Date()
        )
    )
    .frame(width: 340)
    .padding()
    .background(LT.bg)
}

#Preview("MetricsView — no temperature") {
    MetricsView(
        metrics: MetricsSnapshot(
            cpuPercent: 5,
            memoryPercent: 30,
            diskPercent: 12,
            netRXBytesPerSec: 512,
            netTXBytesPerSec: 256,
            tempCelsius: nil,
            collectedAt: nil
        )
    )
    .frame(width: 340)
    .padding()
    .background(LT.bg)
}
#endif
