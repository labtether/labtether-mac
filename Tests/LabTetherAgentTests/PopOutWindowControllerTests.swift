import AppKit
import XCTest
@testable import LabTetherAgent

final class PopOutWindowControllerTests: XCTestCase {
    @MainActor
    func testRetiredPanelCloseCannotHideReplacementOrStopItsCloseTracking() {
        _ = NSApplication.shared
        let controller = PopOutWindowController()
        let retired = makePanel()
        let replacement = makePanel()
        defer {
            controller.close()
            retired.close()
            replacement.close()
        }

        controller.present(retired)
        XCTAssertTrue(controller.isVisible)
        controller.close()
        XCTAssertFalse(controller.panelVisible)
        XCTAssertFalse(controller.isVisible)
        XCTAssertFalse(retired.isVisible)
        XCTAssertNil(retired.delegate)

        controller.present(replacement)
        // Deliver the old window's close after its replacement has been shown.
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: retired))
        XCTAssertTrue(controller.panelVisible)
        XCTAssertTrue(controller.isVisible)
        XCTAssertTrue(replacement.isVisible)
        XCTAssertTrue(replacement.delegate === controller)

        replacement.close()
        XCTAssertFalse(controller.panelVisible)
        XCTAssertFalse(controller.isVisible)
        XCTAssertNil(replacement.delegate)
    }

    @MainActor
    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 100),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isReleasedWhenClosed = false
        return panel
    }
}
