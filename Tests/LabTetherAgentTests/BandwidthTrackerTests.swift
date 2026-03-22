import XCTest
@testable import LabTetherAgent

@MainActor
final class BandwidthTrackerTests: XCTestCase {

    // MARK: - Helpers

    private var tempDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BandwidthTrackerTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeTempFilePath() -> String {
        let dir = tempDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("bandwidth.json").path
    }

    private func makeSnapshot(
        rx: Double,
        tx: Double,
        collectedAt: Date?
    ) -> MetricsSnapshot {
        MetricsSnapshot(
            cpuPercent: 0,
            memoryPercent: 0,
            diskPercent: 0,
            netRXBytesPerSec: rx,
            netTXBytesPerSec: tx,
            tempCelsius: nil,
            collectedAt: collectedAt
        )
    }

    // MARK: - Tests

    /// Two snapshots 5 seconds apart at 100/50 bytes/sec produce 500/250 bytes.
    func testAccumulateAddsBytes() {
        let tracker = BandwidthTracker(filePath: makeTempFilePath())
        let base = Date(timeIntervalSince1970: 1_741_420_800)

        // First sample — sets the baseline only.
        tracker.accumulate(makeSnapshot(rx: 100, tx: 50, collectedAt: base))
        XCTAssertEqual(tracker.currentSessionRX, 0, "Baseline sample should not add bytes")
        XCTAssertEqual(tracker.currentSessionTX, 0)

        // Second sample — 5 s later at 100/50 bytes/s = 500/250 bytes.
        tracker.accumulate(makeSnapshot(rx: 100, tx: 50, collectedAt: base.addingTimeInterval(5)))
        XCTAssertEqual(tracker.currentSessionRX, 500)
        XCTAssertEqual(tracker.currentSessionTX, 250)
    }

    /// A snapshot whose collectedAt is nil must be silently skipped.
    func testAccumulateSkipsNilCollectedAt() {
        let tracker = BandwidthTracker(filePath: makeTempFilePath())
        let base = Date(timeIntervalSince1970: 1_741_420_800)

        tracker.accumulate(makeSnapshot(rx: 100, tx: 50, collectedAt: base))
        tracker.accumulate(makeSnapshot(rx: 100, tx: 50, collectedAt: nil))

        XCTAssertEqual(tracker.currentSessionRX, 0)
        XCTAssertEqual(tracker.currentSessionTX, 0)
    }

    /// A gap of 100 seconds exceeds the 90 s threshold and must not accumulate bytes.
    func testAccumulateSkipsLargeGaps() {
        let tracker = BandwidthTracker(filePath: makeTempFilePath())
        let base = Date(timeIntervalSince1970: 1_741_420_800)

        tracker.accumulate(makeSnapshot(rx: 100, tx: 50, collectedAt: base))
        tracker.accumulate(makeSnapshot(rx: 100, tx: 50, collectedAt: base.addingTimeInterval(100)))

        XCTAssertEqual(tracker.currentSessionRX, 0)
        XCTAssertEqual(tracker.currentSessionTX, 0)
    }

    /// Negative rate values must be clamped to zero — no bytes should be subtracted.
    func testAccumulateClampsNegativeRates() {
        let tracker = BandwidthTracker(filePath: makeTempFilePath())
        let base = Date(timeIntervalSince1970: 1_741_420_800)

        tracker.accumulate(makeSnapshot(rx: -50, tx: -100, collectedAt: base))
        tracker.accumulate(makeSnapshot(rx: -50, tx: -100, collectedAt: base.addingTimeInterval(5)))

        XCTAssertEqual(tracker.currentSessionRX, 0)
        XCTAssertEqual(tracker.currentSessionTX, 0)
    }

