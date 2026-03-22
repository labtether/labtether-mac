import Foundation
import os.signpost

enum LTPerformanceSignposts {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.labtether.mac-agent"
    private static let log = OSLog(subsystem: subsystem, category: "Performance")

    static func beginLocalStatusPoll() -> OSSignpostID {
        let signpostID = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "LocalStatusPoll", signpostID: signpostID)
        return signpostID
    }

    static func endLocalStatusPoll(
        _ signpostID: OSSignpostID,
        outcome: Int,
        httpStatus: Int = 0,
        payloadBytes: Int = 0
    ) {
        os_signpost(
            .end,
            log: log,
            name: "LocalStatusPoll",
            signpostID: signpostID,
            "outcome=%d http=%d bytes=%d",
            outcome,
            httpStatus,
            payloadBytes
        )
    }

    static func emitMetricsHistoryAppend(retainedSamples: Int) {
        os_signpost(
            .event,
            log: log,
            name: "MetricsHistoryAppend",
            "retained=%d",
            retainedSamples
        )
    }

    static func emitLogBufferAppend(batchCount: Int, retainedLines: Int) {
        os_signpost(
            .event,
            log: log,
            name: "LogBufferAppend",
            "batch=%d retained=%d",
            batchCount,
            retainedLines
        )
    }

    static func emitMenuBarLabelRefresh(changed: Bool, menuVisible: Bool) {
        os_signpost(
            .event,
            log: log,
            name: "MenuBarLabelRefresh",
            "changed=%d menuVisible=%d",
            changed ? 1 : 0,
            menuVisible ? 1 : 0
        )
    }
}
