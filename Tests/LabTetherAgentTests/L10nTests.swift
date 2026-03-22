import XCTest
@testable import LabTetherAgent

final class L10nTests: XCTestCase {
    func testAllStringKeysReturnNonEmptyValues() {
        XCTAssertFalse(L10n.connected.isEmpty)
        XCTAssertFalse(L10n.menuSettings.isEmpty)
        XCTAssertFalse(L10n.onboardingWelcomeTitle.isEmpty)
        XCTAssertFalse(L10n.aboutTitle.isEmpty)
        XCTAssertFalse(L10n.sessionTitle.isEmpty)
        XCTAssertFalse(L10n.bandwidthTitle.isEmpty)
        XCTAssertFalse(L10n.diagnosticsTitle.isEmpty)
        XCTAssertFalse(L10n.uninstallTitle.isEmpty)
    }

    func testConnectedStringContainsExpectedEnglishValue() {
        XCTAssertEqual(L10n.connected, "Connected")
    }
}
