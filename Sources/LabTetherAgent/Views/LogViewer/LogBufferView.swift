import AppKit
import SwiftUI

// MARK: - Log Viewer

private struct LogTextViewport: NSViewRepresentable {
    let lines: [LogLine]
    let autoScroll: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.lineFragmentPadding = 0
        textView.layoutManager?.allowsNonContiguousLayout = true

        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        let signature = LogTextContentSignature(lines: lines)
        if context.coordinator.lastSignature != signature {
            if context.coordinator.canAppendIncrementally(lines: lines) {
                textView.textStorage?.append(
                    LogTextDocumentBuilder.build(lines: lines, from: context.coordinator.lastLineCount)
                )
            } else {
                textView.textStorage?.setAttributedString(LogTextDocumentBuilder.build(lines: lines))
            }
            context.coordinator.updateSnapshot(lines: lines, signature: signature)
        }
        if autoScroll {
            textView.scrollToEndOfDocument(nil)
        }
    }

    final class Coordinator {
        weak var textView: NSTextView?
        var lastSignature = LogTextContentSignature(lines: [])
        var lastLineCount = 0
        var firstLineID: Int?
        var lastLineID: Int?

        func canAppendIncrementally(lines: [LogLine]) -> Bool {
            guard lastLineCount > 0,
                  lines.count > lastLineCount,
                  firstLineID == lines.first?.id,
                  lastLineID == lines[lastLineCount - 1].id else {
                return false
            }
            return true
        }

        func updateSnapshot(lines: [LogLine], signature: LogTextContentSignature) {
            lastSignature = signature
            lastLineCount = lines.count
            firstLineID = lines.first?.id
            lastLineID = lines.last?.id
        }
    }
}

private struct LogTextContentSignature: Equatable {
    let count: Int
    let contentHash: Int

    init(lines: [LogLine]) {
        count = lines.count
        var hasher = Hasher()
        for line in lines {
            hasher.combine(line.id)
        }
        contentHash = hasher.finalize()
    }
}

enum LogTextDocumentBuilder {
    private static let timestampAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor(LT.textMuted)
    ]

    private static let sourceAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
    ]

    private static let messageFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let separatorAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
        .foregroundColor: NSColor(LT.textMuted)
    ]

    static func build(lines: [LogLine]) -> NSAttributedString {
        build(lines: lines, from: 0)
    }

    static func build(lines: [LogLine], from startIndex: Int) -> NSAttributedString {
        let output = NSMutableAttributedString()
        guard startIndex < lines.count else {
            return output
        }
        for index in startIndex..<lines.count {
            let line = lines[index]
            if let gap = gapInterval(at: index, lines: lines) {
                output.append(
                    NSAttributedString(
                        string: "+\(Int(gap.rounded()))s\n",
                        attributes: separatorAttributes
                    )
                )
            }

            output.append(
                NSAttributedString(
                    string: line.displayTimestamp + "  ",
                    attributes: timestampAttributes
                )
            )

            if let source = line.source {
                var attributes = sourceAttributes
                attributes[.foregroundColor] = sourceColor(for: line)
                output.append(NSAttributedString(string: "[\(source)] ", attributes: attributes))
            }

            if line.isRoutine {
                var attributes = sourceAttributes
                attributes[.foregroundColor] = NSColor(LT.textMuted)
                output.append(NSAttributedString(string: "[ROUTINE] ", attributes: attributes))
            }

            output.append(
                NSAttributedString(
                    string: line.displayMessage,
                    attributes: [
                        .font: messageFont,
                        .foregroundColor: messageColor(for: line)
                    ]
                )
            )
            output.append(NSAttributedString(string: "\n"))
        }
        return output
    }

    private static func gapInterval(at index: Int, lines: [LogLine]) -> TimeInterval? {
        guard index > 0 else { return nil }
        let previous = lines[index - 1]
        let current = lines[index]
        guard let previousDate = previous.timestampDate,
              let currentDate = current.timestampDate else { return nil }
        let gap = currentDate.timeIntervalSince(previousDate)
        return gap > 5 ? gap : nil
    }

    private static func sourceColor(for line: LogLine) -> NSColor {
        if line.isWrapperMessage {
            return NSColor(LT.accent)
        }
        return messageColor(for: line)
    }

    private static func messageColor(for line: LogLine) -> NSColor {
        switch line.level {
        case .error:
            return NSColor(LT.bad)
        case .warning:
            return NSColor(LT.warn)
        case .info:
            if line.isRoutine {
                return NSColor(LT.textMuted)
            }
            return line.isWrapperMessage ? NSColor(LT.accent) : NSColor(LT.textSecondary)
        }
    }
}

struct LogBufferView: View {
    @ObservedObject var logBuffer: LogBuffer
    @ObservedObject var status: AgentStatus
    @Environment(\.animationsActive) private var animationsActive

