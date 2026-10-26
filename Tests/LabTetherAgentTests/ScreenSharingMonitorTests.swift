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

    /// The Fix action used to ignore AppleScript errors, so a failed
    /// kickstart looked like success. A dismissed prompt is not a failure.
    func testGrantResultReportsFailuresButNotCancelledPrompt() {
        XCTAssertEqual(ScreenSharingMonitor.grantResult(appleScriptError: nil), .granted)
        XCTAssertEqual(
            ScreenSharingMonitor.grantResult(appleScriptError: [NSAppleScript.errorNumber: -128]),
            .cancelled
        )
        XCTAssertEqual(
            ScreenSharingMonitor.grantResult(appleScriptError: [
                NSAppleScript.errorNumber: 1,
                NSAppleScript.errorMessage: "kickstart: permission denied",
            ]),
            .failed("Could not grant Screen Sharing control: kickstart: permission denied")
        )
    }
}
