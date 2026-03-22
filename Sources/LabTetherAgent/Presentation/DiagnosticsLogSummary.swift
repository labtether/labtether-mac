import Foundation

struct DiagnosticsLogSummary: Equatable {
    let totalCount: Int
    let errorCount: Int
    let warningCount: Int
    let infoCount: Int

    init(logLines: [LogLine]) {
        totalCount = logLines.count
        errorCount = logLines.filter { $0.level == .error }.count
        warningCount = logLines.filter { $0.level == .warning }.count
        infoCount = logLines.filter { $0.level == .info }.count
    }

    var reportLines: [String] {
        [
            "Buffered Logs: \(totalCount) total (\(errorCount) error, \(warningCount) warning, \(infoCount) info)",
            "Recent raw log lines are omitted from clipboard diagnostics for redaction safety. Use the Agent Logs window for full local details."
        ]
    }
}
