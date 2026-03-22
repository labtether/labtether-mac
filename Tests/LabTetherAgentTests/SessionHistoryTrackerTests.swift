import XCTest
@testable import LabTetherAgent

@MainActor
final class SessionHistoryTrackerTests: XCTestCase {

    // MARK: - Helpers

    private func makeTempPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
            .path
    }

    private func makeTracker(
        filePath: String? = nil,
        maxRecords: Int = 500,
        maxAgeDays: Int = 30
    ) -> SessionHistoryTracker {
        SessionHistoryTracker(
            filePath: filePath ?? makeTempPath(),
            maxRecords: maxRecords,
            maxAgeDays: maxAgeDays
        )
    }

    // MARK: - 1. testHandleEventCreatesRecordForTerminalSession

    func testHandleEventCreatesRecordForTerminalSession() {
        let tracker = makeTracker()
        let now = Date()

        tracker.handleEvent(.terminalSession(detail: "user@host"), timestamp: now)

        XCTAssertEqual(tracker.records.count, 1)
        let record = tracker.records[0]
        XCTAssertEqual(record.type, .terminal)
        XCTAssertEqual(record.detail, "user@host")
        XCTAssertEqual(record.timestamp, now)
    }

    // MARK: - 2. testHandleEventCreatesRecordForAllSessionTypes

    func testHandleEventCreatesRecordForAllSessionTypes() {
        let tracker = makeTracker()
        let now = Date()

        tracker.handleEvent(.desktopSession(detail: "desktop-info"), timestamp: now)
        tracker.handleEvent(.fileTransfer(detail: "file-info"), timestamp: now)
        tracker.handleEvent(.vncSession(detail: "vnc-info"), timestamp: now)

        XCTAssertEqual(tracker.records.count, 3)

        let types = tracker.records.map(\.type)
        XCTAssertTrue(types.contains(.desktop), "Expected .desktop in records")
        XCTAssertTrue(types.contains(.fileTransfer), "Expected .fileTransfer in records")
        XCTAssertTrue(types.contains(.vnc), "Expected .vnc in records")

        let details = tracker.records.map(\.detail)
        XCTAssertTrue(details.contains("desktop-info"))
        XCTAssertTrue(details.contains("file-info"))
        XCTAssertTrue(details.contains("vnc-info"))
    }

    // MARK: - 3. testHandleEventIgnoresNonSessionEvents

    func testHandleEventIgnoresNonSessionEvents() {
        let tracker = makeTracker()
        let now = Date()

        tracker.handleEvent(.connected(url: "wss://hub.example.com"), timestamp: now)
        tracker.handleEvent(.heartbeat(detail: "ok"), timestamp: now)
        tracker.handleEvent(.info(scope: "agent", message: "started"), timestamp: now)
        tracker.handleEvent(.reconnecting(delay: "5s", error: "timeout"), timestamp: now)
        tracker.handleEvent(.enrolled(assetID: "abc-123"), timestamp: now)

        XCTAssertEqual(tracker.records.count, 0, "Non-session events must not create records")
    }

    // MARK: - 4. testPruneRemovesRecordsOlderThan30Days

    func testPruneRemovesRecordsOlderThan30Days() {
        let tracker = makeTracker(maxAgeDays: 30)
        let now = Date()
        let thirtyOneDaysAgo = now.addingTimeInterval(-31 * 24 * 60 * 60)
        let twentyNineDaysAgo = now.addingTimeInterval(-29 * 24 * 60 * 60)

        tracker.handleEvent(.terminalSession(detail: "old"), timestamp: thirtyOneDaysAgo)
        tracker.handleEvent(.terminalSession(detail: "recent"), timestamp: twentyNineDaysAgo)

        tracker.prune()

        XCTAssertEqual(tracker.records.count, 1, "Only the recent record should survive")
        XCTAssertEqual(tracker.records[0].detail, "recent")
    }

    // MARK: - 5. testPruneEnforcesMaxRecordCount

    func testPruneEnforcesMaxRecordCount() {
        let tracker = makeTracker(maxRecords: 3)
        let now = Date()

        // Insert 5 records with distinct timestamps (oldest first)
        for index in 0..<5 {
            let timestamp = now.addingTimeInterval(Double(index))
            tracker.handleEvent(.terminalSession(detail: "record-\(index)"), timestamp: timestamp)
        }

        tracker.prune()

        XCTAssertEqual(tracker.records.count, 3, "Prune must cap at maxRecords")

        // The 3 most recent records (indices 2, 3, 4) should survive
        let details = tracker.records.map(\.detail)
        XCTAssertTrue(details.contains("record-2"), "record-2 should survive")
        XCTAssertTrue(details.contains("record-3"), "record-3 should survive")
        XCTAssertTrue(details.contains("record-4"), "record-4 should survive")
        XCTAssertFalse(details.contains("record-0"), "record-0 (oldest) should be pruned")
        XCTAssertFalse(details.contains("record-1"), "record-1 (2nd oldest) should be pruned")
    }

    // MARK: - 6. testSaveAndLoadRoundTrip

    func testSaveAndLoadRoundTrip() {
        let path = makeTempPath()
        let tracker = SessionHistoryTracker(filePath: path, maxRecords: 500, maxAgeDays: 30)
        let now = Date()

        tracker.handleEvent(.terminalSession(detail: "ssh session"), timestamp: now)
        tracker.handleEvent(.desktopSession(detail: "desktop session"), timestamp: now)

        tracker.save()

        // Load from the same path using a fresh tracker instance
        let loaded = SessionHistoryTracker(filePath: path, maxRecords: 500, maxAgeDays: 30)

        XCTAssertEqual(loaded.records.count, 2, "Loaded tracker should have 2 records")

        let loadedDetails = loaded.records.map(\.detail).sorted()
        XCTAssertEqual(loadedDetails, ["desktop session", "ssh session"].sorted())

        let loadedTypes = loaded.records.map(\.type)
        XCTAssertTrue(loadedTypes.contains(.terminal))
        XCTAssertTrue(loadedTypes.contains(.desktop))

        // IDs and timestamps should round-trip exactly
        let originalIDs = Set(tracker.records.map(\.id))
        let loadedIDs = Set(loaded.records.map(\.id))
        XCTAssertEqual(originalIDs, loadedIDs, "UUIDs must survive JSON round-trip")
    }

    // MARK: - 7. testClearHistoryRemovesAllRecords

    func testClearHistoryRemovesAllRecords() {
        let path = makeTempPath()
        let tracker = SessionHistoryTracker(filePath: path, maxRecords: 500, maxAgeDays: 30)
        let now = Date()

        tracker.handleEvent(.terminalSession(detail: "session-a"), timestamp: now)
        tracker.handleEvent(.vncSession(detail: "session-b"), timestamp: now)
        tracker.save()

        XCTAssertEqual(tracker.records.count, 2, "Precondition: 2 records before clear")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path), "File should exist after save")

        tracker.clearHistory()

        XCTAssertEqual(tracker.records.count, 0, "clearHistory must empty the records array")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path), "clearHistory must delete the file")
    }
}
