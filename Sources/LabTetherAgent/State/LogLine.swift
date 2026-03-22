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
    let source: String?
    let message: String
    let searchableText: String

    init(id: Int, raw: String) {
        self.id = id
        self.raw = raw
        self.timestamp = LogLine.parseTimestamp(raw)
        self.timestampDate = LogLine.parseTimestampDate(raw)
        self.level = LogLine.parseLevel(raw)

        let normalized = LogLine.normalizedDisplayContent(from: raw)
        let withoutTimestamp = LogLine.stripTimestampPrefix(normalized)
        let parsed = LogLine.parseDisplayComponents(withoutTimestamp)

        self.source = parsed.source
        self.message = parsed.message.isEmpty ? normalized : parsed.message
        self.searchableText = [raw, parsed.source ?? "", parsed.message].joined(separator: " ")
    }

    private static func parseTimestamp(_ line: String) -> String {
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

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static func parseTimestampDate(_ line: String) -> Date? {
        let ts = parseTimestamp(line)
        guard ts.count == 8 else { return nil }
        return timestampFormatter.date(from: ts)
    }

    private static func parseLevel(_ line: String) -> LogLevel {
        let lower = line.lowercased()

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

    var isRoutine: Bool {
        let lower = raw.lowercased()
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
    @Published private(set) var logLines: [LogLine] = []
    @Published private(set) var recentEventLines: [LogLine] = []
    @Published private(set) var summary = LogBufferSummary()
    private let maxLines = 500
    private var nextID = 0
    private var storage: [LogLine?]
    private var headIndex = 0
    private var count = 0

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
        if count < maxLines {
            storage[(headIndex + count) % maxLines] = logLine
            count += 1
        } else {
            storage[headIndex] = logLine
            headIndex = (headIndex + 1) % maxLines
        }
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
