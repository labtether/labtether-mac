import SwiftUI

// MARK: - PopOutSessionHistorySection

/// A pop-out dashboard section that displays session history records grouped by calendar day.
///
/// Records are sourced from a ``SessionHistoryTracker`` and grouped into labelled day buckets
/// ("Today", "Yesterday", or a formatted date). A "Clear History" action button is provided
/// with a destructive confirmation alert to prevent accidental data loss.
struct PopOutSessionHistorySection: View {
    @ObservedObject var tracker: SessionHistoryTracker

    @State private var showClearConfirmation = false

    // MARK: - Cached formatters

    /// Formats a `Date` into a human-readable day label ("Today", "Yesterday", or "Mar 12").
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    /// Produces short relative timestamp strings ("3 min. ago", "1 hr. ago").
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    // MARK: - Derived data

    /// Records reversed so newest appear first, then grouped by their day label.
    private var groupedRecords: [(day: String, records: [SessionRecord])] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        let grouped = Dictionary(
            grouping: tracker.records.reversed(),
            by: { record -> String in
                let recordDay = calendar.startOfDay(for: record.timestamp)
                if recordDay == today {
                    return L10n.sessionToday
                } else if recordDay == yesterday {
                    return L10n.sessionYesterday
                } else {
                    return Self.dayFormatter.string(from: record.timestamp)
                }
            }
        )

        // Sort groups by the timestamp of the first (newest) record in each group,
        // descending so the most recent day appears first.
        return grouped
            .map { (day: $0.key, records: $0.value) }
            .sorted { lhs, rhs in
                let lhsDate = lhs.records.first?.timestamp ?? .distantPast
                let rhsDate = rhs.records.first?.timestamp ?? .distantPast
                return lhsDate > rhsDate
            }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: LT.space8) {
            headerRow

            if tracker.records.isEmpty {
                emptyState
            } else {
                LTGlassCard {
                    VStack(spacing: 0) {
                        ForEach(Array(groupedRecords.enumerated()), id: \.element.day) { groupIndex, group in
                            if groupIndex > 0 {
                                Divider()
                                    .background(LT.panelBorder)
                                    .padding(.vertical, LT.space4)
                            }

                            dayHeader(group.day)

                            ForEach(group.records) { record in
                                SessionRecordRow(
                                    record: record,
                                    relativeFormatter: Self.relativeFormatter
                                )
                            }
                        }
                    }
                    .padding(-LT.space12)
                }
            }

            if !tracker.records.isEmpty {
                clearButton
            }
        }
        .padding(.horizontal, LT.space12)
        .accessibilityIdentifier("popout-session-history")
        .alert(L10n.sessionClearTitle, isPresented: $showClearConfirmation) {
            Button("Clear", role: .destructive) {
                tracker.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(L10n.sessionClearMessage)
        }
    }

    // MARK: - Subviews

    /// Section header with title and record count badge.
    private var headerRow: some View {
        HStack(spacing: LT.space8) {
            Text("// \(L10n.sessionTitle)")
                .font(LT.mono(10, weight: .medium))
                .foregroundStyle(LT.textMuted)
                .tracking(1)

            if !tracker.records.isEmpty {
                Text("\(tracker.records.count)")
                    .font(LT.mono(9, weight: .bold))
                    .foregroundStyle(LT.accent)
                    .padding(.horizontal, LT.space4)
                    .padding(.vertical, 2)
                    .background(LT.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }

            Spacer()
        }
    }

    /// Displays the day label above its group of records.
    private func dayHeader(_ day: String) -> some View {
        HStack {
            Text(day.uppercased())
                .font(LT.mono(10, weight: .medium))
                .foregroundStyle(LT.textSecondary)
                .tracking(0.5)
            Spacer()
        }
        .padding(.horizontal, LT.space12)
        .padding(.top, LT.space8)
        .padding(.bottom, LT.space4)
    }

    /// Empty state shown when no sessions have been recorded yet.
    private var emptyState: some View {
        LTGlassCard {
            Text(L10n.sessionEmpty)
                .font(LT.inter(12))
                .foregroundStyle(LT.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Destructive "Clear History" action button.
    private var clearButton: some View {
        HStack {
            Spacer()
            Button(L10n.sessionClear) {
                showClearConfirmation = true
            }
            .font(LT.inter(11))
            .foregroundStyle(LT.textMuted)
            .buttonStyle(.plain)
            .accessibilityHint("Removes all recorded session events")
        }
    }
}

// MARK: - SessionRecordRow

/// A single row displaying a session record with its type icon, detail text, and relative timestamp.
private struct SessionRecordRow: View {
    let record: SessionRecord
    let relativeFormatter: RelativeDateTimeFormatter

    private var iconName: String {
        switch record.type {
        case .terminal:     return "terminal.fill"
        case .desktop:      return "desktopcomputer"
        case .fileTransfer: return "folder.fill"
        case .vnc:          return "display"
        }
    }

    private var iconColor: Color {
        switch record.type {
        case .terminal:     return LT.ok
        case .desktop:      return LT.accent
        case .fileTransfer: return LT.warn
        case .vnc:          return LT.accent
        }
    }

    private var relativeTimestamp: String {
        relativeFormatter.localizedString(for: record.timestamp, relativeTo: Date())
    }

    var body: some View {
        HStack(spacing: LT.space8) {
            Image(systemName: iconName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 14, alignment: .center)

            Text(record.detail)
                .font(LT.inter(12))
                .foregroundStyle(LT.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Text(relativeTimestamp)
                .font(LT.mono(10))
                .foregroundStyle(LT.textMuted)
        }
        .padding(.horizontal, LT.space12)
        .padding(.vertical, LT.space4 + 1)
    }
}
