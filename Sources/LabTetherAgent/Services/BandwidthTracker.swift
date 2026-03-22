import Foundation

// MARK: - BandwidthTracker

/// Accumulates per-hour bandwidth from `MetricsSnapshot` polls and persists the
/// history to disk as a JSON file.
///
/// Call `accumulate(_:)` on every metrics poll. The tracker computes deltas from
/// the reported byte-rate × elapsed time and stores them in hourly buckets.
/// When the hour rolls over the completed bucket is flushed to the `samples`
/// array and persisted.
///
/// **Gap suppression:** if the interval between two consecutive polls exceeds
/// `gapThreshold` (default 90 s) the delta is discarded to avoid counting
/// periods where the agent was paused or the machine was sleeping.
@MainActor
final class BandwidthTracker: ObservableObject {

    // MARK: - Published State

    /// Total receive bytes accumulated since the last `resetSession()` call.
    @Published private(set) var currentSessionRX: UInt64 = 0

    /// Total transmit bytes accumulated since the last `resetSession()` call.
    @Published private(set) var currentSessionTX: UInt64 = 0

    /// Historical hourly samples, sorted chronologically, loaded from disk on init.
    @Published private(set) var samples: [BandwidthSample] = []

    // MARK: - Configuration

    private let filePath: String
    private let maxSamples: Int
    private let maxAgeDays: Int
    private let gapThreshold: TimeInterval

    // MARK: - In-progress Accumulator State

    /// Timestamp of the most recently processed snapshot.
    private var lastSampleTime: Date?

    /// The calendar hour bucket currently being accumulated.
    private var currentHourStart: Date?

    /// Bytes accumulated into the current (incomplete) hour bucket.
    private var hourlyRX: UInt64 = 0
    private var hourlyTX: UInt64 = 0

    // MARK: - Init

    /// Creates a bandwidth tracker backed by the given file path.
    ///
    /// - Parameters:
    ///   - filePath: Absolute path to the JSON persistence file.
    ///   - maxSamples: Maximum number of hourly samples to retain (default 720 = 30 days).
    ///   - maxAgeDays: Samples older than this many days are pruned (default 30).
    ///   - gapThreshold: Maximum acceptable elapsed time between consecutive polls
    ///                   before the delta is discarded (default 90 s).
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

    // MARK: - Public API

    /// Incorporates a new metrics snapshot into the running bandwidth totals.
    ///
    /// The first call after init (or after `resetSession()`) serves as a baseline
    /// and does not produce any byte accumulation — it only anchors the clock for
    /// the next call. Subsequent calls accumulate `rate × elapsed` bytes.
    ///
    /// - Parameter snapshot: The latest metrics snapshot from the agent poll.
    func accumulate(_ snapshot: MetricsSnapshot) {
        guard let collectedAt = snapshot.collectedAt else { return }

        guard let last = lastSampleTime else {
            // First sample — anchor the clock, initialise the hour bucket.
            lastSampleTime = collectedAt
            currentHourStart = BandwidthTracker.hourStart(for: collectedAt)
            return
        }

        let elapsed = collectedAt.timeIntervalSince(last)

        // Only accumulate when elapsed is positive and within the gap threshold.
        if elapsed > 0, elapsed < gapThreshold {
            let rx = max(0, snapshot.netRXBytesPerSec)
            let tx = max(0, snapshot.netTXBytesPerSec)
            let rxDelta = UInt64(rx * elapsed)
            let txDelta = UInt64(tx * elapsed)

            currentSessionRX += rxDelta
            currentSessionTX += txDelta
            hourlyRX += rxDelta
            hourlyTX += txDelta
        }

        // Detect hour rollover.
        let snapshotHour = BandwidthTracker.hourStart(for: collectedAt)
        if let bucketHour = currentHourStart, snapshotHour > bucketHour {
            // Flush the completed bucket.
            flushHourlyBucket(hour: bucketHour)
            persist()
            // Start a fresh bucket for the new hour.
            currentHourStart = snapshotHour
            hourlyRX = 0
            hourlyTX = 0
        }

        lastSampleTime = collectedAt
    }

    /// Resets the current session counters and in-progress hourly accumulator.
    ///
    /// Any in-progress hourly data is flushed to `samples` before the reset so
    /// that data is not permanently lost.
    func resetSession() {
        if let hour = currentHourStart, hourlyRX > 0 || hourlyTX > 0 {
            flushHourlyBucket(hour: hour)
            persist()
        }
        currentSessionRX = 0
        currentSessionTX = 0
        lastSampleTime = nil
        currentHourStart = nil
        hourlyRX = 0
        hourlyTX = 0
    }

    /// Flushes any in-progress hourly bucket, prunes old data, and writes to disk.
    ///
    /// After flushing the hourly counters are reset to zero to prevent double-flush
    /// on the next rollover.
    func save() {
        if let hour = currentHourStart, hourlyRX > 0 || hourlyTX > 0 {
            flushHourlyBucket(hour: hour)
            // Reset to prevent double-flush on next hour rollover.
            hourlyRX = 0
            hourlyTX = 0
        }
        prune()
        persist()
    }

    /// Removes samples that exceed the age or count limits.
    func prune() {
        let cutoff = Date().addingTimeInterval(-TimeInterval(maxAgeDays) * 24 * 3600)
        samples.removeAll { $0.date < cutoff }
        if samples.count > maxSamples {
            samples = Array(samples.suffix(maxSamples))
        }
    }

    /// Test-only entry point for inserting pre-built samples directly into `samples`.
    ///
    /// This bypasses the accumulate pathway so tests can seed arbitrary historical data.
    func testInsertSample(_ sample: BandwidthSample) {
        appendOrMergeSample(sample)
    }

    // MARK: - Internal Helpers (internal for tests)

    /// Truncates `date` to the start of its calendar hour (UTC).
    static func hourStart(for date: Date) -> Date {
        let secs = date.timeIntervalSince1970
        let hourSecs: TimeInterval = 3600
        return Date(timeIntervalSince1970: floor(secs / hourSecs) * hourSecs)
    }

    // MARK: - Private

    /// Reads the persistence file and populates `samples`.
    private func load() {
        guard let data = FileManager.default.contents(atPath: filePath) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([BandwidthSample].self, from: data) else { return }
        samples = decoded
        prune()
    }

    /// Writes `samples` to the persistence file as JSON.
    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(samples) else { return }
        FileManager.default.createFile(atPath: filePath, contents: data)
    }

    /// Flushes the given hour bucket into `samples` without resetting the counters.
    private func flushHourlyBucket(hour: Date) {
        let sample = BandwidthSample(date: hour, rxBytes: hourlyRX, txBytes: hourlyTX)
        appendOrMergeSample(sample)
    }

    /// Merges `sample` into an existing bucket for the same hour or appends a new one,
    /// keeping `samples` sorted chronologically.
    private func appendOrMergeSample(_ sample: BandwidthSample) {
        if let index = samples.firstIndex(where: { $0.date == sample.date }) {
            samples[index].rxBytes += sample.rxBytes
            samples[index].txBytes += sample.txBytes
        } else {
            samples.append(sample)
            samples.sort { $0.date < $1.date }
        }
    }
}