    @State private var autoScroll = true
    @State private var searchText = ""
    @State private var levelFilter: LogLevel?
    @State private var hoveredButton: String?
    @State private var emptyGlow = false
    @FocusState private var searchFocused: Bool

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

    private func dominantGlowColor(for filtered: FilteredLogSnapshot) -> Color {
        if filtered.summary.errorCount > 0 { return LT.bad }
        if filtered.summary.warningCount > 0 { return LT.warn }
        if filtered.containsWrapperMessages { return LT.accent }
        return status.state == .connected ? LT.ok : LT.accent
    }

    var body: some View {
        let filtered = filteredSnapshot
        let glowColor = dominantGlowColor(for: filtered)

        VStack(spacing: LT.space8) {
            toolbar(filtered: filtered, glowColor: glowColor)
            logContent(filtered: filtered, glowColor: glowColor)
            statusBar(filtered: filtered)
        }
        .padding(LT.space12)
        .frame(minWidth: 700, minHeight: 460)
        .background(
            ZStack {
                LT.bg
                RadialGradient(
                    colors: [LT.accent.opacity(0.03), Color.clear],
                    center: UnitPoint(x: 0.12, y: 0.0),
                    startRadius: 0,
                    endRadius: 260
                )
                RadialGradient(
                    colors: [glowColor.opacity(0.035), Color.clear],
                    center: UnitPoint(x: 0.92, y: 0.08),
                    startRadius: 0,
                    endRadius: 220
                )
            }
        )
    }

    // MARK: - Toolbar

