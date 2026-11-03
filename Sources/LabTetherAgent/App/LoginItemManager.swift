import Foundation
import ServiceManagement

/// Manages macOS login item registration using SMAppService (macOS 13+).
enum LoginItemManager {
    /// Register or unregister the app as a login item.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        guard !AppStateLocation.current.isolated else { return false }
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

    /// Setup ends with Start at login on, so the Mac comes back online after a
    /// restart; the switch in Settings turns it off. Separate QA instances
    /// never register. If macOS refuses, the switch shows what macOS has.
    @MainActor
    static func turnOnAfterSetup(
        _ settings: AgentSettings,
        allowed: Bool? = nil,
        register: (Bool) -> Bool = { setEnabled($0) },
        registered: () -> Bool = { isEnabled }
    ) {
        guard allowed ?? settings.allowsSystemIntegration else { return }
        settings.startAtLogin = register(true) ? true : registered()
    }
}
