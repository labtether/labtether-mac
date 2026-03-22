import XCTest
@testable import LabTetherAgent

final class BandwidthPresentationTests: XCTestCase {

    // MARK: - formatBytes

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

    // MARK: - dailyTotals

    func testDailyTotalsAggregatesByCalendarDay() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        // Two samples on yesterday, two samples on today.
        let samples: [BandwidthSample] = [
            BandwidthSample(date: yesterday.addingTimeInterval(3_600), rxBytes: 100, txBytes: 200),
            BandwidthSample(date: yesterday.addingTimeInterval(7_200), rxBytes: 50,  txBytes: 80),
            BandwidthSample(date: today.addingTimeInterval(3_600),     rxBytes: 300, txBytes: 400),
            BandwidthSample(date: today.addingTimeInterval(7_200),     rxBytes: 25,  txBytes: 75),
        ]

        let totals = BandwidthPresentation.dailyTotals(from: samples)

        XCTAssertEqual(totals.count, 2)

        // Sorted ascending: yesterday first.
        XCTAssertEqual(totals[0].date, yesterday)
        XCTAssertEqual(totals[0].rx, 150)
        XCTAssertEqual(totals[0].tx, 280)

        XCTAssertEqual(totals[1].date, today)
        XCTAssertEqual(totals[1].rx, 325)
        XCTAssertEqual(totals[1].tx, 475)
    }

    // MARK: - totalForPeriod

    func testTotalForPeriodSumsCorrectDays() {
        let now = Date()
        // Sample from 10 days ago — outside both 7-day and 30-day windows... wait, 30-day includes it.
        // Let's place one clearly outside 30 days, one at 10 days (inside 30, outside 7), one at 2 days (inside both).
        let tenDaysAgo  = now.addingTimeInterval(-10 * 86_400)
        let twoDaysAgo  = now.addingTimeInterval(-2  * 86_400)
        let justNow     = now.addingTimeInterval(-60)

        let samples: [BandwidthSample] = [
            BandwidthSample(date: tenDaysAgo, rxBytes: 1_000, txBytes: 2_000),
            BandwidthSample(date: twoDaysAgo, rxBytes: 500,   txBytes: 800),
            BandwidthSample(date: justNow,    rxBytes: 200,   txBytes: 300),
        ]

        let sevenDay = BandwidthPresentation.totalForPeriod(samples, days: 7)
        XCTAssertEqual(sevenDay.rx, 700)   // twoDaysAgo + justNow
        XCTAssertEqual(sevenDay.tx, 1_100)

        let thirtyDay = BandwidthPresentation.totalForPeriod(samples, days: 30)
        XCTAssertEqual(thirtyDay.rx, 1_700)  // all three
        XCTAssertEqual(thirtyDay.tx, 3_100)
    }
}