    private func toolbar(filtered: FilteredLogSnapshot, glowColor: Color) -> some View {
        LTGlassCard(glowColor: searchFocused ? LT.accent : glowColor) {
            VStack(spacing: LT.space8) {
                HStack(spacing: LT.space8) {
                    HStack(spacing: LT.space6) {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(glowColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Activity Log")
                                .font(LT.sora(13, weight: .semibold))
                                .foregroundStyle(LT.textPrimary)

                            Text(toolbarSubtitle(filtered: filtered))
                                .font(LT.inter(10))
                                .foregroundStyle(LT.textMuted)
                        }
                    }

                    Spacer()

                    copyButton
                    clearButton
                    autoScrollButton
                }

                HStack(spacing: LT.space8) {
                    searchField
                    levelFilterMenu
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(LT.textMuted)

            TextField("Filter logs...", text: $searchText)
                .textFieldStyle(.plain)
                .font(LT.mono(12))
                .foregroundStyle(LT.textPrimary)
                .focused($searchFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(LT.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, LT.space8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(LT.panelGlass, in: RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous))
        .ltFocusRing(searchFocused)
    }

    private var levelFilterMenu: some View {
        Menu {
            Button {
                levelFilter = nil
            } label: {
                if levelFilter == nil {
                    Label("All Levels", systemImage: "checkmark")
                } else {
                    Text("All Levels")
                }
            }

            Divider()

            ForEach(LogLevel.allCases, id: \.self) { level in
                Button {
                    levelFilter = level
                } label: {
                    if levelFilter == level {
                        Label(level.label, systemImage: "checkmark")
                    } else {
                        Text(level.label)
                    }
                }
            }
        } label: {
            HStack(spacing: LT.space4) {
                if let level = levelFilter {
                    LTStatusDot(color: levelDotColor(level), size: 6)
                    Text(level.label)
                        .font(LT.inter(11, weight: .medium))
                } else {
                    Text("All")
                        .font(LT.inter(11, weight: .medium))
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(LT.textSecondary)
            .padding(.horizontal, LT.space8)
            .padding(.vertical, 5)
            .background(LT.panelGlass, in: Capsule())
            .overlay(Capsule().strokeBorder(LT.panelBorder, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var copyButton: some View {
        ghostButton(icon: "doc.on.doc", id: "copy", tooltip: "Copy All") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(logBuffer.text, forType: .string)
        }
    }

    private var clearButton: some View {
        ghostButton(icon: "trash", id: "clear", tooltip: "Clear") {
            logBuffer.clear()
        }
    }

    private var autoScrollButton: some View {
        Button {
            autoScroll.toggle()
        } label: {
            HStack(spacing: LT.space4) {
                LTStatusDot(color: autoScroll ? LT.accent : LT.textMuted, size: 6)
                Text(autoScroll ? "Live Tail" : "Paused")
                    .font(LT.mono(10, weight: .medium))
                    .foregroundStyle(autoScroll ? LT.accent : (hoveredButton == "scroll" ? LT.textPrimary : LT.textSecondary))
            }
            .padding(.horizontal, LT.space8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous)
                    .fill(hoveredButton == "scroll" ? LT.hover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in hoveredButton = h ? "scroll" : nil }
        .help("Auto-scroll")
        .animation(.easeInOut(duration: LT.animFast), value: autoScroll)
    }

    // MARK: - Log Content

    private func logContent(filtered: FilteredLogSnapshot, glowColor: Color) -> some View {
        LTGlassCard(glowColor: glowColor) {
            if filtered.lines.isEmpty {
                emptyLogState
            } else {
                LogTextViewport(lines: filtered.lines, autoScroll: autoScroll)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, LT.space4)
            }
        }
    }

    private var emptyLogState: some View {
        VStack(spacing: LT.space16) {
            ZStack {
                Circle()
                    .fill(LT.textMuted.opacity(emptyGlow ? 0.08 : 0.03))
                    .frame(width: 84, height: 84)
                    .animation(
                        animationsActive ? .easeInOut(duration: LT.breatheDuration).repeatForever(autoreverses: true) : .default,
                        value: emptyGlow
                    )

                Image(systemName: searchText.isEmpty ? "terminal" : "magnifyingglass")
                    .font(.system(size: 30, weight: .thin))
                    .foregroundStyle(LT.textMuted.opacity(emptyGlow ? 0.65 : 0.4))
                    .animation(
                        animationsActive ? .easeInOut(duration: LT.breatheDuration).repeatForever(autoreverses: true) : .default,
                        value: emptyGlow
                    )
            }

            VStack(spacing: LT.space4) {
                Text(searchText.isEmpty ? "Waiting for agent output" : "No matching lines")
                    .font(LT.inter(13, weight: .medium))
                    .foregroundStyle(LT.textSecondary)

                Text(searchText.isEmpty ? "New events will flow in here automatically." : "Try broadening the filter or switching the level view.")
                    .font(LT.inter(11))
                    .foregroundStyle(LT.textMuted)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .onAppear { emptyGlow = animationsActive }
        .onChange(of: animationsActive) { emptyGlow = $0 }
    }

    // MARK: - Status Bar

    private func statusBar(filtered: FilteredLogSnapshot) -> some View {
        LTGlassCard {
            HStack(spacing: LT.space8) {
                statCapsule("ERR", count: filtered.summary.errorCount, color: LT.bad)
                statCapsule("WARN", count: filtered.summary.warningCount, color: LT.warn)
                statCapsule("INFO", count: filtered.summary.infoCount, color: LT.textSecondary)

                if filtered.isFiltered {
                    Text("Filtered \(filtered.summary.totalCount) of \(logBuffer.summary.totalCount)")
                        .font(LT.mono(10))
                        .foregroundStyle(LT.textMuted)
                }

                Spacer()

                HStack(spacing: LT.space4) {
                    LTStatusDot(color: autoScroll ? LT.accent : LT.textMuted, size: 6)
                    Text(autoScroll ? "LIVE TAIL" : "MANUAL SCROLL")
                        .font(LT.mono(10, weight: .medium))
                        .foregroundStyle(autoScroll ? LT.accent : LT.textMuted)
                }

                HStack(spacing: LT.space4) {
                    LTStatusDot(color: stateColor(status.state), size: 6)
                    Text(status.state.rawValue.uppercased())
                        .font(LT.mono(10, weight: .medium))
                        .foregroundStyle(LT.textSecondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func toolbarSubtitle(filtered: FilteredLogSnapshot) -> String {
        if !searchText.isEmpty {
            return "\(filtered.summary.totalCount) matching lines"
        }
        return "\(logBuffer.summary.totalCount) line buffer"
    }

    private func levelDotColor(_ level: LogLevel) -> Color {
        switch level {
        case .error:   return LT.bad
        case .warning: return LT.warn
        case .info:    return LT.textSecondary
        }
    }

    private func stateColor(_ state: ConnectionState) -> Color {
        switch state {
        case .connected:                 return LT.ok
        case .reconnecting, .enrolling: return LT.warn
        case .starting:                  return LT.accent
        case .stopped, .error:           return LT.bad
        }
    }

    private func statCapsule(_ label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 5) {
            LTStatusDot(color: color, size: 5)
            Text("\(label) \(count)")
                .font(LT.mono(10, weight: .medium))
                .foregroundStyle(count == 0 ? LT.textMuted : color)
        }
        .padding(.horizontal, LT.space8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(count == 0 ? LT.panelGlass : color.opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(count == 0 ? LT.panelBorder : color.opacity(0.18), lineWidth: 0.5)
        )
    }

    private func ghostButton(icon: String, id: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hoveredButton == id ? LT.accent : LT.textSecondary)
                .scaleEffect(hoveredButton == id ? 1.1 : 1.0)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous)
                        .fill(hoveredButton == id ? LT.accent.opacity(0.1) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LT.radiusSm, style: .continuous)
                        .strokeBorder(hoveredButton == id ? LT.accent.opacity(0.25) : Color.clear, lineWidth: 0.5)
                )
                .shadow(color: hoveredButton == id ? LT.accent.opacity(0.2) : Color.clear, radius: 4)
        }
        .buttonStyle(LTPressButtonStyle())
        .onHover { hoveredButton = $0 ? id : nil }
        .animation(.easeInOut(duration: LT.animFast), value: hoveredButton)
        .help(tooltip)
    }
}
