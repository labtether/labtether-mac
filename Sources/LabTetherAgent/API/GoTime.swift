import Foundation

/// Reads the times the Go agent writes in `/agent/status`.
///
/// Go's `time.Time` JSON is RFC 3339: `YYYY-MM-DDTHH:MM:SS`, then an optional
/// fraction of one to nine digits (trailing zeros dropped, none when zero),
/// then `Z` or a `+HH:MM` / `-HH:MM` offset. Go's zero time is
/// `0001-01-01T00:00:00Z`.
///
/// This is a hand parser over that fixed layout. It uses only integer
/// arithmetic and `Date(timeIntervalSinceReferenceDate:)`, so its result does
/// not depend on the macOS version. `JSONDecoder`'s `.iso8601` strategy is
/// built on the system's ISO 8601 formatter, whose handling of fractional
/// seconds has not been checked on macOS 13 to 26; one unreadable
/// `started_at` used to fail the whole status read.
enum GoTime {
    /// The decoder strategy for status bodies. An unreadable string throws
    /// `DecodingError.dataCorrupted`.
    static let decodingStrategy: JSONDecoder.DateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let date = parse(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a Go RFC 3339 time")
        }
        return date
    }

    /// The instant `text` names, or nil when it is not in Go's layout.
    static func parse(_ text: String) -> Date? {
        let b = Array(text.utf8)
        // Shortest: "0001-01-01T00:00:00Z" (20 bytes).
        guard b.count >= 20,
              b[4] == UInt8(ascii: "-"), b[7] == UInt8(ascii: "-"), b[10] == UInt8(ascii: "T"),
              b[13] == UInt8(ascii: ":"), b[16] == UInt8(ascii: ":"),
              let year = digits(b, 0, 4), let month = digits(b, 5, 2), let day = digits(b, 8, 2),
              let hour = digits(b, 11, 2), let minute = digits(b, 14, 2), let second = digits(b, 17, 2),
              (1...12).contains(month), day >= 1, day <= daysIn(month: month, year: year),
              hour < 24, minute < 60, second < 60
        else { return nil }

        var i = 19
        var nanos = 0
        if b[i] == UInt8(ascii: ".") {
            i += 1
            let start = i
            while i < b.count, let d = digit(b[i]) {
                nanos = nanos * 10 + d
                i += 1
            }
            let count = i - start
            guard (1...9).contains(count) else { return nil }
            for _ in count..<9 { nanos *= 10 }
        }

        guard i < b.count else { return nil }
        var offsetSeconds = 0
        switch b[i] {
        case UInt8(ascii: "Z"):
            i += 1
        case UInt8(ascii: "+"), UInt8(ascii: "-"):
            guard b.count - i == 6, b[i + 3] == UInt8(ascii: ":"),
                  let oh = digits(b, i + 1, 2), let om = digits(b, i + 4, 2), oh < 24, om < 60
            else { return nil }
            offsetSeconds = (oh * 3600 + om * 60) * (b[i] == UInt8(ascii: "-") ? -1 : 1)
            i += 6
        default:
            return nil
        }
        guard i == b.count else { return nil }

        let wallSeconds = daysFromUnixEpoch(year: year, month: month, day: day) * 86_400
            + hour * 3600 + minute * 60 + second
        let unixSeconds = wallSeconds - offsetSeconds
        // 978_307_200 s from 1970-01-01 to 2001-01-01, Date's reference.
        // Whole seconds and the fraction are added once, so the only rounding
        // is Date's own Double.
        return Date(timeIntervalSinceReferenceDate: Double(unixSeconds - 978_307_200) + Double(nanos) / 1e9)
    }

    private static func digit(_ byte: UInt8) -> Int? {
        byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") ? Int(byte - UInt8(ascii: "0")) : nil
    }

    private static func digits(_ b: [UInt8], _ start: Int, _ count: Int) -> Int? {
        var value = 0
        for k in start..<(start + count) {
            guard let d = digit(b[k]) else { return nil }
            value = value * 10 + d
        }
        return value
    }

    private static func isLeap(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    private static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: return isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// Days from 1970-01-01 in the proleptic Gregorian calendar, as Go counts
    /// them (H. Hinnant's `days_from_civil`).
    private static func daysFromUnixEpoch(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
}
