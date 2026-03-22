import XCTest
@testable import LabTetherAgent

final class LogRenderingTests: XCTestCase {
    func testGoTimestampIsRemovedFromDisplayMessageAndSourceIsExtracted() {
        let line = LogLine(id: 1, raw: "2026/03/08 17:31:22 agentws: connected to wss://hub.local/ws/agent")

        XCTAssertEqual(line.timestamp, "17:31:22")
        XCTAssertEqual(line.source, "AGENTWS")
        XCTAssertEqual(line.displayMessage, "connected to wss://hub.local/ws/agent")
    }

    func testBracketPrefixAndANSIAreSanitizedForRendering() {
        let line = LogLine(id: 2, raw: "2026/03/08 17:31:22 [app] \u{001B}[31mCrash loop detected\u{001B}[0m")

        XCTAssertEqual(line.source, "APP")
        XCTAssertEqual(line.displayMessage, "Crash loop detected")
    }

    func testPlainMessageWithoutStructuredPrefixStillRendersCleanly() {
        let line = LogLine(id: 3, raw: "2026/03/08 17:31:22 background sync finished")

        XCTAssertNil(line.source)
        XCTAssertEqual(line.displayMessage, "background sync finished")
    }

    func testDocumentBuilderRendersGapMarkersAndStructuredPrefixes() {
        let lines = [
            LogLine(id: 1, raw: "2026/03/09 12:00:00 [app] launched"),
            LogLine(id: 2, raw: "2026/03/09 12:00:12 warning: reconnecting"),
            LogLine(id: 3, raw: "2026/03/09 12:00:13 heartbeat ok")
        ]

        let rendered = LogTextDocumentBuilder.build(lines: lines).string

        XCTAssertTrue(rendered.contains("12:00:00  [APP] launched"))
        XCTAssertTrue(rendered.contains("+12s"))
        XCTAssertTrue(rendered.contains("12:00:12  [WARNING] reconnecting"))
        XCTAssertTrue(rendered.contains("12:00:13  [ROUTINE] heartbeat ok"))
    }
}

final class LogPipeChunkDecoderTests: XCTestCase {
    func testChunkDecoderBuffersPartialLinesAcrossReads() {
        let decoder = LogPipeChunkDecoder()

        XCTAssertEqual(decoder.ingest(Data("2026/03/08 17:31:22 agent".utf8)), [])
        XCTAssertEqual(
            decoder.ingest(Data("ws: connected\n2026/03/08 17:31:23 warn".utf8)),
            ["2026/03/08 17:31:22 agentws: connected"]
        )
        XCTAssertEqual(
            decoder.ingest(Data("ing: retrying\n".utf8)),
            ["2026/03/08 17:31:23 warning: retrying"]
        )
    }

    func testChunkDecoderFlushesTrailingLineOnFinish() {
        let decoder = LogPipeChunkDecoder()

        XCTAssertEqual(decoder.ingest(Data("[app] Stopping agent...".utf8)), [])
        XCTAssertEqual(decoder.finish(), ["[app] Stopping agent..."])
    }

    func testChunkDecoderBuffersSplitUTF8ScalarsAcrossReads() {
        let decoder = LogPipeChunkDecoder()

        XCTAssertEqual(decoder.ingest(Data([0x63, 0x61, 0x66, 0xC3])), [])
        XCTAssertEqual(decoder.ingest(Data([0xA9, 0x0A])), ["café"])
    }
}

@MainActor
final class LogBufferTests: XCTestCase {
    func testLogBufferRetainsMostRecentWindow() {
        let buffer = LogBuffer()

        for index in 0..<550 {
            buffer.append("[app] line-\(index)")
        }

        XCTAssertEqual(buffer.logLines.count, 500)
        XCTAssertEqual(buffer.logLines.first?.raw, "[app] line-50")
        XCTAssertEqual(buffer.logLines.last?.raw, "[app] line-549")
    }

    func testLogBufferCachesSummaryCountsAndRecentNonRoutineLines() {
        let buffer = LogBuffer()

        buffer.appendBatch([
            "2026/03/09 12:00:00 heartbeat ok",
            "2026/03/09 12:00:01 warning: reconnecting",
            "2026/03/09 12:00:02 [app] launched",
            "2026/03/09 12:00:03 agentws: connected",
            "2026/03/09 12:00:04 error: boom"
        ])

        XCTAssertEqual(buffer.summary.totalCount, 5)
        XCTAssertEqual(buffer.summary.errorCount, 1)
        XCTAssertEqual(buffer.summary.warningCount, 1)
        XCTAssertEqual(buffer.summary.infoCount, 3)
        XCTAssertEqual(
            buffer.recentEventLines.map(\.raw),
            [
                "2026/03/09 12:00:04 error: boom",
                "2026/03/09 12:00:03 agentws: connected",
                "2026/03/09 12:00:02 [app] launched",
                "2026/03/09 12:00:01 warning: reconnecting"
            ]
        )
    }
}
