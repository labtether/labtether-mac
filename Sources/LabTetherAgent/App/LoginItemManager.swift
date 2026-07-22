import Foundation
import ServiceManagement

/// Manages macOS login item registration using SMAppService (macOS 13+).
enum LoginItemManager {
    /// Register or unregister the app as a login item.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            // register() can return successfully while macOS reports
            // .requiresApproval. Only persist the requested setting after the
            // system registration actually reflects it.
            return registrationMatches(
                requestedEnabled: enabled,
                reportedEnabled: service.status == .enabled
            )
        } catch {
            print("LoginItemManager: failed to \(enabled ? "register" : "unregister"): \(error)")
            return false
        }
    }

    /// Check if the app is currently registered as a login item.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func registrationMatches(requestedEnabled: Bool, reportedEnabled: Bool) -> Bool {
        requestedEnabled == reportedEnabled
    }
}
