import Foundation

/// Encapsulates crash detection, backoff delay calculation, and cooldown timer
/// management, extracted from AgentProcess to keep process lifecycle separate
/// from crash-restart policy.
@MainActor
final class CrashRestartCoordinator: ObservableObject {
    enum CrashAction {
        /// Restart after the given delay (exponential backoff).
        case restart(delay: TimeInterval)
        /// Too many crashes in the window — enter cooldown before retrying.
        case enterCooldown(duration: TimeInterval)
    }

    @Published var crashLoopActive: Bool = false

    private var crashTimestamps: [Date] = []
    private var crashCooldownTask: Task<Void, Never>?

    static let maxCrashRestarts = 5
    static let crashWindowSeconds: TimeInterval = 60
    static let crashCooldownSeconds: TimeInterval = 300 // 5 minutes

    /// Record a crash and return the appropriate action.
    ///
    /// Callers are responsible for acting on the returned value (scheduling a
    /// delayed restart or entering cooldown).
    func recordCrash() -> CrashAction {
        let now = Date()

        // Prune timestamps outside the rolling window
        crashTimestamps = crashTimestamps.filter {
            now.timeIntervalSince($0) < Self.crashWindowSeconds
        }

        if crashTimestamps.count >= Self.maxCrashRestarts {
            crashLoopActive = true
            return .enterCooldown(duration: Self.crashCooldownSeconds)
        }

        crashTimestamps.append(now)
        let attempt = crashTimestamps.count
        let delay = 3.0 * pow(2.0, Double(attempt - 1)) // 3s, 6s, 12s, 24s, 48s
        return .restart(delay: delay)
    }

    /// The 1-based attempt number for the most recent crash (useful for logging).
    var currentAttempt: Int {
        crashTimestamps.count
    }

    /// Reset all crash tracking state (e.g. on successful connection or user
    /// restart).
    func reset() {
        crashTimestamps.removeAll()
        crashLoopActive = false
        cancelCooldown()
    }

    /// Cancel any pending cooldown timer without clearing crash history.
    func cancelCooldown() {
        crashCooldownTask?.cancel()
        crashCooldownTask = nil
    }

    /// Schedule a cooldown timer that fires `onExpired` when the cooldown
    /// elapses. The coordinator clears its crash history and sets
    /// `crashLoopActive = false` before calling the closure.
    func scheduleCooldown(duration: TimeInterval, onExpired: @escaping @MainActor () -> Void) {
        crashCooldownTask?.cancel()
        crashCooldownTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self.crashTimestamps.removeAll()
            self.crashLoopActive = false
            onExpired()
        }
    }
}
