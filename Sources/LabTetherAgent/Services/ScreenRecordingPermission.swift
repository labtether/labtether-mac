import CoreGraphics
import AppKit

/// Checks and requests macOS Screen Recording (TCC) permission.
enum ScreenRecordingPermission {
    /// Check if Screen Recording permission is currently granted.
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Request Screen Recording permission. Opens System Settings prompt on first call.
    /// Returns true if already granted.
    @discardableResult
    static func request() -> Bool {
        guard !AppStateLocation.current.isolated else { return false }
        return CGRequestScreenCaptureAccess()
    }

    /// Open System Settings to the Screen Recording privacy pane.
    static func openSettings() {
        guard !AppStateLocation.current.isolated else { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
