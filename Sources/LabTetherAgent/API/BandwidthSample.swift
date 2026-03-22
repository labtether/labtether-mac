import Foundation

/// A single hourly bandwidth observation recorded by the local agent.
///
/// Samples are stored per-hour and are aggregated into daily or period totals
/// by ``BandwidthPresentation``.
struct BandwidthSample: Codable, Identifiable, Equatable {
    /// The timestamp of this sample; also used as the stable identifier.
    let date: Date

    /// Bytes received during the sample interval.
    var rxBytes: UInt64

    /// Bytes transmitted during the sample interval.
    var txBytes: UInt64

    var id: Date { date }
}
