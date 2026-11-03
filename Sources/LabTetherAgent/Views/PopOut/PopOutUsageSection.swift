import SwiftUI

/// Usage: CPU, memory and disk with sparklines, split by spacing, and the network line.
struct PopOutUsageSection: View {
    @ObservedObject var runtime: LocalAPIRuntimeStore
    @ObservedObject var metrics: LocalAPIMetricsStore
    @ObservedObject var agentProcess: AgentProcess

    private var presentation: LocalAPIMetricsPresentation? {
        runtime.snapshot.isReachable ? metrics.snapshot.presentation : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LT.space8) {
            if let syncText = presentation?.network.relativeSyncText {
                LTSectionTitle("Usage", detail: "Updated \(syncText)")
            } else {
                LTSectionTitle("Usage")
            }

            if let presentation {
                LTSheet(padding: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top, spacing: 0) {
                            UsageCell(label: "CPU", gauge: presentation.cpu)
                            UsageCell(label: "Memory", gauge: presentation.memory)
                            UsageCell(label: "Disk", gauge: presentation.disk)
                        }
                        NetworkFiguresRow(network: presentation.network, compact: false)
                            .padding(EdgeInsets(top: 2, leading: 14, bottom: LT.space12, trailing: 14))
                    }
                }
            } else {
                LTSheet {
                    LTPlaceholderText(text: agentProcess.isRunning || agentProcess.isStarting
                                      ? "Waiting for usage"
                                      : "No usage while the agent is stopped")
                }
            }
        }
    }
}

private struct UsageCell: View {
    let label: String
    let gauge: MetricGaugePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(LT.font(12))
                .foregroundStyle(LT.text3)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(gauge.roundedPercent)")
                    .font(LT.font(20, weight: .medium).monospacedDigit())
                    .foregroundStyle(gauge.isHot ? LT.warnText : LT.text)
                Text("%")
                    .font(LT.font(13))
                    .foregroundStyle(LT.text3)
            }
            .padding(.top, 2)
            LTSparkline(
                series: gauge.sparkline,
                color: gauge.isHot ? LT.warn : LT.chart,
                fill: gauge.isHot ? nil : LT.chartFill,
                height: 28
            )
            .padding(.top, LT.space6)
        }
        .padding(EdgeInsets(top: LT.space12, leading: 14, bottom: 10, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(gauge.percentText)
    }
}
