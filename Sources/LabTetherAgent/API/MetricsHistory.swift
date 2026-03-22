import Foundation

struct SparklineSeries: Equatable {
    let normalizedValues: [Double]

    init(values: [Double] = []) {
        guard !values.isEmpty else {
            normalizedValues = []
            return
        }
        let finiteValues = values.map { $0.isFinite ? $0 : 0 }
        let maxValue = finiteValues.max() ?? 0
        let minValue = finiteValues.min() ?? 0
        let range = max(maxValue - minValue, 1)
        if range == 1 && maxValue == minValue {
            normalizedValues = Array(repeating: 0.5, count: finiteValues.count)
            return
        }
        normalizedValues = finiteValues.map { ($0 - minValue) / range }
    }
}

// MARK: - MetricsHistory

/// A fixed-capacity ring buffer of `MetricsSnapshot` samples used to back sparkline charts.
///
/// Accumulates up to 60 samples (approximately 5 minutes at the 5 s fast-poll interval).
/// Older samples are dropped automatically when the buffer is full.
///
/// The `cpuHistory`, `memHistory`, and `diskHistory` arrays are cached as stored
/// properties and recomputed only on `append(_:)`, avoiding redundant O(n) map passes
/// on every SwiftUI view-body evaluation.
struct MetricsHistory: Equatable {
    private let maxCount = 60  // 5 minutes at 5s polling
    private var buffer: [MetricsSnapshot?]
    private var headIndex = 0
    private var count = 0

    init() {
        buffer = Array(repeating: nil, count: maxCount)
    }

    /// Cached CPU percentage history for sparkline rendering.
    private(set) var cpuHistory: [Double] = []

    /// Cached memory percentage history for sparkline rendering.
    private(set) var memHistory: [Double] = []

    /// Cached disk percentage history for sparkline rendering.
    private(set) var diskHistory: [Double] = []

    /// Cached normalized sparkline series for pop-out metric cards.
    private(set) var cpuSparkline = SparklineSeries()
    private(set) var memSparkline = SparklineSeries()
    private(set) var diskSparkline = SparklineSeries()

    /// Appends a new sample, evicting the oldest when the buffer is full,
    /// and rebuilds the cached history arrays in one pass.
    mutating func append(_ snapshot: MetricsSnapshot) {
        if count < maxCount {
            buffer[(headIndex + count) % maxCount] = snapshot
            count += 1
        } else {
            buffer[headIndex] = snapshot
            headIndex = (headIndex + 1) % maxCount
        }
        rebuildHistories()
        LTPerformanceSignposts.emitMetricsHistoryAppend(retainedSamples: count)
    }

    mutating func clear() {
        buffer = Array(repeating: nil, count: maxCount)
        headIndex = 0
        count = 0
        cpuHistory = []
        memHistory = []
        diskHistory = []
        cpuSparkline = SparklineSeries()
        memSparkline = SparklineSeries()
        diskSparkline = SparklineSeries()
    }

    /// All retained samples in chronological order.
    var samples: [MetricsSnapshot] {
        var ordered: [MetricsSnapshot] = []
        ordered.reserveCapacity(count)
        for offset in 0..<count {
            if let sample = buffer[(headIndex + offset) % maxCount] {
                ordered.append(sample)
            }
        }
        return ordered
    }

    private mutating func rebuildHistories() {
        var cpu: [Double] = []
        var mem: [Double] = []
        var disk: [Double] = []
        cpu.reserveCapacity(count)
        mem.reserveCapacity(count)
        disk.reserveCapacity(count)

        for sample in samples {
            cpu.append(sample.cpuPercent)
            mem.append(sample.memoryPercent)
            disk.append(sample.diskPercent)
        }

        cpuHistory = cpu
        memHistory = mem
        diskHistory = disk
        cpuSparkline = SparklineSeries(values: cpu)
        memSparkline = SparklineSeries(values: mem)
        diskSparkline = SparklineSeries(values: disk)
    }
}
