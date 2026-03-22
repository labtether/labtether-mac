# Session History & Cumulative Bandwidth Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add persistent session history tracking and cumulative bandwidth accumulation with pop-out dashboard UI sections.

**Architecture:** Two `@MainActor ObservableObject` trackers owned by `AppState`. JSON file persistence in Application Support. Session events forwarded from `AgentProcess.handleParsedLines()`. Bandwidth accumulated from `LocalAPIMetricsStore.$snapshot` changes. UI as new sections in the existing pop-out dashboard.

**Tech Stack:** Swift 5.9+, SwiftUI, macOS 13+, Foundation (JSONEncoder/Decoder, FileManager), Combine, XCTest

**Spec:** `docs/superpowers/specs/2026-03-15-session-bandwidth-design.md`

---

## Chunk 1: Session History

### Task 1: Create SessionHistoryTracker service

**Files:**
- Create: `Sources/LabTetherAgent/Services/SessionHistoryTracker.swift`
- Test: `Tests/LabTetherAgentTests/SessionHistoryTrackerTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/LabTetherAgentTests/SessionHistoryTrackerTests.swift`:

```swift
import XCTest
@testable import LabTetherAgent

@MainActor
final class SessionHistoryTrackerTests: XCTestCase {

    private func makeTempPath() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("session-history.json").path
    }

    func testHandleEventCreatesRecordForTerminalSession() {
        let tracker = SessionHistoryTracker(filePath: makeTempPath())
        tracker.handleEvent(.terminalSession(detail: "started for user root"), timestamp: Date())

        XCTAssertEqual(tracker.records.count, 1)
        XCTAssertEqual(tracker.records.first?.type, .terminal)
        XCTAssertEqual(tracker.records.first?.detail, "started for user root")
    }

    func testHandleEventCreatesRecordForAllSessionTypes() {
        let tracker = SessionHistoryTracker(filePath: makeTempPath())
        let now = Date()
        tracker.handleEvent(.desktopSession(detail: "connected"), timestamp: now)
        tracker.handleEvent(.fileTransfer(detail: "upload 2.3MB"), timestamp: now)
        tracker.handleEvent(.vncSession(detail: "viewer attached"), timestamp: now)

        XCTAssertEqual(tracker.records.count, 3)
        XCTAssertEqual(tracker.records[0].type, .desktop)
        XCTAssertEqual(tracker.records[1].type, .fileTransfer)
        XCTAssertEqual(tracker.records[2].type, .vnc)
    }

    func testHandleEventIgnoresNonSessionEvents() {
        let tracker = SessionHistoryTracker(filePath: makeTempPath())
        tracker.handleEvent(.connected(url: "wss://hub"), timestamp: Date())
        tracker.handleEvent(.heartbeat(detail: "ok"), timestamp: Date())
        tracker.handleEvent(.info(scope: "agent", message: "started"), timestamp: Date())

        XCTAssertTrue(tracker.records.isEmpty)
    }

    func testPruneRemovesRecordsOlderThan30Days() {
        let tracker = SessionHistoryTracker(filePath: makeTempPath())
        let old = Date().addingTimeInterval(-31 * 24 * 3600)
        let recent = Date()
        tracker.handleEvent(.terminalSession(detail: "old"), timestamp: old)
        tracker.handleEvent(.terminalSession(detail: "recent"), timestamp: recent)

        tracker.prune()

        XCTAssertEqual(tracker.records.count, 1)
        XCTAssertEqual(tracker.records.first?.detail, "recent")
    }

    func testPruneEnforcesMaxRecordCount() {
        let path = makeTempPath()
        let tracker = SessionHistoryTracker(filePath: path, maxRecords: 3)
        for i in 0..<5 {
            tracker.handleEvent(
                .terminalSession(detail: "session \(i)"),
                timestamp: Date().addingTimeInterval(Double(i))
            )
        }

        tracker.prune()

        XCTAssertEqual(tracker.records.count, 3)
        // Should keep the 3 most recent
        XCTAssertEqual(tracker.records.last?.detail, "session 4")
    }

    func testSaveAndLoadRoundTrip() {
        let path = makeTempPath()
        let tracker1 = SessionHistoryTracker(filePath: path)
        let now = Date()
        tracker1.handleEvent(.terminalSession(detail: "ssh root"), timestamp: now)
        tracker1.handleEvent(.fileTransfer(detail: "upload"), timestamp: now)
        tracker1.save()

        let tracker2 = SessionHistoryTracker(filePath: path)
        XCTAssertEqual(tracker2.records.count, 2)
        XCTAssertEqual(tracker2.records[0].type, .terminal)
        XCTAssertEqual(tracker2.records[1].type, .fileTransfer)
    }

    func testClearHistoryRemovesAllRecords() {
        let tracker = SessionHistoryTracker(filePath: makeTempPath())
        tracker.handleEvent(.terminalSession(detail: "test"), timestamp: Date())

        tracker.clearHistory()

        XCTAssertTrue(tracker.records.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SessionHistoryTrackerTests 2>&1 | tail -10`
