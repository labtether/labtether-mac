import Foundation

// MARK: - Log Line Model

enum LogLevel: String, CaseIterable {
    case error, warning, info

    var label: String {
        switch self {
        case .error:   return "Errors"
        case .warning: return "Warnings"
        case .info:    return "Info"
        }
    }

    var icon: String {
        switch self {
        case .error:   return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info:    return "circle.fill"
        }
    }
}

struct LogLine: Identifiable {
    let id: Int
    let raw: String
    let timestamp: String
    let timestampDate: Date?
    let level: LogLevel
    let isRoutine: Bool
    let source: String?
    let message: String
    let searchableText: String

    init(id: Int, raw: String) {
        self.id = id
        self.raw = raw
        self.timestamp = LogLine.parseTimestamp(raw)
        self.timestampDate = LogLine.timestampDates.date(from: timestamp)
        let lowercase = SearchText(raw.lowercased())
        self.level = LogLine.parseLevel(lowercase)
        self.isRoutine = LogLine.parseRoutine(lowercase)

        let normalized = LogLine.normalizedDisplayContent(from: raw)
        let withoutTimestamp = LogLine.stripTimestampPrefix(normalized)
        let parsed = LogLine.parseDisplayComponents(withoutTimestamp)

        self.source = parsed.source
        self.message = parsed.message.isEmpty ? normalized : parsed.message
        self.searchableText = [raw, parsed.source ?? "", parsed.message].joined(separator: " ")
    }

    private static func parseTimestamp(_ line: String) -> String {
        guard line.utf8.contains(0x3A) else { return "" }
        if let tRange = line.range(of: #"\d{4}-\d{2}-\d{2}T(\d{2}:\d{2}:\d{2})"#, options: .regularExpression) {
            let match = line[tRange]
            if let tIdx = match.firstIndex(of: "T") {
                let afterT = match[match.index(after: tIdx)...]
                return String(afterT.prefix(8))
            }
        }

        if let range = line.range(of: #"\d{4}/\d{2}/\d{2}\s+(\d{2}:\d{2}:\d{2})"#, options: .regularExpression) {
            let match = String(line[range])
            if let spaceIdx = match.lastIndex(of: " ") {
                return String(match[match.index(after: spaceIdx)...].prefix(8))
            }
        }

        if line.count >= 8 {
            let prefix = String(line.prefix(8))
            if prefix.range(of: #"^\d{2}:\d{2}:\d{2}$"#, options: .regularExpression) != nil {
                return prefix
            }
        }

        return ""
    }

    private static let timestampDates = TimestampDateCache()

    /// A log burst commonly shares one second. Keep just that last conversion
    /// instead of asking the calendar parser to repeat it for every line.
    private final class TimestampDateCache {
        private let lock = NSLock()
        private let formatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            return formatter
        }()
        private var previousTimestamp: String?
        private var previousDate: Date?

        func date(from timestamp: String) -> Date? {
            guard timestamp.count == 8 else { return nil }
            lock.lock()
            defer { lock.unlock() }
            if previousTimestamp != timestamp {
                previousDate = formatter.date(from: timestamp)
                previousTimestamp = timestamp
            }
            return previousDate
        }
    }

    /// ASCII log tokens need only literal matching. Keep Swift's Unicode
    /// matching for all other text, including its canonical-equivalence rules.
    private struct SearchText {
        let text: String
        let ascii: NSString?

        init(_ text: String) {
            self.text = text
            self.ascii = text.utf8.allSatisfy { $0 < 0x80 } ? text as NSString : nil
        }

        func contains(_ token: String) -> Bool {
            if let ascii {
                return ascii.range(of: token, options: .literal).location != NSNotFound
            }
            return text.contains(token)
        }
    }

    private static func parseLevel(_ lower: SearchText) -> LogLevel {
        if lower.contains("error") || lower.contains("fatal") || lower.contains("failed") ||
            lower.contains("panic") || lower.contains("crash") {
            return .error
        }

        if lower.contains("warn") || lower.contains("timeout") || lower.contains("retry") ||
            lower.contains("crash loop") {
            return .warning
        }

        return .info
    }

    private static func normalizedDisplayContent(from raw: String) -> String {
        // Normal child logs are printable ASCII. Keep their text directly;
        // Unicode, controls, tabs and ANSI escapes use the full sanitizer below.
        if raw.utf8.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let withoutANSI = raw.replacingOccurrences(
            of: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]",
            with: "",
            options: .regularExpression
        )

        let filteredScalars = String.UnicodeScalarView(
            withoutANSI.unicodeScalars.filter {
                !CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0)
            }
        )

        return String(filteredScalars)
            .replacingOccurrences(of: "\t", with: "    ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func stripTimestampPrefix(_ line: String) -> String {
        guard line.utf8.contains(0x3A) else { return line.trimmingCharacters(in: .whitespaces) }
        let isoPattern = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})?\s*"#
        if let range = line.range(of: isoPattern, options: .regularExpression) {
            return String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }

        let goPattern = #"^\d{4}/\d{2}/\d{2}\s+\d{2}:\d{2}:\d{2}\s+"#
        if let range = line.range(of: goPattern, options: .regularExpression) {
            return String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }

        let shortPattern = #"^\d{2}:\d{2}:\d{2}\s+"#
        if let range = line.range(of: shortPattern, options: .regularExpression) {
            return String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }

        return line.trimmingCharacters(in: .whitespaces)
    }

    private static func parseDisplayComponents(_ line: String) -> (source: String?, message: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return (nil, "") }

        if trimmed.hasPrefix("["),
           let close = trimmed.firstIndex(of: "]"),
           close > trimmed.index(after: trimmed.startIndex) {
            let source = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
            let messageStart = trimmed.index(after: close)
            let message = String(trimmed[messageStart...]).trimmingCharacters(in: .whitespaces)
            return (normalizedSource(source), message)
        }

        if let colon = trimmed.firstIndex(of: ":") {
            let candidate = String(trimmed[..<colon])
            if candidate.count >= 2,
               candidate.count <= 24,
               candidate.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil {
                let messageStart = trimmed.index(after: colon)
                let message = String(trimmed[messageStart...]).trimmingCharacters(in: .whitespaces)
                return (normalizedSource(candidate), message)
            }
        }

        return (nil, trimmed)
    }

    private static func normalizedSource(_ source: String) -> String {
        source.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func parseRoutine(_ lower: SearchText) -> Bool {
        return lower.contains("heartbeat") ||
            lower.contains("ping") ||
            lower.contains("pong") ||
            lower.contains("sent ok")
    }

    var displayTimestamp: String {
        timestamp.isEmpty ? "--:--:--" : timestamp
    }

    var displayMessage: String {
        message.isEmpty ? raw : message
    }

    var isWrapperMessage: Bool {
        source == "APP"
    }
}

