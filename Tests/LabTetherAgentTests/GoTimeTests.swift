import XCTest
@testable import LabTetherAgent

/// Risk: the Go agent writes RFC 3339 times with up to nine fraction digits,
/// an offset or no fraction. The system `.iso8601` strategy is unchecked for
/// fractions on macOS 13 to 26, and one unreadable `started_at` failed the
/// whole status read. These go through the app's own decoder.
final class GoTimeTests: XCTestCase {
    private func startedAt(_ text: String) throws -> Date? {
        let body = try StatusFixtures.variant("connected") { $0["started_at"] = text }
        return try LocalAPIClient.decodeStatus(body).startedAt
    }

    private func assertInstant(_ date: Date?, _ unix: Double, _ label: String, line: UInt = #line) {
        guard let date else { return XCTFail("\(label): no date", line: line) }
        // Date holds about 0.1 µs at this range; 1 µs still tells a dropped
        // or cut fraction (0.418236512 against 0.418) apart.
        XCTAssertEqual(date.timeIntervalSince1970, unix, accuracy: 1e-6, label, line: line)
    }

    func testFixtureTimesDecodeToTheirInstants() throws {
        let status = try LocalAPIClient.decodeStatus(StatusFixtures.data("alerts-with-temperature"))
        assertInstant(status.startedAt, 1_794_641_194.418236512, "started_at, 9 digits")
        assertInstant(status.metrics.collectedAt, 1_794_649_262.907113845, "collected_at, 9 digits")
        assertInstant(status.alerts[0].timestamp, 1_794_647_560, "alert, no fraction")
        assertInstant(status.alerts[1].timestamp, 1_794_646_503.512, "alert, 3 digits")

        let down = try LocalAPIClient.decodeStatus(StatusFixtures.data("auth-failed-token-rejected"))
        assertInstant(down.disconnectedAt, 1_794_649_131.260417093, "disconnected_at")

        let zero = try LocalAPIClient.decodeStatus(StatusFixtures.data("minimal-optional-fields-absent"))
        XCTAssertEqual(zero.startedAt?.timeIntervalSince1970, -62_135_596_800, "Go zero time")
    }

    func testEveryGoTimeFormDecodes() throws {
        let unix = 1_794_641_194.0
        let forms: [(String, Double)] = [
            ("2026-11-14T07:26:34Z", unix),
            ("2026-11-14T07:26:34.5Z", unix + 0.5),
            ("2026-11-14T07:26:34.41Z", unix + 0.41),
            ("2026-11-14T07:26:34.418236512Z", unix + 0.418236512),
            ("2026-11-14T07:26:34.000000001Z", unix + 0.000000001),
            // The host's local zone, as disconnected_at after a failed connect.
            ("2026-11-14T17:26:34.418236512+10:00", unix + 0.418236512),
            ("2026-11-14T01:56:34.418236512-05:30", unix + 0.418236512),
            ("2026-11-14T07:26:34+00:00", unix),
            ("2024-02-29T23:59:59Z", 1_709_251_199),
        ]
        for (text, expected) in forms {
            assertInstant(try startedAt(text), expected, text)
        }
    }

    func testTextOutsideGoLayoutIsRefused() {
        let bad = [
            "", "2026-11-14", "2026-11-14T07:26:34", "2026-11-14 07:26:34Z",
            "2026-11-14T07:26:34.Z", "2026-11-14T07:26:34.4182365120Z",
            "2026-13-14T07:26:34Z", "2026-02-29T07:26:34Z", "2026-11-31T07:26:34Z",
            "2026-11-14T24:00:00Z", "2026-11-14T07:60:34Z", "2026-11-14T07:26:60Z",
            "2026-11-14T07:26:34+1000", "2026-11-14T07:26:34+10:00:00", "2026-11-14T07:26:34Zjunk",
            "２026-11-14T07:26:34Z",
        ]
        for text in bad {
            XCTAssertNil(GoTime.parse(text), text)
        }
    }

    /// Dates are display-only: an unreadable one becomes nil and the
    /// connection state, metrics and alerts still show.
    func testAnUnreadableDateDoesNotLoseTheStatus() throws {
        let body = try StatusFixtures.variant("alerts-with-temperature") { body in
            body["started_at"] = "Saturday"
            var metrics = body["metrics"] as? [String: Any] ?? [:]
            metrics["collected_at"] = "2026-11-14T09:41:02.9071138451Z"
            body["metrics"] = metrics
            var alerts = body["alerts"] as? [[String: Any]] ?? []
            alerts[0]["timestamp"] = "yesterday"
            body["alerts"] = alerts
        }
        let status = try LocalAPIClient.decodeStatus(body)
        XCTAssertNil(status.startedAt)
        XCTAssertNil(status.metrics.collectedAt)
        XCTAssertNil(status.alerts[0].timestamp)
        assertInstant(status.alerts[1].timestamp, 1_794_646_503.512, "the readable alert time stays")
        XCTAssertEqual(status.connectionState, "connected")
        XCTAssertEqual(status.metrics.cpuPercent, 12.5)
        XCTAssertEqual(status.alerts.count, 2)
    }

    /// A date that is not a string breaks the contract's types and still fails.
    func testADateOfTheWrongTypeFails() throws {
        let body = try StatusFixtures.variant("connected") { $0["started_at"] = 1_794_641_194 }
        XCTAssertThrowsError(try LocalAPIClient.decodeStatus(body))
    }
}
