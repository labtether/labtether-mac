import SwiftUI

// MARK: - PopOutBandwidthSection

/// A pop-out dashboard section displaying bandwidth statistics and a 7-day bar chart.
///
/// Shows the current session totals (RX and TX), today's aggregated usage, a 7-day
/// vertical bar chart with proportionally scaled bars, and a 30-day period total.
/// When no samples are available an empty-state message is shown in place of all content.
struct PopOutBandwidthSection: View {

    @ObservedObject var tracker: BandwidthTracker

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: LT.space8) {
            LTSectionHeader(L10n.bandwidthTitle)

            if tracker.samples.isEmpty && tracker.currentSessionRX == 0 && tracker.currentSessionTX == 0 {
                emptyState
            } else {
                LTGlassCard {
                    VStack(alignment: .leading, spacing: LT.space8) {
                        sessionRow
                        todayRow
                        let bars = barChartData()
                        if bars.contains(where: { $0.total > 0 }) {
                            barChart(bars: bars)
                        }
                        thirtyDayRow
                    }
                }
            }
        }
        .padding(.horizontal, LT.space12)
        .accessibilityIdentifier("popout-bandwidth")
    }

    // MARK: - Row Views

    /// "This Session" bandwidth row.
    private var sessionRow: some View {
        HStack {
            Text(L10n.bandwidthThisSession)
                .font(LT.mono(12))
                .foregroundStyle(LT.textSecondary)

            Spacer()

            bandwidthPair(rx: tracker.currentSessionRX, tx: tracker.currentSessionTX)
                .font(LT.mono(12))
        }
    }

    /// Today's aggregated bandwidth row.
    private var todayRow: some View {
        let today = BandwidthPresentation.totalForPeriod(tracker.samples, days: 1)
        return HStack {
            Text(L10n.bandwidthToday)
                .font(LT.mono(12))
                .foregroundStyle(LT.textSecondary)

            Spacer()

            bandwidthPair(rx: today.rx, tx: today.tx)
                .font(LT.mono(12))
        }
    }

    /// Last 30 days total row.
    private var thirtyDayRow: some View {
        let period = BandwidthPresentation.totalForPeriod(tracker.samples, days: 30)
        return HStack {
            Text(L10n.bandwidthLast30Days)
                .font(LT.mono(11))
                .foregroundStyle(LT.textSecondary)

            Spacer()

            bandwidthPair(rx: period.rx, tx: period.tx)
                .font(LT.mono(11))
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Text(L10n.bandwidthEmpty)
            .font(LT.inter(11))
            .foregroundStyle(LT.textMuted)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Bandwidth Pair Helper

    /// Renders a "↓ RX  ↑ TX" pair with semantic colors.
    ///
    /// - Parameters:
    ///   - rx: Received byte count.
    ///   - tx: Transmitted byte count.
    @ViewBuilder
    private func bandwidthPair(rx: UInt64, tx: UInt64) -> some View {
        HStack(spacing: LT.space8) {
            HStack(spacing: LT.space4) {
                Text("↓")
                    .foregroundStyle(LT.ok)
                Text(BandwidthPresentation.formatBytes(rx))
                    .foregroundStyle(LT.textPrimary)
            }
            HStack(spacing: LT.space4) {
                Text("↑")
                    .foregroundStyle(LT.accent)
                Text(BandwidthPresentation.formatBytes(tx))
                    .foregroundStyle(LT.textPrimary)
            }
        }
    }

    // MARK: - Bar Chart

    /// Renders the 7-day vertical bar chart inside a fixed-height container.
    ///
    /// Each bar represents one calendar day. Bars scale proportionally to the tallest
    /// day, with a minimum visual height of 2 pt so empty days remain visible.
    @ViewBuilder
    private func barChart(bars: [DayBar]) -> some View {
        let maxTotal = bars.map(\.total).max() ?? 1
        let chartHeight: CGFloat = 40
        let minBarHeight: CGFloat = 2

        VStack(alignment: .leading, spacing: LT.space4) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(bars) { bar in
                    VStack(spacing: 2) {
                        let proportion = maxTotal > 0
                            ? CGFloat(bar.total) / CGFloat(maxTotal)
                            : 0
                        let barHeight = max(
                            bar.total > 0 ? minBarHeight : 0,
                            proportion * chartHeight
                        )

                        Spacer(minLength: 0)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(LT.accent)
                            .frame(height: barHeight)
                    }
                    .frame(maxWidth: .infinity, minHeight: chartHeight, maxHeight: chartHeight)
                }
            }
            .frame(height: chartHeight)

            HStack(spacing: 0) {
                ForEach(bars) { bar in
                    Text(bar.label)
                        .font(LT.mono(8))
                        .foregroundStyle(LT.textMuted)
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Bar Chart Data

    /// Computes ``DayBar`` entries for each of the last 7 calendar days.
    ///
    /// Days are ordered from 6 days ago (leading) through today (trailing).
    private func barChartData() -> [DayBar] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"

        return (0..<7).map { offset -> DayBar in
            let dayStart = calendar.date(byAdding: .day, value: -(6 - offset), to: today)!
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
            let total = tracker.samples
                .filter { $0.date >= dayStart && $0.date < dayEnd }
                .reduce(UInt64(0)) { $0 + $1.rxBytes + $1.txBytes }
            let label = formatter.string(from: dayStart)
            return DayBar(id: dayStart, label: label, total: total)
        }
    }
}

// MARK: - DayBar Model

/// A single day's aggregated bandwidth total used to drive the bar chart.
private struct DayBar: Identifiable {
    /// The calendar-day boundary used as the stable identifier.
    let id: Date
    /// Abbreviated day name (e.g. "Mon").
    let label: String
    /// Combined RX + TX bytes for the day.
    let total: UInt64
}
