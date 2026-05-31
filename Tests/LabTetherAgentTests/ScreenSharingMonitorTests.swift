import XCTest
@testable import LabTetherAgent

final class ScreenSharingMonitorTests: XCTestCase {
    func testShellSingleQuotedArgumentEscapesSingleQuotes() {
        XCTAssertEqual(
            ScreenSharingMonitor.shellSingleQuotedArgument("o'brien"),
            #"'o'\''brien'"#
        )
    }

    func testAppleScriptStringLiteralEscapesDelimiters() {
        XCTAssertEqual(
            ScreenSharingMonitor.appleScriptStringLiteral(#"echo "hi" \ done"#),
            #""echo \"hi\" \\ done""#
        )
    }

    func testScreenSharingGrantCommandQuotesKickstartAndUser() {
        let command = ScreenSharingMonitor.screenSharingGrantCommand(
            kickstart: "/tmp/kick start",
            user: "o'brien"
        )

        XCTAssertEqual(
            command,
            #"'/tmp/kick start' -configure -access -on -users 'o'\''brien' -privs -all -restart -agent"#
        )
    }
}
