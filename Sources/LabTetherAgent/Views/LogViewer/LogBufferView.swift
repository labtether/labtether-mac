import AppKit
import SwiftUI

struct LogBufferView: View {
    @ObservedObject var logBuffer: LogBuffer
    @ObservedObject var status: AgentStatus
    @State private var autoScroll = true
    @State private var searchText = ""
    @State private var levelFilter: LogLevel?

    private struct FilteredLogSnapshot {
        let lines: [LogLine]
        let summary: LogBufferSummary
        let containsWrapperMessages: Bool
        let isFiltered: Bool
    }

    private var filteredSnapshot: FilteredLogSnapshot {
        guard levelFilter != nil || !searchText.isEmpty else {
            return FilteredLogSnapshot(
                lines: logBuffer.logLines,
                summary: logBuffer.summary,
                containsWrapperMessages: logBuffer.logLines.contains(where: \.isWrapperMessage),
                isFiltered: false
            )
        }

        var filtered: [LogLine] = []
        filtered.reserveCapacity(logBuffer.logLines.count)
        var summary = LogBufferSummary()
        var containsWrapperMessages = false

        for line in logBuffer.logLines {
            if let levelFilter, line.level != levelFilter {
                continue
            }
            if !searchText.isEmpty && !line.searchableText.localizedCaseInsensitiveContains(searchText) {
                continue
            }
            filtered.append(line)
            summary.totalCount += 1
            containsWrapperMessages = containsWrapperMessages || line.isWrapperMessage
            switch line.level {
            case .error:
                summary.errorCount += 1
            case .warning:
                summary.warningCount += 1
            case .info:
                summary.infoCount += 1
            }
        }

        return FilteredLogSnapshot(
            lines: filtered,
            summary: summary,
            containsWrapperMessages: containsWrapperMessages,
            isFiltered: true
        )
    }

    var body: some View {
        let filtered = filteredSnapshot

        VStack(alignment: .leading, spacing: LT.space12) {
            toolbar(filtered: filtered)
            LTSheet(padding: 0) {
                if filtered.lines.isEmpty {
                    Text(searchText.isEmpty && levelFilter == nil ? "No agent output yet" : "No matching lines")
                        .font(LT.font(13))
                        .foregroundStyle(LT.text3)
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    LogTextViewport(lines: filtered.lines, autoScroll: autoScroll)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
            statusBar(filtered: filtered)
        }
        .padding(LT.space16)
        .frame(minWidth: 700, minHeight: 460)
        .background(LT.canvas)
    }

    // MARK: - Toolbar

    private func toolbar(filtered: FilteredLogSnapshot) -> some View {
        HStack(spacing: LT.space8) {
            LTTextField(label: "Filter logs", text: $searchText, prompt: "Filter logs", accessory: {
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(LT.text3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear filter")
                }
            })
            .frame(maxWidth: 320)

            Picker("Level", selection: $levelFilter) {
                Text("All levels").tag(LogLevel?.none)
                ForEach(LogLevel.allCases, id: \.self) { level in
                    Text(level.label).tag(LogLevel?.some(level))
                }
            }
            .labelsHidden()
            .fixedSize()

            Spacer(minLength: LT.space8)

            Button(autoScroll ? "Following" : "Paused") { autoScroll.toggle() }
                .buttonStyle(LTSecondaryButtonStyle())
                .help(autoScroll ? "Stop following new lines" : "Follow new lines")
            LTQuietIconButton(systemImage: "doc.on.doc", label: "Copy all") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(logBuffer.text, forType: .string)
            }
            LTQuietIconButton(systemImage: "trash", label: "Clear") {
                logBuffer.clear()
            }
        }
    }

    // MARK: - Status Bar

    private func statusBar(filtered: FilteredLogSnapshot) -> some View {
        HStack(spacing: LT.space6) {
            Text(countsText(filtered.summary))
                .foregroundStyle(filtered.summary.errorCount > 0 ? LT.badText : LT.text3)
            if filtered.isFiltered {
                Text("· showing \(filtered.summary.totalCount) of \(logBuffer.summary.totalCount)")
                    .foregroundStyle(LT.text3)
            }
            Spacer(minLength: LT.space8)
            LTStatusDot(color: status.state.color, size: 6)
            Text(status.state.rawValue)
                .foregroundStyle(LT.text2)
        }
        .font(LT.font(12).monospacedDigit())
        .padding(.horizontal, LT.space4)
    }

    private func countsText(_ summary: LogBufferSummary) -> String {
        "\(summary.errorCount) errors · \(summary.warningCount) warnings · \(summary.infoCount) info"
    }
}
