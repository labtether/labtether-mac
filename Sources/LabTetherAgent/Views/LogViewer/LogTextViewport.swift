import AppKit
import SwiftUI

// MARK: - Log Viewer

struct LogTextViewport: NSViewRepresentable {
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

struct LogTextContentSignature: Equatable {
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