Expected: Compilation error — `SessionHistoryTracker` not found

- [ ] **Step 3: Create SessionHistoryTracker**

Create `Sources/LabTetherAgent/Services/SessionHistoryTracker.swift`:

```swift
import Foundation

/// Type of remote session.
enum SessionType: String, Codable, CaseIterable {
    case terminal
    case desktop
    case fileTransfer
    case vnc
}

/// A recorded remote session event.
struct SessionRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let type: SessionType
    let detail: String
    let timestamp: Date
}

/// Tracks remote session events and persists them to a JSON file.
@MainActor
final class SessionHistoryTracker: ObservableObject {
    @Published private(set) var records: [SessionRecord] = []

    private let filePath: String
    private let maxRecords: Int
    private let maxAgeDays: Int
    private var saveTimer: Timer?

    init(
        filePath: String,
        maxRecords: Int = 500,
        maxAgeDays: Int = 30
    ) {
        self.filePath = filePath
        self.maxRecords = maxRecords
        self.maxAgeDays = maxAgeDays
        load()
    }

    /// Process an agent event. Creates a record if it's a session event, ignores otherwise.
    func handleEvent(_ event: AgentEvent, timestamp: Date) {
        guard let type = sessionType(from: event) else { return }
        let detail = sessionDetail(from: event)
        let record = SessionRecord(
            id: UUID(),
            type: type,
            detail: detail,
            timestamp: timestamp
        )
        records.append(record)
        scheduleDebouncedSave()
    }

    /// Remove records older than maxAgeDays and enforce maxRecords cap.
    func prune() {
        let cutoff = Date().addingTimeInterval(-Double(maxAgeDays) * 24 * 3600)
        records = records.filter { $0.timestamp > cutoff }
        if records.count > maxRecords {
            records = Array(records.suffix(maxRecords))
        }
    }

    /// Remove all records and delete the file.
    func clearHistory() {
        records = []
        try? FileManager.default.removeItem(atPath: filePath)
        saveTimer?.invalidate()
        saveTimer = nil
    }

    /// Write records to disk immediately.
    func save() {
        saveTimer?.invalidate()
        saveTimer = nil
        prune()
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(records)
            let url = URL(fileURLWithPath: filePath)
            let parent = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try data.write(to: url, options: .atomic)
        } catch {
            // Silently fail — persistence is best-effort
        }
    }

    // MARK: - Private

    private func load() {
        let url = URL(fileURLWithPath: filePath)
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([SessionRecord].self, from: data) {
            records = loaded
            prune()
        }
    }

    private func scheduleDebouncedSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.save()
            }
        }
    }

    private func sessionType(from event: AgentEvent) -> SessionType? {
        switch event {
        case .terminalSession: return .terminal
        case .desktopSession: return .desktop
        case .fileTransfer: return .fileTransfer
        case .vncSession: return .vnc
        default: return nil
        }
    }

    private func sessionDetail(from event: AgentEvent) -> String {
        switch event {
        case .terminalSession(let detail),
             .desktopSession(let detail),
             .fileTransfer(let detail),
             .vncSession(let detail):
            return detail
        default:
            return ""
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SessionHistoryTrackerTests 2>&1 | tail -20`
Expected: All 7 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/LabTetherAgent/Services/SessionHistoryTracker.swift \
  Tests/LabTetherAgentTests/SessionHistoryTrackerTests.swift
git commit -m "feat: add SessionHistoryTracker with JSON persistence and pruning"
```

---

### Task 2: Create BandwidthTracker service

**Files:**
- Create: `Sources/LabTetherAgent/Services/BandwidthTracker.swift`
- Test: `Tests/LabTetherAgentTests/BandwidthTrackerTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/LabTetherAgentTests/BandwidthTrackerTests.swift`:

```swift
import XCTest
@testable import LabTetherAgent

@MainActor
final class BandwidthTrackerTests: XCTestCase {

