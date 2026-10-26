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

    func testSanitizerPreservesPrintableAndUnicodeTextAndRemovesControls() {
        let plain = LogLine(id: 1, raw: "   printable ASCII 123   ")
        XCTAssertEqual(plain.displayMessage, "printable ASCII 123")
        let unicode = LogLine(id: 2, raw: "café\u{0085}\t🦀\u{0007}")
        XCTAssertEqual(unicode.displayMessage, "café\u{0085}    🦀")
        XCTAssertTrue(LogLine(id: 3, raw: "HEARTBEAT sent OK").isRoutine)
        XCTAssertFalse(LogLine(id: 4, raw: "background sync finished").isRoutine)
    }

    func testTimestampCachePreservesGapDatesAcrossRepeatedAndChangedSeconds() throws {
        let first = try XCTUnwrap(LogLine(id: 1, raw: "2026/10/09 12:34:56 first").timestampDate)
        XCTAssertEqual(LogLine(id: 2, raw: "2026/10/09 12:34:56 second").timestampDate, first)
        XCTAssertNil(LogLine(id: 3, raw: "2026/10/09 99:99:99 invalid").timestampDate)
        let later = try XCTUnwrap(LogLine(id: 4, raw: "2026/10/09 12:35:08 later").timestampDate)
        XCTAssertEqual(later.timeIntervalSince(first), 12)
        XCTAssertEqual(LogLine(id: 5, raw: "2026/10/09 12:34:56 earlier").timestampDate, first)
    }

    func testLogClassificationAndTimestampRenderingPreserveASCIIAndUnicodeBehavior() {
        let cases: [(String, LogLevel, Bool)] = [
            ("WARN retry after ERROR", .error, false),
            ("HEARTBEAT sent OK", .info, true),
            ("ping timeout", .warning, true),
            ("🦀 ERROR heartbeat", .error, true),
            ("café WARN sent OK", .warning, true),
            ("e\u{301}rror héartbeat", .info, false),
            ("nothing happened", .info, false)
        ]
        for (raw, level, routine) in cases {
            let line = LogLine(id: 1, raw: raw)
            XCTAssertEqual(line.level, level, raw)
            XCTAssertEqual(line.isRoutine, routine, raw)
            XCTAssertEqual(line.timestamp, "", raw)
            XCTAssertEqual(line.displayMessage, raw, raw)
        }
        for prefix in ["2026-10-09T12:34:56Z", "2026/10/09 12:34:56", "12:34:56"] {
            let line = LogLine(id: 1, raw: "\(prefix) 🦀 ready")
            XCTAssertEqual(line.timestamp, "12:34:56")
            XCTAssertEqual(line.displayMessage, "🦀 ready")
        }
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
            [.init(text: "2026/03/08 17:31:22 agentws: connected", isContinuation: false)]
        )
        XCTAssertEqual(
            decoder.ingest(Data("ing: retrying\n".utf8)),
            [.init(text: "2026/03/08 17:31:23 warning: retrying", isContinuation: false)]
        )
    }

    func testChunkDecoderFlushesTrailingLineOnFinish() {
        let decoder = LogPipeChunkDecoder()

        XCTAssertEqual(decoder.ingest(Data("[app] Stopping agent...".utf8)), [])
        XCTAssertEqual(decoder.finish(), [.init(text: "[app] Stopping agent...", isContinuation: false)])
    }

    func testChunkDecoderBuffersSplitUTF8ScalarsAcrossReads() {
        let decoder = LogPipeChunkDecoder()

        XCTAssertEqual(decoder.ingest(Data([0x63, 0x61, 0x66, 0xC3])), [])
        XCTAssertEqual(decoder.ingest(Data([0xA9, 0x0A])), [.init(text: "café", isContinuation: false)])
    }

    func testLongFragmentSurvivesManyReadsAndResetsAfterLineAndFinish() {
        let decoder = LogPipeChunkDecoder()
        let fragment = String(repeating: "x", count: 1_024)
        for _ in 0..<64 {
            XCTAssertEqual(decoder.ingest(Data(fragment.utf8)), [])
        }
        XCTAssertEqual(
            decoder.ingest(Data("\r\nnext\ntrailing".utf8)),
            [.init(text: String(repeating: fragment, count: 64), isContinuation: false),
             .init(text: "next", isContinuation: false)]
        )
        XCTAssertEqual(decoder.finish(), [.init(text: "trailing", isContinuation: false)])
        XCTAssertEqual(decoder.ingest(Data("fresh\n".utf8)), [.init(text: "fresh", isContinuation: false)])
    }

    func testUnterminatedOutputEmitsBoundedFragmentsAndResetsOnFinish() {
        let decoder = LogPipeChunkDecoder()
        let limit = LogPipeChunkDecoder.maximumPendingBytes
        let chunk = Data(repeating: 0x78, count: 1_024)
        var emittedBytes = 0
        for read in 1...1_025 {
            let lines = decoder.ingest(chunk)
            XCTAssertTrue(lines.allSatisfy(\.isContinuation))
            for line in lines {
                XCTAssertEqual(line.text, String(repeating: "x", count: limit))
                emittedBytes += line.text.utf8.count
            }
            // Retained data is the input not yet emitted, capped on every read.
            XCTAssertLessThanOrEqual(read * chunk.count - emittedBytes, limit)
        }
        let trailing = decoder.finish()
        XCTAssertTrue(trailing.allSatisfy(\.isContinuation))
        emittedBytes += trailing.reduce(0) { $0 + $1.text.utf8.count }
        XCTAssertEqual(emittedBytes, 1_025 * chunk.count)
        XCTAssertEqual(decoder.finish(), [])
        XCTAssertEqual(decoder.ingest(Data("fresh\n".utf8)), [.init(text: "fresh", isContinuation: false)])
    }

    func testOversizedUTF8LinesKeepScalarsAndTextAcrossReadAndFragmentBoundaries() {
        let limit = LogPipeChunkDecoder.maximumPendingBytes
        for scalar in ["é", "€", "🐱"] {
            for offset in 1..<scalar.utf8.count {
                for splitReads in [false, true] {
                    let decoder = LogPipeChunkDecoder()
                    let original = String(repeating: "x", count: limit - offset)
                        + scalar + String(repeating: "y", count: limit) + scalar + "\u{2028}"
                    let bytes = Data(original.utf8)
                    var lines: [LogPipeChunkDecoder.Line] = []
                    if splitReads {
                        lines += decoder.ingest(Data(bytes.prefix(limit)))
                        lines += decoder.ingest(Data(bytes.dropFirst(limit)))
                    } else {
                        lines += decoder.ingest(bytes)
                    }
                    lines += decoder.finish()
                    XCTAssertEqual(lines.map(\.text).joined(), original)
                    XCTAssertTrue(lines.allSatisfy(\.isContinuation))
                    XCTAssertTrue(lines.allSatisfy { $0.text.utf8.count <= limit })
                }
            }
        }
    }

    func testOversizedFragmentsCannotTriggerLifecycleOrAuthenticationEvents() {
        let limit = LogPipeChunkDecoder.maximumPendingBytes
        let parser = LogParser()
        for token in ["agent: removed consumed enrollment token file",
                      "agentws: auth failure: invalid token",
                      "agentws: connected to wss://hub.local/ws/agent",
                      "agent: enrolled successfully as asset-123"] {
            let decoder = LogPipeChunkDecoder()
            let first = token + String(repeating: " ", count: limit - token.utf8.count)
            let fragments = decoder.ingest(Data((first + token + "\n" + token + "\n").utf8))
            XCTAssertEqual(fragments.count, 3)
            for fragment in fragments.prefix(2) {
                XCTAssertTrue(fragment.isContinuation)
                XCTAssertEqual(AgentProcess.logEvent(for: fragment, parser: parser), .unknown(line: fragment.text))
            }
            let complete = fragments[2]
            XCTAssertFalse(complete.isContinuation)
            XCTAssertEqual(AgentProcess.logEvent(for: complete, parser: parser), parser.parse(token))
            XCTAssertNotEqual(parser.parse(token), .unknown(line: token))
        }
    }
}

@MainActor
final class LogBufferTests: XCTestCase {
    func testOversizedLogFloodRetainsNewestCompleteTextWithinByteBudget() {
        let buffer = LogBuffer()
        let body = String(repeating: "é", count: 32_765)
        let lines = (0..<80).map { "\($0):\(body)" }
        buffer.appendBatch(lines)

        let retained = buffer.logLines.map(\.raw)
        XCTAssertFalse(retained.isEmpty)
        XCTAssertLessThan(retained.count, lines.count)
        XCTAssertLessThanOrEqual(retained.reduce(0) { $0 + $1.utf8.count }, 4 * 1024 * 1024)
        XCTAssertEqual(retained, Array(lines.suffix(retained.count)))
        XCTAssertEqual(buffer.summary.totalCount, retained.count)

        buffer.clear()
        buffer.appendBatch((0..<500).map { "normal-\($0)" })
        XCTAssertEqual(buffer.logLines.count, 500)
        XCTAssertEqual(buffer.logLines.first?.raw, "normal-0")
        XCTAssertEqual(buffer.logLines.last?.raw, "normal-499")
    }

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
