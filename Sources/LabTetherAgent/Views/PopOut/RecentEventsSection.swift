import SwiftUI

/// Isolates log-buffer observation so incoming log lines do not invalidate the entire pop-out view.
struct RecentEventsSectionView: View {
    @ObservedObject var logBuffer: LogBuffer

    private var recentEventLines: [LogLine] {
        logBuffer.recentEventLines
    }

    var body: some View {
        VStack(spacing: LT.space8) {
            LTSectionHeader("RECENT EVENTS")

            if recentEventLines.isEmpty {
                LTGlassCard {
                    LTEmptyState(
                        icon: "text.alignleft",
                        title: "No events recorded",
                        subtitle: "Events will appear here as they occur"
                    )
                    .padding(-LT.space12)
                }
            } else {
                LTGlassCard {
                    VStack(spacing: 0) {
                        ForEach(Array(recentEventLines.enumerated()), id: \.element.id) { idx, line in
                            EventRowView(line: line, stripTimestamp: stripTimestamp)
                                .background(idx % 2 == 1 ? LT.hover.opacity(0.3) : Color.clear)
                            if idx < recentEventLines.count - 1 {
                                Divider()
                                    .background(LT.panelBorder)
                                    .opacity(0.3)
                            }
                        }
                    }
                    .padding(-LT.space12)
                }
            }
        }
    }

    /// Strips the leading Go log timestamp from a raw log line for compact display.
    private func stripTimestamp(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Go timestamp: "YYYY/MM/DD HH:MM:SS " (20 chars)
        if trimmed.count > 20,
           trimmed[trimmed.index(trimmed.startIndex, offsetBy: 4)] == "/",
           trimmed[trimmed.index(trimmed.startIndex, offsetBy: 7)] == "/",
           trimmed[trimmed.index(trimmed.startIndex, offsetBy: 10)] == " ",
           trimmed[trimmed.index(trimmed.startIndex, offsetBy: 19)] == " " {
            return String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 20)...])
        }
        return trimmed
    }
}

/// A single event row with a colored severity edge bar.
struct EventRowView: View {
    let line: LogLine
    let stripTimestamp: (String) -> String

    private func levelColor(_ level: LogLevel) -> Color {
        switch level {
        case .error:   return LT.bad
        case .warning: return LT.warn
        case .info:    return LT.ok
        }
    }

    private var levelIcon: String {
        switch line.level {
        case .error:   return "exclamationmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info:    return "info.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Colored severity edge bar
            LTSeverityEdge(color: levelColor(line.level))
                .padding(.vertical, 2)

            HStack(spacing: LT.space6) {
                Image(systemName: levelIcon)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(levelColor(line.level))

                Text(line.timestamp.isEmpty ? "--:--:--" : line.timestamp)
                    .font(LT.mono(10))
                    .foregroundStyle(LT.textMuted)
                    .frame(width: 52, alignment: .leading)

                Text(stripTimestamp(line.raw))
                    .font(LT.inter(11))
                    .foregroundStyle(LT.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, LT.space6)
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