    /// After resetSession the session counters are zero.
    func testResetSessionZerosCurrentCounters() {
        let tracker = BandwidthTracker(filePath: makeTempFilePath())
        let base = Date(timeIntervalSince1970: 1_741_420_800)

        tracker.accumulate(makeSnapshot(rx: 100, tx: 50, collectedAt: base))
        tracker.accumulate(makeSnapshot(rx: 100, tx: 50, collectedAt: base.addingTimeInterval(5)))
        XCTAssertGreaterThan(tracker.currentSessionRX, 0)

        tracker.resetSession()

        XCTAssertEqual(tracker.currentSessionRX, 0)
        XCTAssertEqual(tracker.currentSessionTX, 0)
    }

    /// Samples spanning two calendar hours must produce at least one persisted hourly sample.
    func testHourlyRolloverCreatesSample() {
        let tracker = BandwidthTracker(filePath: makeTempFilePath())
        // Use a recent date (yesterday) aligned to XX:59:55 so +10 s crosses the hour boundary.
        let yesterday = Date().addingTimeInterval(-24 * 3600)
        let cal = Calendar(identifier: .gregorian)
        var comps = cal.dateComponents([.year, .month, .day, .hour], from: yesterday)
        comps.minute = 59
        comps.second = 55
        let beforeRollover = cal.date(from: comps)!
        let afterRollover = beforeRollover.addingTimeInterval(10)

        tracker.accumulate(makeSnapshot(rx: 1000, tx: 500, collectedAt: beforeRollover))
        tracker.accumulate(makeSnapshot(rx: 1000, tx: 500, collectedAt: afterRollover))

        XCTAssertFalse(tracker.samples.isEmpty, "Expected at least one persisted hourly sample after hour rollover")
    }

    /// Samples written to disk must survive a round-trip through save and load.
    func testSaveAndLoadRoundTrip() {
        let path = makeTempFilePath()
        let tracker = BandwidthTracker(filePath: path)

        // Use a recent date (yesterday) so pruning does not remove the sample.
        let yesterday = Date().addingTimeInterval(-24 * 3600)
        // Align to XX:59:55 so adding 10 s crosses into the next hour.
        let cal = Calendar(identifier: .gregorian)
        var comps = cal.dateComponents([.year, .month, .day, .hour], from: yesterday)
        comps.minute = 59
        comps.second = 55
        let beforeRollover = cal.date(from: comps)!
        let afterRollover = beforeRollover.addingTimeInterval(10)

        tracker.accumulate(makeSnapshot(rx: 200, tx: 100, collectedAt: beforeRollover))
        tracker.accumulate(makeSnapshot(rx: 200, tx: 100, collectedAt: afterRollover))

        // Force a save which also flushes in-progress bucket.
        tracker.save()

        // A fresh tracker reading the same file should restore the samples.
        let tracker2 = BandwidthTracker(filePath: path)
        XCTAssertFalse(tracker2.samples.isEmpty, "Loaded tracker must contain saved samples")
        XCTAssertEqual(tracker2.samples.count, tracker.samples.count)
    }

    /// Samples older than maxAgeDays must be removed by prune.
    func testPruneRemovesSamplesOlderThan30Days() {
        let tracker = BandwidthTracker(filePath: makeTempFilePath())
        let now = Date()
        let old = now.addingTimeInterval(-31 * 24 * 3600) // 31 days ago

        let oldSample = BandwidthSample(
            date: BandwidthTracker.hourStart(for: old),
            rxBytes: 999,
            txBytes: 888
        )
        let recentSample = BandwidthSample(
            date: BandwidthTracker.hourStart(for: now.addingTimeInterval(-1 * 3600)),
            rxBytes: 111,
            txBytes: 222
        )

        tracker.testInsertSample(oldSample)
        tracker.testInsertSample(recentSample)

        XCTAssertEqual(tracker.samples.count, 2, "Pre-prune should have both samples")

        tracker.save() // save calls prune internally

        XCTAssertEqual(tracker.samples.count, 1, "Post-prune should retain only recent sample")
        XCTAssertEqual(tracker.samples.first?.rxBytes, recentSample.rxBytes)
    }
}
