import XCTest
@testable import LabTetherAgent

final class LoginItemManagerTests: XCTestCase {
    func testRegistrationMustMatchRequestedSystemState() {
        XCTAssertTrue(
            LoginItemManager.registrationMatches(
                requestedEnabled: true,
                reportedEnabled: true
            )
        )
        XCTAssertTrue(
            LoginItemManager.registrationMatches(
                requestedEnabled: false,
                reportedEnabled: false
            )
        )
        XCTAssertFalse(
            LoginItemManager.registrationMatches(
                requestedEnabled: true,
                reportedEnabled: false
            )
        )
        XCTAssertFalse(
            LoginItemManager.registrationMatches(
                requestedEnabled: false,
                reportedEnabled: true
            )
        )
    }

    /// Owner decision for 2.0: setup ends with Start at login on, the switch
    /// shows what macOS really did, and separate QA instances never register.
    @MainActor
    func testSetupTurnsOnStartAtLogin() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lt-login-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = AgentSettings(
            testSettingsStore: UserDefaults(suiteName: "lt-login-\(UUID().uuidString)")!,
            appSupportDirectory: folder
        )
        XCTAssertFalse(settings.startAtLogin)

        var requests: [Bool] = []
        LoginItemManager.turnOnAfterSetup(settings, allowed: true, register: { requests.append($0); return true })
        XCTAssertEqual(requests, [true])
        XCTAssertTrue(settings.startAtLogin)

        settings.startAtLogin = false
        LoginItemManager.turnOnAfterSetup(settings, allowed: true, register: { _ in false }, registered: { false })
        XCTAssertFalse(settings.startAtLogin)

        LoginItemManager.turnOnAfterSetup(settings, allowed: false, register: { _ in
            XCTFail("a separate QA instance must not register a login item")
            return true
        })
        XCTAssertFalse(settings.startAtLogin)
    }
}
