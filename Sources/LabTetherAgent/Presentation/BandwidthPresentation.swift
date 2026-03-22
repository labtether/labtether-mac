import Foundation

/// Formatting and aggregation helpers for bandwidth data.
///
/// All methods are pure functions with no external dependencies, making them
/// straightforward to unit-test and safe to call from any context.
enum BandwidthPresentation {

    // MARK: - Constants

    private static let tb: UInt64 = 1_099_511_627_776
    private static let gb: UInt64 = 1_073_741_824
    private static let mb: UInt64 = 1_048_576
    private static let kb: UInt64 = 1_024

    // MARK: - Public API

    /// Formats a byte count using binary units (1 KB = 1 024 bytes).
    ///
    /// Amounts are displayed with one decimal place for all multi-byte units:
    /// - `0` → `"0 B"`
    /// - `512` → `"512 B"`
    /// - `1 536` → `"1.5 KB"`
    /// - `1 572 864` → `"1.5 MB"`
    /// - `1 610 612 736` → `"1.5 GB"`
    ///
    /// - Parameter bytes: The raw byte count to format.
    /// - Returns: A human-readable string such as `"1.5 GB"`.
    static func formatBytes(_ bytes: UInt64) -> String {
        switch bytes {
        case tb...:
            return String(format: "%.1f TB", Double(bytes) / Double(tb))
        case gb...:
            return String(format: "%.1f GB", Double(bytes) / Double(gb))
        case mb...:
            return String(format: "%.1f MB", Double(bytes) / Double(mb))
        case kb...:
            return String(format: "%.1f KB", Double(bytes) / Double(kb))
        default:
            return "\(bytes) B"
        }
    }

    /// Aggregates hourly ``BandwidthSample`` values into per-calendar-day totals.
    ///
    /// Samples are grouped by `Calendar.current.startOfDay(for:)` and the
    /// `rxBytes` and `txBytes` fields are summed within each group.
    ///
    /// - Parameter samples: Hourly samples in any order.
    /// - Returns: An array of `(date, rx, tx)` tuples sorted in ascending
    ///   date order, where `date` is the midnight boundary for each day.
    static func dailyTotals(
        from samples: [BandwidthSample]
    ) -> [(date: Date, rx: UInt64, tx: UInt64)] {
        let calendar = Calendar.current

        // Group samples by their calendar-day boundary.
        var byDay: [Date: (rx: UInt64, tx: UInt64)] = [:]
        for sample in samples {
            let day = calendar.startOfDay(for: sample.date)
            let existing = byDay[day] ?? (rx: 0, tx: 0)
            byDay[day] = (
                rx: existing.rx + sample.rxBytes,
                tx: existing.tx + sample.txBytes
            )
        }

        return byDay
            .map { (date: $0.key, rx: $0.value.rx, tx: $0.value.tx) }
            .sorted { $0.date < $1.date }
    }

    /// Sums all samples whose `date` falls within the last `days` calendar days.
    ///
    /// The cut-off is computed as `Date() - days * 86 400 seconds`.
    /// Samples exactly at the boundary are excluded (strictly greater-than).
    ///
    /// - Parameters:
    ///   - samples: The full set of hourly samples to filter.
    ///   - days: The number of days to look back from now.
    /// - Returns: A tuple of `(rx, tx)` byte totals for the requested period.
    static func totalForPeriod(
        _ samples: [BandwidthSample],
        days: Int
    ) -> (rx: UInt64, tx: UInt64) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return samples
            .filter { $0.date > cutoff }
            .reduce(into: (rx: UInt64(0), tx: UInt64(0))) { acc, sample in
                acc.rx += sample.rxBytes
                acc.tx += sample.txBytes
            }
    }
}