    private func makeTempPath() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("bandwidth-history.json").path
    }

    private func makeSnapshot(
        rxPerSec: Double,
        txPerSec: Double,
        collectedAt: Date?
    ) -> MetricsSnapshot {
        MetricsSnapshot(
            cpuPercent: 0,
            memoryPercent: 0,
            diskPercent: 0,
            netRXBytesPerSec: rxPerSec,
            netTXBytesPerSec: txPerSec,
            tempCelsius: nil,
            collectedAt: collectedAt
        )
    }

    func testAccumulateAddsBytes() {
        let tracker = BandwidthTracker(filePath: makeTempPath())
        let t0 = Date(timeIntervalSince1970: 1000)
        let t1 = t0.addingTimeInterval(5) // 5 seconds later

        tracker.accumulate(makeSnapshot(rxPerSec: 100, txPerSec: 50, collectedAt: t0))
        tracker.accumulate(makeSnapshot(rxPerSec: 100, txPerSec: 50, collectedAt: t1))

        // 100 bytes/sec * 5 sec = 500 bytes
        XCTAssertEqual(tracker.currentSessionRX, 500)
        XCTAssertEqual(tracker.currentSessionTX, 250)
    }

    func testAccumulateSkipsNilCollectedAt() {
        let tracker = BandwidthTracker(filePath: makeTempPath())
        let t0 = Date(timeIntervalSince1970: 1000)

        tracker.accumulate(makeSnapshot(rxPerSec: 100, txPerSec: 50, collectedAt: t0))
        tracker.accumulate(makeSnapshot(rxPerSec: 100, txPerSec: 50, collectedAt: nil))

        XCTAssertEqual(tracker.currentSessionRX, 0) // no accumulation — only one sample with time
    }

    func testAccumulateSkipsLargeGaps() {
        let tracker = BandwidthTracker(filePath: makeTempPath())
        let t0 = Date(timeIntervalSince1970: 1000)
        let t1 = t0.addingTimeInterval(100) // 100 seconds — exceeds 90s threshold

        tracker.accumulate(makeSnapshot(rxPerSec: 1000, txPerSec: 500, collectedAt: t0))
        tracker.accumulate(makeSnapshot(rxPerSec: 1000, txPerSec: 500, collectedAt: t1))

        XCTAssertEqual(tracker.currentSessionRX, 0)
        XCTAssertEqual(tracker.currentSessionTX, 0)
    }

    func testAccumulateClampsNegativeRates() {
        let tracker = BandwidthTracker(filePath: makeTempPath())
        let t0 = Date(timeIntervalSince1970: 1000)
        let t1 = t0.addingTimeInterval(5)

        tracker.accumulate(makeSnapshot(rxPerSec: -100, txPerSec: -50, collectedAt: t0))
        tracker.accumulate(makeSnapshot(rxPerSec: -100, txPerSec: -50, collectedAt: t1))

        XCTAssertEqual(tracker.currentSessionRX, 0)
        XCTAssertEqual(tracker.currentSessionTX, 0)
    }

    func testResetSessionZerosCurrentCounters() {
        let tracker = BandwidthTracker(filePath: makeTempPath())
        let t0 = Date(timeIntervalSince1970: 1000)
        let t1 = t0.addingTimeInterval(5)

        tracker.accumulate(makeSnapshot(rxPerSec: 100, txPerSec: 50, collectedAt: t0))
        tracker.accumulate(makeSnapshot(rxPerSec: 100, txPerSec: 50, collectedAt: t1))
        tracker.resetSession()

        XCTAssertEqual(tracker.currentSessionRX, 0)
        XCTAssertEqual(tracker.currentSessionTX, 0)
    }

    func testHourlyRolloverCreatesSample() {
        let tracker = BandwidthTracker(filePath: makeTempPath())
        // Start at hour boundary
        let cal = Calendar.current
        let hourStart = cal.date(from: cal.dateComponents([.year, .month, .day, .hour], from: Date()))!
        let t0 = hourStart
        let t1 = t0.addingTimeInterval(10)
        // Jump to next hour
        let t2 = hourStart.addingTimeInterval(3600)
        let t3 = t2.addingTimeInterval(10)

        tracker.accumulate(makeSnapshot(rxPerSec: 100, txPerSec: 50, collectedAt: t0))
        tracker.accumulate(makeSnapshot(rxPerSec: 100, txPerSec: 50, collectedAt: t1))
        // Hour rolls over
        tracker.accumulate(makeSnapshot(rxPerSec: 200, txPerSec: 100, collectedAt: t2))
        tracker.accumulate(makeSnapshot(rxPerSec: 200, txPerSec: 100, collectedAt: t3))

        XCTAssertGreaterThanOrEqual(tracker.samples.count, 1)
    }

    func testSaveAndLoadRoundTrip() {
        let path = makeTempPath()
        let tracker1 = BandwidthTracker(filePath: path)
        let cal = Calendar.current
        let hourStart = cal.date(from: cal.dateComponents([.year, .month, .day, .hour], from: Date()))!
        let t0 = hourStart
        let t1 = t0.addingTimeInterval(10)
        let t2 = hourStart.addingTimeInterval(3600)

        tracker1.accumulate(makeSnapshot(rxPerSec: 100, txPerSec: 50, collectedAt: t0))
        tracker1.accumulate(makeSnapshot(rxPerSec: 100, txPerSec: 50, collectedAt: t1))
        tracker1.accumulate(makeSnapshot(rxPerSec: 200, txPerSec: 100, collectedAt: t2))
        tracker1.save()

        let tracker2 = BandwidthTracker(filePath: path)
        XCTAssertEqual(tracker2.samples.count, tracker1.samples.count)
    }

    func testPruneRemovesSamplesOlderThan30Days() {
        let path = makeTempPath()
        let tracker = BandwidthTracker(filePath: path)
        let old = Date().addingTimeInterval(-31 * 24 * 3600)
        let recent = Date()

        // Manually insert old and recent samples for testing
        tracker.testInsertSample(BandwidthSample(date: old, rxBytes: 100, txBytes: 50))
        tracker.testInsertSample(BandwidthSample(date: recent, rxBytes: 200, txBytes: 100))
        tracker.prune()

        XCTAssertEqual(tracker.samples.count, 1)
        XCTAssertEqual(tracker.samples.first?.rxBytes, 200)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter BandwidthTrackerTests 2>&1 | tail -10`
Expected: Compilation error — `BandwidthTracker` not found

- [ ] **Step 3: Create BandwidthTracker**

Create `Sources/LabTetherAgent/Services/BandwidthTracker.swift`:

```swift
import Foundation

/// An hourly bandwidth sample for persistence.
struct BandwidthSample: Codable, Identifiable, Equatable {
    var id: Date { date }
    let date: Date        // rounded to the hour
    var rxBytes: UInt64
    var txBytes: UInt64
}

/// Accumulates network bandwidth from polling snapshots and persists hourly samples.
@MainActor
final class BandwidthTracker: ObservableObject {
    @Published private(set) var currentSessionRX: UInt64 = 0
    @Published private(set) var currentSessionTX: UInt64 = 0
    @Published private(set) var samples: [BandwidthSample] = []

    private let filePath: String
    private let maxSamples: Int
    private let maxAgeDays: Int
    private let gapThreshold: TimeInterval

    private var lastSampleTime: Date?
    private var currentHourStart: Date?
    private var hourlyRX: UInt64 = 0
    private var hourlyTX: UInt64 = 0

    init(
        filePath: String,
        maxSamples: Int = 720,
        maxAgeDays: Int = 30,
        gapThreshold: TimeInterval = 90
    ) {
        self.filePath = filePath
        self.maxSamples = maxSamples
        self.maxAgeDays = maxAgeDays
        self.gapThreshold = gapThreshold
        load()
    }

    /// Process a new metrics snapshot. Accumulates bytes if the time gap is within threshold.
    func accumulate(_ snapshot: MetricsSnapshot) {
        guard let collectedAt = snapshot.collectedAt else { return }

        defer { lastSampleTime = collectedAt }

        guard let lastTime = lastSampleTime else { return }

        let elapsed = collectedAt.timeIntervalSince(lastTime)
        guard elapsed > 0, elapsed < gapThreshold else { return }

        let rx = max(0, snapshot.netRXBytesPerSec)
        let tx = max(0, snapshot.netTXBytesPerSec)
        let rxDelta = UInt64(rx * elapsed)
        let txDelta = UInt64(tx * elapsed)

        currentSessionRX += rxDelta
        currentSessionTX += txDelta

        // Hourly bucketing
        let hourStart = Self.hourStart(for: collectedAt)
        if currentHourStart == nil {
            currentHourStart = hourStart
        }

        if hourStart != currentHourStart {
            // Hour rolled over — flush previous bucket
            if let prevHour = currentHourStart, (hourlyRX > 0 || hourlyTX > 0) {
                appendOrMergeSample(BandwidthSample(date: prevHour, rxBytes: hourlyRX, txBytes: hourlyTX))
                save()
            }
            currentHourStart = hourStart
            hourlyRX = rxDelta
            hourlyTX = txDelta
        } else {
            hourlyRX += rxDelta
            hourlyTX += txDelta
        }
    }

    /// Reset current session counters (called when agent stops).
    func resetSession() {
        // Flush any in-progress hourly data before resetting
        if let hour = currentHourStart, (hourlyRX > 0 || hourlyTX > 0) {
            appendOrMergeSample(BandwidthSample(date: hour, rxBytes: hourlyRX, txBytes: hourlyTX))
        }
        currentSessionRX = 0
        currentSessionTX = 0
        lastSampleTime = nil
        currentHourStart = nil
        hourlyRX = 0
        hourlyTX = 0
    }

    /// Remove samples older than maxAgeDays and enforce maxSamples cap.
    func prune() {
        let cutoff = Date().addingTimeInterval(-Double(maxAgeDays) * 24 * 3600)
        samples = samples.filter { $0.date > cutoff }
        if samples.count > maxSamples {
            samples = Array(samples.suffix(maxSamples))
        }
    }

    /// Write samples to disk immediately. Flushes any in-progress hourly bucket first.
    func save() {
        // Flush in-progress hourly data so it's not lost on quit
        if let hour = currentHourStart, (hourlyRX > 0 || hourlyTX > 0) {
            appendOrMergeSample(BandwidthSample(date: hour, rxBytes: hourlyRX, txBytes: hourlyTX))
            // Reset counters to prevent double-flush if save() is called again
            hourlyRX = 0
            hourlyTX = 0
            currentHourStart = nil
            // accumulate() will re-establish currentHourStart on next data point
        }
        prune()
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(samples)
            let url = URL(fileURLWithPath: filePath)
            let parent = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try data.write(to: url, options: .atomic)
        } catch {
            // Silently fail — persistence is best-effort
        }
    }

    /// Test helper to insert a sample directly.
    func testInsertSample(_ sample: BandwidthSample) {
        samples.append(sample)
    }

    // MARK: - Private

    private func load() {
        let url = URL(fileURLWithPath: filePath)
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([BandwidthSample].self, from: data) {
            samples = loaded
            prune()
        }
    }

    private func appendOrMergeSample(_ sample: BandwidthSample) {
        if let index = samples.firstIndex(where: { $0.date == sample.date }) {
            samples[index].rxBytes += sample.rxBytes
            samples[index].txBytes += sample.txBytes
        } else {
            samples.append(sample)
            samples.sort { $0.date < $1.date }
        }
    }

    static func hourStart(for date: Date) -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month, .day, .hour], from: date))!
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter BandwidthTrackerTests 2>&1 | tail -20`
Expected: All 8 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/LabTetherAgent/Services/BandwidthTracker.swift \
  Tests/LabTetherAgentTests/BandwidthTrackerTests.swift
git commit -m "feat: add BandwidthTracker with hourly bucketing and JSON persistence"
```

