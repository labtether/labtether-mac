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
}
