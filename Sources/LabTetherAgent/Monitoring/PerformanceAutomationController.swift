import Foundation

@MainActor
final class PerformanceAutomationController: ObservableObject {
    struct ScrollCommand: Equatable {
        let id: Int
        let targetID: String
    }

    static let popOutTopAnchorID = "lt-profile-top"
    static let popOutBottomAnchorID = "lt-profile-bottom"

    @Published private(set) var popOutScrollCommand: ScrollCommand?

    private let logBuffer: LogBuffer
    private var scrollTask: Task<Void, Never>?
    private var logBurstTask: Task<Void, Never>?
    private var nextScrollCommandID = 0

    init(logBuffer: LogBuffer) {
        self.logBuffer = logBuffer
    }

    /// Profiling input comes from outside the app, so keep runs short and finite.
    static func boundedDuration(_ seconds: TimeInterval) -> TimeInterval {
        seconds.isFinite ? min(max(seconds, 0), 120) : 0
    }

    func runPopOutScrollProfile(durationSeconds: TimeInterval) {
        scrollTask?.cancel()
        let duration = Self.boundedDuration(durationSeconds)
        scrollTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let deadline = Date().addingTimeInterval(duration)
            var targetID = Self.popOutBottomAnchorID
            while Date() < deadline {
                nextScrollCommandID += 1
                popOutScrollCommand = ScrollCommand(id: nextScrollCommandID, targetID: targetID)
                targetID = targetID == Self.popOutBottomAnchorID ? Self.popOutTopAnchorID : Self.popOutBottomAnchorID
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
            }
        }
    }

    func runLogBurst(durationSeconds: TimeInterval, linesPerBatch requestedLines: Int = 40) {
        logBurstTask?.cancel()
        // A negative count would trap when building the range below.
        let linesPerBatch = min(max(requestedLines, 1), 500)
        let duration = Self.boundedDuration(durationSeconds)
        logBurstTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let deadline = Date().addingTimeInterval(duration)
            var sequence = 0
            while Date() < deadline {
                let now = Date()
                let timestamp = Self.profileTimestampFormatter.string(from: now)
                let lines = (0..<linesPerBatch).map { idx in
                    let globalIndex = sequence + idx
                    switch globalIndex % 3 {
                    case 0:
                        return "\(timestamp) [profiler] info synthetic scroll burst \(globalIndex)"
                    case 1:
                        return "\(timestamp) [profiler] warning synthetic backlog warning \(globalIndex)"
                    default:
                        return "\(timestamp) [profiler] error synthetic reconnect error \(globalIndex)"
                    }
                }
                sequence += linesPerBatch
                logBuffer.appendBatch(lines)
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
            }
        }
    }

    func cancelAll() {
        scrollTask?.cancel()
        logBurstTask?.cancel()
    }

    private static let profileTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter
    }()
}