---

### Task 3: Create BandwidthPresentation helpers

**Files:**
- Create: `Sources/LabTetherAgent/Presentation/BandwidthPresentation.swift`
- Test: `Tests/LabTetherAgentTests/BandwidthPresentationTests.swift`

- [ ] **Step 1: Write failing tests**

Create `Tests/LabTetherAgentTests/BandwidthPresentationTests.swift`:

```swift
import XCTest
@testable import LabTetherAgent

final class BandwidthPresentationTests: XCTestCase {

    func testFormatBytesShowsBytes() {
        XCTAssertEqual(BandwidthPresentation.formatBytes(0), "0 B")
        XCTAssertEqual(BandwidthPresentation.formatBytes(512), "512 B")
    }

    func testFormatBytesShowsKB() {
        XCTAssertEqual(BandwidthPresentation.formatBytes(1_536), "1.5 KB")
        XCTAssertEqual(BandwidthPresentation.formatBytes(10_240), "10.0 KB")
    }

    func testFormatBytesShowsMB() {
        XCTAssertEqual(BandwidthPresentation.formatBytes(1_572_864), "1.5 MB")
    }

    func testFormatBytesShowsGB() {
        XCTAssertEqual(BandwidthPresentation.formatBytes(1_610_612_736), "1.5 GB")
    }

    func testFormatBytesShowsTB() {
        XCTAssertEqual(BandwidthPresentation.formatBytes(1_649_267_441_664), "1.5 TB")
    }

    func testDailyTotalsAggregatesByCalendarDay() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

        let samples = [
            BandwidthSample(date: yesterday, rxBytes: 100, txBytes: 50),
            BandwidthSample(date: yesterday.addingTimeInterval(3600), rxBytes: 200, txBytes: 100),
            BandwidthSample(date: today, rxBytes: 300, txBytes: 150),
        ]

        let daily = BandwidthPresentation.dailyTotals(from: samples)
        XCTAssertEqual(daily.count, 2)

        let yesterdayTotal = daily.first { cal.isDate($0.date, inSameDayAs: yesterday) }
        XCTAssertEqual(yesterdayTotal?.rx, 300)
        XCTAssertEqual(yesterdayTotal?.tx, 150)

        let todayTotal = daily.first { cal.isDate($0.date, inSameDayAs: today) }
        XCTAssertEqual(todayTotal?.rx, 300)
        XCTAssertEqual(todayTotal?.tx, 150)
    }

    func testTotalForPeriodSumsCorrectDays() {
        let today = Date()
        let old = today.addingTimeInterval(-10 * 24 * 3600)
        let recent = today.addingTimeInterval(-2 * 24 * 3600)

        let samples = [
            BandwidthSample(date: old, rxBytes: 1000, txBytes: 500),
            BandwidthSample(date: recent, rxBytes: 2000, txBytes: 1000),
            BandwidthSample(date: today, rxBytes: 3000, txBytes: 1500),
        ]

        let total7 = BandwidthPresentation.totalForPeriod(samples, days: 7)
        XCTAssertEqual(total7.rx, 5000) // recent + today
        XCTAssertEqual(total7.tx, 2500)

        let total30 = BandwidthPresentation.totalForPeriod(samples, days: 30)
        XCTAssertEqual(total30.rx, 6000) // all
        XCTAssertEqual(total30.tx, 3000)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter BandwidthPresentationTests 2>&1 | tail -10`
