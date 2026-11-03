import SwiftUI

// MARK: - PopOutSessionHistorySection

/// Remote sessions grouped by day, newest first, with a Clear action behind a confirmation.
struct PopOutSessionHistorySection: View {
    @ObservedObject var tracker: SessionHistoryTracker

    @State private var showClearConfirmation = false

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// Records newest first, grouped under "Today", "Yesterday" or a date.
    private var groupedRecords: [(day: String, records: [SessionRecord])] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        let grouped = Dictionary(grouping: tracker.records.reversed()) { record -> String in
            let recordDay = calendar.startOfDay(for: record.timestamp)
            if recordDay == today { return L10n.sessionToday }
            if recordDay == yesterday { return L10n.sessionYesterday }
            return Self.dayFormatter.string(from: record.timestamp)
        }
        return grouped
            .map { (day: $0.key, records: $0.value) }
            .sorted { ($0.records.first?.timestamp ?? .distantPast) > ($1.records.first?.timestamp ?? .distantPast) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LT.space8) {
            LTSectionTitle(L10n.sessionTitle) {
                if !tracker.records.isEmpty {
                    Button(L10n.sessionClear) { showClearConfirmation = true }
                        .buttonStyle(LTTextButtonStyle(fontSize: 12))
                        .accessibilityHint("Removes all recorded session events")
                }
            }
            LTSheet {
                if tracker.records.isEmpty {
                    LTPlaceholderText(text: L10n.sessionEmpty)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(groupedRecords, id: \.day) { group in
                            Text(group.day)
                                .font(LT.font(12, weight: .semibold))
                                .foregroundStyle(LT.text2)
                                .padding(EdgeInsets(top: LT.space8, leading: LT.space12, bottom: 2, trailing: LT.space12))
                            ForEach(group.records) { record in
                                SessionRecordRow(record: record, relativeFormatter: Self.relativeFormatter)
                            }
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("popout-session-history")
        .alert(L10n.sessionClearTitle, isPresented: $showClearConfirmation) {
            Button("Clear", role: .destructive) { tracker.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(L10n.sessionClearMessage)
        }
    }
}

/// One session: outlined type icon, what happened, and how long ago.
private struct SessionRecordRow: View {
    let record: SessionRecord
    let relativeFormatter: RelativeDateTimeFormatter

    private var iconName: String {
        switch record.type {
        case .terminal:     return "terminal"
        case .desktop:      return "desktopcomputer"
        case .fileTransfer: return "folder"
        case .vnc:          return "lt.display"
        }
    }

    var body: some View {
        HStack(spacing: LT.space8) {
            LTIcon(name: iconName)
            Text(record.detail)
                .font(LT.font(13))
                .foregroundStyle(LT.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: LT.space8)
            Text(relativeFormatter.localizedString(for: record.timestamp, relativeTo: Date()))
                .font(LT.font(12).monospacedDigit())
                .foregroundStyle(LT.text3)
        }
        .padding(.horizontal, LT.space12)
        .frame(height: 30)
        .accessibilityElement(children: .combine)
    }
}
