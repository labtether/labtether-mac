import XCTest
@testable import LabTetherAgent

@MainActor
final class CrashRestartCoordinatorTests: XCTestCase {
    /// A core that quits at once, restarted after each backoff delay, must reach
    /// the cooldown. With a 60 s window the delays outgrew it and the app kept
    /// restarting (and notifying) forever.
    func testCoreThatQuitsAtOnceReachesTheCooldown() {
        let coordinator = CrashRestartCoordinator()
        var now = Date(timeIntervalSince1970: 1_000_000)
        var delays: [TimeInterval] = []
        for _ in 0..<CrashRestartCoordinator.maxCrashRestarts {
            guard case .restart(let delay) = coordinator.recordCrash(at: now) else {
                return XCTFail("cooldown came before \(CrashRestartCoordinator.maxCrashRestarts) restarts")
            }
            delays.append(delay)
            now = now.addingTimeInterval(delay)
        }
        XCTAssertEqual(delays, [3, 6, 12, 24, 48])
        guard case .enterCooldown(let duration) = coordinator.recordCrash(at: now) else {
            return XCTFail("the sixth quick crash restarted again instead of pausing")
        }
        XCTAssertEqual(duration, CrashRestartCoordinator.crashCooldownSeconds)
        XCTAssertTrue(coordinator.crashLoopActive)
    }
}
