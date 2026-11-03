import AppKit
import SwiftUI

/// Firing alerts as rows: severity dot, title, summary and the time it fired.
/// The dot colour carries severity. A row opens the Hub's alerts page.
struct AlertRowsView: View {
    let firingAlerts: [AlertSnapshot]
    let consoleBaseURL: URL?
    /// Rows shown before a "more" line. The pop-out shows them all.
    var limit = Int.max
    /// Leading inset of the text column (the pop-out sheet uses a wider gutter).
    var horizontalPadding: CGFloat = LT.space8

    var body: some View {
        VStack(spacing: 0) {
            ForEach(firingAlerts.prefix(limit)) { alert in
                AlertRow(alert: alert, horizontalPadding: horizontalPadding, action: openAlertsPage)
            }
            if firingAlerts.count > limit {
                Button(action: openAlertsPage) {
                    Text("\(firingAlerts.count - limit) more")
                        .font(LT.font(12, weight: .medium))
                        .foregroundStyle(LT.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, horizontalPadding + 24)
                        .frame(height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(firingAlerts.count - limit) more alerts in the web console")
            }
        }
    }

    private func openAlertsPage() {
        guard let base = consoleBaseURL else { return }
        NSApp.activate(ignoringOtherApps: true)
        NSWorkspace.shared.open(base.appendingPathComponent("alerts"))
    }
}

private struct AlertRow: View {
    let alert: AlertSnapshot
    let horizontalPadding: CGFloat
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: LT.space8) {
                LTStatusDot(color: LTSeverity.dotColor(for: alert.severity))
                    .frame(width: 16, height: 18)
                VStack(alignment: .leading, spacing: 0) {
                    Text(alert.title)
                        .font(LT.font(13, weight: .medium))
                        .foregroundStyle(LT.text)
                        .lineLimit(1)
                    if !alert.summary.isEmpty {
                        Text(alert.summary)
                            .font(LT.font(12))
                            .foregroundStyle(LT.text3)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: LT.space8)
                if let timestamp = alert.timestamp {
                    Text(AlertRow.timeText(timestamp))
                        .font(LT.font(12).monospacedDigit())
                        .foregroundStyle(LT.text3)
                        .padding(.top, 1)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: LT.radiusRow, style: .continuous)
                    .fill(isHovered ? LT.sel : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(alert.severity.capitalized) alert, \(alert.title)")
        .accessibilityHint("Opens the alerts page in the web console")
    }

    /// "21:12" today, "3 Nov" before today.
    static func timeText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