struct LogBufferSummary: Equatable {
    var totalCount = 0
    var errorCount = 0
    var warningCount = 0
    var infoCount = 0
}

// MARK: - Log Buffer

@MainActor
final class LogBuffer: ObservableObject {
    // The row limit alone cannot bound memory when child logs contain huge lines.
    static let maximumRetainedRawBytes = 4 * 1024 * 1024
    @Published private(set) var logLines: [LogLine] = []
    @Published private(set) var recentEventLines: [LogLine] = []
    @Published private(set) var summary = LogBufferSummary()
    private let maxLines = 500
    private var nextID = 0
    private var storage: [LogLine?]
    private var headIndex = 0
    private var count = 0
    private var retainedRawBytes = 0

    init() {
        storage = Array(repeating: nil, count: maxLines)
    }

    func append(_ line: String) {
        appendBatch([line])
    }

    func appendBatch(_ lines: [String]) {
        guard !lines.isEmpty else { return }
        var appendedCount = 0
        for line in lines where !line.isEmpty {
            let logLine = LogLine(id: nextID, raw: line)
            nextID += 1
            appendToStorage(logLine)
            appendedCount += 1
        }
        rebuildPublishedState()
        if appendedCount > 0 {
            LTPerformanceSignposts.emitLogBufferAppend(batchCount: appendedCount, retainedLines: count)
        }
    }

    func clear() {
        storage = Array(repeating: nil, count: maxLines)
        headIndex = 0
        count = 0
        retainedRawBytes = 0
        logLines = []
        recentEventLines = []
        summary = LogBufferSummary()
    }

    var text: String {
        logLines.map(\.raw).joined(separator: "\n")
    }

    func tail(_ count: Int) -> [String] {
        Array(logLines.suffix(count).map(\.raw))
    }

    private func appendToStorage(_ logLine: LogLine) {
        let byteCount = logLine.raw.utf8.count
        while count > 0 && (count == maxLines || retainedRawBytes + byteCount > Self.maximumRetainedRawBytes) {
            removeOldest()
        }
        // Pipe input is already split into 64 KiB fragments. Also enforce the
        // retention bound for direct wrapper messages, without clipping text.
        guard byteCount <= Self.maximumRetainedRawBytes else { return }
        storage[(headIndex + count) % maxLines] = logLine
        count += 1
        retainedRawBytes += byteCount
    }

    private func removeOldest() {
        if let oldest = storage[headIndex] {
            retainedRawBytes -= oldest.raw.utf8.count
        }
        storage[headIndex] = nil
        headIndex = (headIndex + 1) % maxLines
        count -= 1
    }

    private func rebuildPublishedState() {
        var lines: [LogLine] = []
        lines.reserveCapacity(count)
        var nextSummary = LogBufferSummary(totalCount: count)
        for offset in 0..<count {
            if let line = storage[(headIndex + offset) % maxLines] {
                lines.append(line)
                switch line.level {
                case .error:
                    nextSummary.errorCount += 1
                case .warning:
                    nextSummary.warningCount += 1
                case .info:
                    nextSummary.infoCount += 1
                }
            }
        }
        logLines = lines
        summary = nextSummary
        recentEventLines = buildRecentEventLines(from: lines)
    }

    private func buildRecentEventLines(from lines: [LogLine]) -> [LogLine] {
        var recent: [LogLine] = []
        recent.reserveCapacity(10)
        for line in lines.reversed() where !line.isRoutine {
            recent.append(line)
            if recent.count == 10 {
                break
            }
        }
        return recent
    }
}
