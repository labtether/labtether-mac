import Foundation
import Combine
import os

// MARK: - Data model

/// The category of a remote session that was recorded in session history.
enum SessionType: String, Codable, CaseIterable {
    case terminal
    case desktop
    case fileTransfer
    case vnc
}

/// An immutable record of a single remote session event.
struct SessionRecord: Codable, Identifiable, Equatable {
    /// Stable identifier for this record.
    let id: UUID
    /// The category of the session.
    let type: SessionType
    /// Human-readable detail string extracted from the agent log event.
    let detail: String
    /// Wall-clock time at which the event was observed.
    let timestamp: Date
}

// MARK: - SessionHistoryTracker

/// Tracks remote session events observed in agent logs and persists them to a JSON file.
///
/// Records are appended via ``handleEvent(_:timestamp:)``, which filters only session-type
/// ``AgentEvent`` values. A debounced save (5-second window) is scheduled automatically
/// after each mutation. Call ``save()`` directly to flush immediately.
///
/// On initialisation the persisted file (if any) is loaded and pruned according to
/// ``maxAgeDays`` and ``maxRecords``.
@MainActor
final class SessionHistoryTracker: ObservableObject {

    // MARK: - Published state

    /// The current in-memory list of session records, newest last.
    @Published private(set) var records: [SessionRecord] = []

    // MARK: - Configuration

    /// Absolute path to the JSON persistence file.
    private let filePath: String

    /// Maximum number of records to retain (oldest are dropped when exceeded).
    private let maxRecords: Int

    /// Records older than this many days are removed during pruning.
    private let maxAgeDays: Int

    // MARK: - Private state

    private var saveTimer: AnyCancellable?

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.labtether.agent",
        category: "SessionHistoryTracker"
    )

    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Initialisation

    /// Creates a tracker, loading any existing records from `filePath`.
    ///
    /// - Parameters:
    ///   - filePath: Absolute path to the JSON persistence file. The directory is
    ///     created if it does not already exist.
    ///   - maxRecords: Upper bound on the number of retained records. Default `500`.
    ///   - maxAgeDays: Records older than this many days are pruned. Default `30`.
    init(filePath: String, maxRecords: Int = 500, maxAgeDays: Int = 30) {
        self.filePath = filePath
        self.maxRecords = maxRecords
        self.maxAgeDays = maxAgeDays
        load()
    }

    // MARK: - Public API

    /// Inspects `event` and, if it represents a session activity, appends a ``SessionRecord``.
    ///
    /// Non-session events (`.connected`, `.heartbeat`, `.info`, etc.) are silently ignored.
    /// After appending a record a debounced save is automatically scheduled.
    ///
    /// - Parameters:
    ///   - event: The parsed agent event to evaluate.
    ///   - timestamp: The wall-clock time to assign to the record.
    func handleEvent(_ event: AgentEvent, timestamp: Date) {
        guard let (sessionType, detail) = sessionInfo(from: event) else { return }

        let record = SessionRecord(
            id: UUID(),
            type: sessionType,
            detail: detail,
            timestamp: timestamp
        )
        records.append(record)
        scheduleDebouncedSave()
    }

    /// Removes records older than ``maxAgeDays`` and caps the list at ``maxRecords``
    /// (keeping the most-recent records).
    func prune() {
        let cutoff = Date().addingTimeInterval(-Double(maxAgeDays) * 24 * 60 * 60)
        records = records.filter { $0.timestamp >= cutoff }
        if records.count > maxRecords {
            records = Array(records.suffix(maxRecords))
        }
    }

    /// Removes all records from memory and deletes the persistence file.
    func clearHistory() {
        records = []
        saveTimer?.cancel()
        saveTimer = nil
        do {
            if FileManager.default.fileExists(atPath: filePath) {
                try FileManager.default.removeItem(atPath: filePath)
            }
        } catch {
            Self.logger.error("SessionHistoryTracker: failed to delete file: \(error.localizedDescription)")
        }
    }

    /// Prunes stale records, then writes the current list to ``filePath`` atomically.
    ///
    /// The containing directory is created with `0o700` permissions if absent.
    func save() {
        prune()
        let url = URL(fileURLWithPath: filePath)
        let directoryURL = url.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = try Self.jsonEncoder.encode(records)
            // Atomic write: write to a sibling temp file then rename.
            let tempURL = directoryURL.appendingPathComponent(UUID().uuidString + ".tmp")
            try data.write(to: tempURL, options: .atomic)
            // Replace destination atomically.
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        } catch {
            Self.logger.error("SessionHistoryTracker: save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private helpers

    /// Schedules a debounced save 5 seconds after the last call.
    private func scheduleDebouncedSave() {
        saveTimer?.cancel()
        saveTimer = Just(())
            .delay(for: .seconds(5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.save()
            }
    }

    /// Reads JSON from ``filePath``, decodes, then prunes.
    private func load() {
        let url = URL(fileURLWithPath: filePath)
        guard FileManager.default.fileExists(atPath: filePath),
              let data = try? Data(contentsOf: url)
        else { return }

        do {
            records = try Self.jsonDecoder.decode([SessionRecord].self, from: data)
            prune()
        } catch {
            Self.logger.error("SessionHistoryTracker: load failed: \(error.localizedDescription)")
            records = []
        }
    }

    /// Maps a session-type ``AgentEvent`` to its ``SessionType`` and detail string.
    ///
    /// Returns `nil` for any event that is not a session type.
    private func sessionInfo(from event: AgentEvent) -> (SessionType, String)? {
        switch event {
        case .terminalSession(let detail):
            return (.terminal, detail)
        case .desktopSession(let detail):
            return (.desktop, detail)
        case .fileTransfer(let detail):
            return (.fileTransfer, detail)
        case .vncSession(let detail):
            return (.vnc, detail)
        default:
            return nil
        }
    }
}