Expected: Compilation error — `BandwidthPresentation` not found

- [ ] **Step 3: Create BandwidthPresentation**

Create `Sources/LabTetherAgent/Presentation/BandwidthPresentation.swift`:

```swift
import Foundation

/// Formatting and aggregation helpers for bandwidth data.
enum BandwidthPresentation {

    /// Format a byte count as human-readable: "1.5 GB", "340 MB", "4.5 KB"
    static func formatBytes(_ bytes: UInt64) -> String {
        let units: [(String, UInt64)] = [
            ("TB", 1_099_511_627_776),
            ("GB", 1_073_741_824),
            ("MB", 1_048_576),
            ("KB", 1_024),
        ]
        for (unit, threshold) in units {
            if bytes >= threshold {
                let value = Double(bytes) / Double(threshold)
                return String(format: "%.1f %@", value, unit)
            }
        }
        return "\(bytes) B"
    }

    /// Aggregate hourly samples into daily totals, sorted by date.
    static func dailyTotals(from samples: [BandwidthSample]) -> [(date: Date, rx: UInt64, tx: UInt64)] {
        let cal = Calendar.current
        var daily: [Date: (rx: UInt64, tx: UInt64)] = [:]

        for sample in samples {
            let dayStart = cal.startOfDay(for: sample.date)
            let existing = daily[dayStart] ?? (rx: 0, tx: 0)
            daily[dayStart] = (rx: existing.rx + sample.rxBytes, tx: existing.tx + sample.txBytes)
        }

        return daily.map { (date: $0.key, rx: $0.value.rx, tx: $0.value.tx) }
            .sorted { $0.date < $1.date }
    }

    /// Sum all samples within the last N days.
    static func totalForPeriod(_ samples: [BandwidthSample], days: Int) -> (rx: UInt64, tx: UInt64) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 3600)
        var rx: UInt64 = 0
        var tx: UInt64 = 0
        for sample in samples where sample.date > cutoff {
            rx += sample.rxBytes
            tx += sample.txBytes
        }
        return (rx: rx, tx: tx)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter BandwidthPresentationTests 2>&1 | tail -20`
