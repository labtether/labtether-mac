import SwiftUI

struct PopOutSystemSection: View {
    @ObservedObject var runtime: LocalAPIRuntimeStore
    @ObservedObject var metrics: LocalAPIMetricsStore
    @ObservedObject var agentProcess: AgentProcess

    private var isMetricsLoading: Bool {
        !runtime.snapshot.isReachable && (agentProcess.isRunning || agentProcess.isStarting)
    }

    var body: some View {
        VStack(spacing: LT.space8) {
            LTSectionHeader("SYSTEM")

            if let presentation = metrics.snapshot.presentation, runtime.snapshot.isReachable {
                HStack(spacing: LT.space8) {
                    metricCard(
                        "CPU",
                        gauge: presentation.cpu
                    )
                    metricCard(
                        "MEM",
                        gauge: presentation.memory
                    )
                    metricCard(
                        "DISK",
                        gauge: presentation.disk
                    )
                }

                networkRow(presentation: presentation)
            } else if isMetricsLoading {
                metricsLoadingSection
            } else {
                LTGlassCard {
                    LTEmptyState(
                        icon: "chart.bar",
                        title: "Metrics unavailable",
                        subtitle: "Waiting for agent connection"
                    )
                    .padding(-LT.space12)
                }
            }
        }
    }

    private func metricCard(
        _ label: String,
        gauge: MetricGaugePresentation
    ) -> some View {
        LTGlassCard(glowColor: gauge.color) {
            VStack(alignment: .leading, spacing: LT.space4) {
                Text(label)
                    .font(LT.mono(10, weight: .semibold))
                    .foregroundStyle(LT.textMuted)
                    .tracking(1)

                Text(gauge.percentText)
                    .font(LT.sora(20, weight: .bold))
                    .foregroundStyle(gauge.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                LTSparkline(series: gauge.sparkline, color: gauge.color, height: 24)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func networkRow(presentation: LocalAPIMetricsPresentation) -> some View {
        LTGlassCard {
            HStack(spacing: LT.space16) {
                networkStatCell(
                    label: "RX",
                    icon: "arrow.down.circle",
                    value: presentation.network.popOutRXText,
                    color: LT.ok
                )

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [LT.panelBorder.opacity(0), LT.panelBorder, LT.panelBorder.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 0.5, height: 28)

                networkStatCell(
                    label: "TX",
                    icon: "arrow.up.circle",
                    value: presentation.network.popOutTXText,
                    color: LT.accent
                )
                if let tempText = presentation.network.popOutTemperatureText {
                    let tempValue = presentation.network.temperatureCelsius ?? 0
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [LT.panelBorder.opacity(0), LT.panelBorder, LT.panelBorder.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 0.5, height: 28)

                    networkStatCell(
                        label: "TEMP",
                        icon: "thermometer.medium",
                        value: tempText,
                        color: MetricGaugePresentation.thresholdColor(for: tempValue)
                    )
                }
                Spacer()
            }
        }
    }

    private func networkStatCell(label: String, icon: String, value: String, color: Color) -> some View {
        HStack(spacing: LT.space4) {
            Image(systemName: "\(icon).fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(color)
                .shadow(color: color.opacity(0.24), radius: 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(LT.mono(9, weight: .semibold))
                    .foregroundStyle(LT.textMuted)
                    .tracking(0.5)
                Text(value)
                    .font(LT.mono(11, weight: .medium))
                    .foregroundStyle(LT.textSecondary)
                    .contentTransition(.numericText())
            }
        }
    }

    private var metricsLoadingSection: some View {
        VStack(spacing: LT.space8) {
            HStack(spacing: LT.space8) {
                ForEach(["CPU", "MEM", "DISK"], id: \.self) { label in
                    LTGlassCard {
                        VStack(alignment: .leading, spacing: LT.space4) {
                            Text(label)
                                .font(LT.mono(10, weight: .semibold))
                                .foregroundStyle(LT.textMuted)
                                .tracking(1)
                            LTShimmer(height: 24, cornerRadius: LT.radiusSm)
                                .frame(width: 48)
                            LTShimmer(height: 24, cornerRadius: LT.radiusSm)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            LTGlassCard {
                HStack(spacing: LT.space16) {
                    loadingNetworkStatCell(label: "RX")
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [LT.panelBorder.opacity(0), LT.panelBorder, LT.panelBorder.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 0.5, height: 28)
                    loadingNetworkStatCell(label: "TX")
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [LT.panelBorder.opacity(0), LT.panelBorder, LT.panelBorder.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 0.5, height: 28)
                    loadingNetworkStatCell(label: "TEMP")
                    Spacer()
                }
            }
        }
    }

    private func loadingNetworkStatCell(label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(LT.mono(9, weight: .semibold))
                .foregroundStyle(LT.textMuted)
                .tracking(0.5)
            LTShimmer(height: 12, cornerRadius: LT.radiusSm)
                .frame(width: 56)
        }
    }
}
