import SwiftUI

/// Isolates log-buffer observation so incoming log lines do not invalidate the entire pop-out view.
struct RecentEventsSectionView: View {
    @ObservedObject var logBuffer: LogBuffer

    var body: some View {
        let lines = logBuffer.recentEventLines
        VStack(alignment: .leading, spacing: LT.space8) {
            LTSectionTitle("Recent events")
            LTSheet {
                if lines.isEmpty {
                    LTPlaceholderText(text: "No events yet")
                } else {
                    VStack(spacing: 0) {
                        ForEach(lines) { line in
                            EventRowView(line: line)
                        }
                    }
                }
            }
        }
    }
}

/// One event: time in the UI font, the log message in mono, a dot only for warnings and errors.
struct EventRowView: View {
    let line: LogLine

    private var dotColor: Color? {
        switch line.level {
        case .error: return LT.bad
        case .warning: return LT.warn
        case .info: return nil
        }
    }

    var body: some View {
        HStack(spacing: LT.space8) {
            Text(EventRowView.shortTime(line.timestamp))
                .font(LT.font(12).monospacedDigit())
                .foregroundStyle(LT.text3)
                .frame(width: 40, alignment: .leading)
            if let dotColor {
                LTStatusDot(color: dotColor, size: 6)
            }
            Text(LogLine.stripTimestampPrefix(line.raw).trimmingCharacters(in: .whitespacesAndNewlines))
                .font(LT.mono(12))
                .foregroundStyle(LT.text2)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LT.space12)
        .frame(height: 32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let level: String
        switch line.level {
        case .error: level = "Error, "
        case .warning: level = "Warning, "
        case .info: level = ""
        }
        return "\(level)\(EventRowView.shortTime(line.timestamp)), \(LogLine.stripTimestampPrefix(line.raw))"
    }

    /// "20:47" from the agent's "HH:MM:SS" (or longer) timestamp.
    static func shortTime(_ timestamp: String) -> String {
        guard !timestamp.isEmpty else { return "--:--" }
        let clock = timestamp.split(separator: " ").last.map(String.init) ?? timestamp
        let parts = clock.split(separator: ":")
        guard parts.count >= 2 else { return clock }
        return "\(parts[0]):\(parts[1])"
    }
}