Expected: All 6 tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/LabTetherAgent/Presentation/BandwidthPresentation.swift \
  Tests/LabTetherAgentTests/BandwidthPresentationTests.swift
git commit -m "feat: add BandwidthPresentation formatting and aggregation helpers"
```

---

## Chunk 2: UI and Integration

### Task 4: Create PopOutSessionHistorySection

**Files:**
- Create: `Sources/LabTetherAgent/Views/PopOut/PopOutSessionHistorySection.swift`

- [ ] **Step 1: Create the view**

```swift
import SwiftUI

/// Pop-out dashboard section showing historical remote session events.
struct PopOutSessionHistorySection: View {
    @ObservedObject var tracker: SessionHistoryTracker
    @State private var showClearConfirmation = false

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var groupedRecords: [(key: String, records: [SessionRecord])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: tracker.records.reversed()) { record -> String in
            if cal.isDateInToday(record.timestamp) {
                return "Today"
            } else if cal.isDateInYesterday(record.timestamp) {
                return "Yesterday"
            } else {
                return Self.dayFormatter.string(from: record.timestamp)
            }
        }
        // Sort groups by the first record's date (descending)
        return grouped.map { (key: $0.key, records: $0.value) }
            .sorted { lhs, rhs in
                guard let l = lhs.records.first?.timestamp,
                      let r = rhs.records.first?.timestamp else { return false }
                return l > r
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LT.space8) {
            HStack {
                Text("SESSION HISTORY")
                    .font(LT.mono(10, weight: .medium))
                    .foregroundColor(LT.textMuted)

                if !tracker.records.isEmpty {
                    Text("\(tracker.records.count)")
                        .font(LT.mono(9, weight: .bold))
                        .foregroundColor(LT.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(LT.accent.opacity(0.15))
                        .cornerRadius(4)
                }

                Spacer()
            }

            if tracker.records.isEmpty {
                Text("No sessions recorded yet")
                    .font(LT.inter(12))
                    .foregroundColor(LT.textMuted)
                    .padding(.vertical, LT.space8)
            } else {
                ForEach(groupedRecords, id: \.key) { group in
                    Text(group.key)
                        .font(LT.mono(10, weight: .medium))
                        .foregroundColor(LT.textSecondary)
                        .padding(.top, LT.space4)

                    ForEach(group.records) { record in
                        HStack(spacing: LT.space8) {
                            Image(systemName: iconName(for: record.type))
                                .font(.system(size: 12))
                                .foregroundColor(iconColor(for: record.type))
                                .frame(width: 16)

                            Text(record.detail)
                                .font(LT.inter(12))
                                .foregroundColor(LT.textPrimary)
                                .lineLimit(1)

                            Spacer()

                            Text(relativeTime(record.timestamp))
                                .font(LT.mono(10))
                                .foregroundColor(LT.textMuted)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("Clear History") {
                        showClearConfirmation = true
                    }
                    .buttonStyle(.plain)
                    .font(LT.inter(11))
                    .foregroundColor(LT.textSecondary)
                    .alert("Clear Session History?", isPresented: $showClearConfirmation) {
                        Button("Clear", role: .destructive) {
                            tracker.clearHistory()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will remove all recorded session events.")
                    }
                }
                .padding(.top, LT.space4)
            }
        }
        .padding(.horizontal, LT.space12)
    }

    private func iconName(for type: SessionType) -> String {
        switch type {
        case .terminal: return "terminal.fill"
        case .desktop: return "desktopcomputer"
        case .fileTransfer: return "folder.fill"
        case .vnc: return "display"
        }
    }

    private func iconColor(for type: SessionType) -> Color {
        switch type {
        case .terminal: return LT.ok
        case .desktop: return LT.accent
        case .fileTransfer: return LT.warn
        case .vnc: return LT.accent
        }
    }

    private func relativeTime(_ date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/LabTetherAgent/Views/PopOut/PopOutSessionHistorySection.swift
git commit -m "feat: add PopOutSessionHistorySection with grouped timeline"
```

---

### Task 5: Create PopOutBandwidthSection

**Files:**
- Create: `Sources/LabTetherAgent/Views/PopOut/PopOutBandwidthSection.swift`

- [ ] **Step 1: Create the view**

```swift
import SwiftUI

/// Pop-out dashboard section showing cumulative bandwidth stats and a 7-day bar chart.
struct PopOutBandwidthSection: View {
    @ObservedObject var tracker: BandwidthTracker

    private var todayTotals: (rx: UInt64, tx: UInt64) {
        BandwidthPresentation.totalForPeriod(tracker.samples, days: 1)
    }

    private var thirtyDayTotals: (rx: UInt64, tx: UInt64) {
        BandwidthPresentation.totalForPeriod(tracker.samples, days: 30)
    }

    private var last7Days: [(label: String, total: UInt64)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let dailyMap = Dictionary(
            grouping: tracker.samples.filter {
                $0.date > today.addingTimeInterval(-7 * 24 * 3600)
            },
            by: { cal.startOfDay(for: $0.date) }
        )

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"

        return (0..<7).reversed().map { daysAgo in
            let day = cal.date(byAdding: .day, value: -daysAgo, to: today)!
            let samples = dailyMap[day] ?? []
            let total = samples.reduce(UInt64(0)) { $0 + $1.rxBytes + $1.txBytes }
            return (label: formatter.string(from: day), total: total)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LT.space8) {
            Text("BANDWIDTH")
                .font(LT.mono(10, weight: .medium))
                .foregroundColor(LT.textMuted)

            let hasData = tracker.currentSessionRX > 0 || tracker.currentSessionTX > 0 || !tracker.samples.isEmpty

            if !hasData {
                Text("Bandwidth data will appear after the agent runs for a while")
                    .font(LT.inter(12))
                    .foregroundColor(LT.textMuted)
                    .padding(.vertical, LT.space8)
            } else {
                // Current session
                HStack(spacing: LT.space16) {
                    Text("This Session")
                        .font(LT.inter(12))
                        .foregroundColor(LT.textSecondary)
                    Spacer()
                    bandwidthPair(rx: tracker.currentSessionRX, tx: tracker.currentSessionTX)
                }

                // Today
                let today = todayTotals
                if today.rx > 0 || today.tx > 0 {
                    HStack(spacing: LT.space16) {
                        Text("Today")
                            .font(LT.inter(12))
                            .foregroundColor(LT.textSecondary)
                        Spacer()
                        bandwidthPair(rx: today.rx, tx: today.tx)
                    }
                }

                // 7-day bar chart
                let days = last7Days
                let maxVal = days.map(\.total).max() ?? 0
                if maxVal > 0 {
                    VStack(spacing: LT.space4) {
                        HStack(alignment: .bottom, spacing: 3) {
                            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                                VStack(spacing: 2) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(LT.accent)
                                        .frame(
                                            width: 28,
                                            height: max(2, CGFloat(day.total) / CGFloat(maxVal) * 40)
                                        )
                                    Text(day.label)
                                        .font(LT.mono(8))
                                        .foregroundColor(LT.textMuted)
                                }
                            }
                        }
                        .frame(height: 56)
                    }
                    .padding(.vertical, LT.space4)
                }

                // 30-day total
                let total30 = thirtyDayTotals
                if total30.rx > 0 || total30.tx > 0 {
                    HStack(spacing: LT.space16) {
                        Text("Last 30 Days")
                            .font(LT.inter(11))
                            .foregroundColor(LT.textSecondary)
                        Spacer()
                        bandwidthPair(rx: total30.rx, tx: total30.tx, small: true)
                    }
                }
            }
        }
        .padding(.horizontal, LT.space12)
    }

    @ViewBuilder
    private func bandwidthPair(rx: UInt64, tx: UInt64, small: Bool = false) -> some View {
        let font = small ? LT.mono(11) : LT.mono(12)
        HStack(spacing: LT.space8) {
            HStack(spacing: 2) {
                Text("↓")
                    .foregroundColor(LT.ok)
                Text(BandwidthPresentation.formatBytes(rx))
                    .foregroundColor(LT.textPrimary)
            }
            .font(font)

            HStack(spacing: 2) {
                Text("↑")
                    .foregroundColor(LT.accent)
                Text(BandwidthPresentation.formatBytes(tx))
                    .foregroundColor(LT.textPrimary)
            }
            .font(font)
        }
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 3: Commit**

```bash
git add Sources/LabTetherAgent/Views/PopOut/PopOutBandwidthSection.swift
git commit -m "feat: add PopOutBandwidthSection with session stats and 7-day chart"
```

---

### Task 6: Wire trackers into AppState, AgentProcess, and PopOutView

**Files:**
- Modify: `Sources/LabTetherAgent/App/AppState.swift`
- Modify: `Sources/LabTetherAgent/Process/AgentProcess.swift`
- Modify: `Sources/LabTetherAgent/App/App.swift`
- Modify: `Sources/LabTetherAgent/Views/PopOut/PopOutView.swift`

- [ ] **Step 1: Make `appSupportDirectory` internal on AgentSettings**

In `AgentSettings.swift` (line 104), change `private var appSupportDirectory` to `var appSupportDirectory` (internal access — the default). This lets `AppState` access it for tracker file paths.

Then in `AppState.swift`, add a property:

```swift
let sessionHistory: SessionHistoryTracker
```

Initialize it in `init()` before creating `AgentProcess`:

```swift
sessionHistory = SessionHistoryTracker(
    filePath: settings.appSupportDirectory.appendingPathComponent("session-history.json").path
)
```

- [ ] **Step 2: Pass SessionHistoryTracker to AgentProcess**

In `AgentProcess.swift`:
1. Add `let sessionHistory: SessionHistoryTracker` property
2. Add it to the init signature: `init(status:, settings:, notifications:, logBuffer:, sessionHistory:)`
3. In `handleParsedLines`, after the existing `status.handleEvent(line.event)` call (around line 286), add:
   ```swift
   sessionHistory.handleEvent(line.event, timestamp: Date())
   ```

Update the `AgentProcess` creation in `AppState.init()` to pass `sessionHistory`.

- [ ] **Step 3: Add BandwidthTracker to AppState**

Add a property:

```swift
let bandwidthTracker: BandwidthTracker
```

Initialize it:

```swift
bandwidthTracker = BandwidthTracker(
    filePath: settings.appSupportDirectory.appendingPathComponent("bandwidth-history.json").path
)
```

Add a Combine subscriber on `apiClient.metrics.$snapshot` using the existing pattern of named `AnyCancellable?` properties:

```swift
private var bandwidthMetricsObserver: AnyCancellable?
```

In `init()`:

```swift
bandwidthMetricsObserver = apiClient.metrics.$snapshot
    .compactMap(\.current)
    .receive(on: RunLoop.main)
    .sink { [weak self] snapshot in
        self?.bandwidthTracker.accumulate(snapshot)
    }
```

Add `bandwidthTracker.resetSession()` inside the existing `runningObserver` sink (around line 58 of `AppState.swift`), in the `else` branch where `!running`:

```swift
// Existing code:
} else {
    apiClient.stop()
    bandwidthTracker.resetSession()  // <-- add this line
}
```

- [ ] **Step 4: Save trackers on app termination**

In `App.swift` `applicationWillTerminate`, add before the existing `forceKill()`:

```swift
AppState.shared.sessionHistory.save()
AppState.shared.bandwidthTracker.save()
```

- [ ] **Step 5: Add sections to PopOutView**

`PopOutView` receives decomposed parameters, not `AppState` directly. Add two new parameters to `PopOutView`:

```swift
let sessionHistory: SessionHistoryTracker
let bandwidthTracker: BandwidthTracker
```

Add the sections in the body:

```swift
// After PopOutSystemSection (around line 41)
PopOutBandwidthSection(tracker: bandwidthTracker)

// After RecentEventsSectionView (around line 49)
PopOutSessionHistorySection(tracker: sessionHistory)
```

Also update `PopOutWindowController.swift` — in its `show(appState:)` method, pass the new parameters through `PopOutRootView` and into `PopOutView`:

```swift
sessionHistory: appState.sessionHistory,
bandwidthTracker: appState.bandwidthTracker,
```

Check `PopOutRootView` (if it exists as a wrapper) and add the parameters there too. Follow the existing wiring chain.

- [ ] **Step 6: Build and run full test suite**

Run: `swift build 2>&1 | tail -10`
Then: `swift test 2>&1 | tail -10`
Expected: Build succeeds, all tests pass

- [ ] **Step 7: Commit**

```bash
git add Sources/LabTetherAgent/App/AppState.swift \
  Sources/LabTetherAgent/Process/AgentProcess.swift \
  Sources/LabTetherAgent/App/App.swift \
  Sources/LabTetherAgent/Views/PopOut/PopOutView.swift \
  Sources/LabTetherAgent/Views/PopOut/PopOutWindowController.swift \
  Sources/LabTetherAgent/Settings/AgentSettings.swift
git commit -m "feat: wire session history and bandwidth trackers into app lifecycle"
```

---

### Task 7: Final integration test

**Files:**
- All modified files

- [ ] **Step 1: Run full test suite**

Run: `swift test 2>&1 | tail -30`
Expected: All tests PASS

- [ ] **Step 2: Build release configuration**

Run: `swift build -c release 2>&1 | grep -v CLAUDE.md | grep -E "warning:|error:|Build complete"`
Expected: Build succeeds with no new warnings

- [ ] **Step 3: Commit if any remaining changes**

```bash
git status
```
