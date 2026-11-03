import SwiftUI

// MARK: - PopOutBandwidthSection

/// Bandwidth totals (this session, today, last 30 days) and a 7-day bar chart in one hue.
struct PopOutBandwidthSection: View {
    @ObservedObject var tracker: BandwidthTracker

    var body: some View {
        VStack(alignment: .leading, spacing: LT.space8) {
            LTSectionTitle(L10n.bandwidthTitle)
            LTSheet {
                if tracker.samples.isEmpty && tracker.currentSessionRX == 0 && tracker.currentSessionTX == 0 {
                    LTPlaceholderText(text: L10n.bandwidthEmpty)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        row(L10n.bandwidthThisSession, rx: tracker.currentSessionRX, tx: tracker.currentSessionTX)
                        let today = BandwidthPresentation.totalForPeriod(tracker.samples, days: 1)
                        row(L10n.bandwidthToday, rx: today.rx, tx: today.tx)
                        let period = BandwidthPresentation.totalForPeriod(tracker.samples, days: 30)
                        row(L10n.bandwidthLast30Days, rx: period.rx, tx: period.tx)
                        let bars = barChartData()
                        if bars.contains(where: { $0.total > 0 }) {
                            barChart(bars: bars)
                                .padding(EdgeInsets(top: LT.space4, leading: LT.space12, bottom: LT.space8, trailing: LT.space12))
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("popout-bandwidth")
    }

    private func row(_ title: String, rx: UInt64, tx: UInt64) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .foregroundStyle(LT.text3)
                .frame(width: 112, alignment: .leading)
            Text("↓ \(BandwidthPresentation.formatBytes(rx))   ↑ \(BandwidthPresentation.formatBytes(tx))")
                .foregroundStyle(LT.text)
                .accessibilityLabel("Down \(BandwidthPresentation.formatBytes(rx)), up \(BandwidthPresentation.formatBytes(tx))")
            Spacer(minLength: 0)
        }
        .font(LT.font(13).monospacedDigit())
        .padding(.horizontal, LT.space12)
        .frame(height: 32)
    }

    // MARK: - Bar chart

    /// One bar per calendar day, scaled to the busiest day; empty days keep a 2 pt stub.
    private func barChart(bars: [DayBar]) -> some View {
        let maxTotal = max(bars.map(\.total).max() ?? 1, 1)
        let chartHeight: CGFloat = 28
        return VStack(alignment: .leading, spacing: LT.space4) {
            HStack(alignment: .bottom, spacing: LT.space6) {
                ForEach(bars) { bar in
                    let height = max(bar.total > 0 ? 2 : 0, CGFloat(bar.total) / CGFloat(maxTotal) * chartHeight)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(LT.chart)
                        .frame(width: 10, height: height)
                        .frame(maxWidth: .infinity, maxHeight: chartHeight, alignment: .bottom)
                }
            }
            HStack(spacing: LT.space6) {
                ForEach(bars) { bar in
                    Text(bar.label)
                        .font(LT.font(11))
                        .foregroundStyle(LT.text3)
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bandwidth for the last 7 days")
    }

    private func barChartData() -> [DayBar] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")

        return (0..<7).compactMap { offset -> DayBar? in
            guard let dayStart = calendar.date(byAdding: .day, value: -(6 - offset), to: today),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
            let total = tracker.samples
                .filter { $0.date >= dayStart && $0.date < dayEnd }
                .reduce(UInt64(0)) { $0 + $1.rxBytes + $1.txBytes }
            return DayBar(id: dayStart, label: formatter.string(from: dayStart), total: total)
        }
    }
}

/// A single day's combined RX + TX total for the bar chart.
private struct DayBar: Identifiable {
    let id: Date
    let label: String
    let total: UInt64
}
