import AppKit

/// Performs a clean uninstall: stops agent, removes config, credentials, and history, then quits.
enum UninstallManager {
    @MainActor
    static func performUninstall(
        agentProcess: AgentProcess,
        settings: AgentSettings
    ) {
        // Capture path before cleanup (accessing appSupportDirectory creates it as side effect)
        let appSupportURL = settings.appSupportDirectory
        // 1. Stop agent
        agentProcess.forceKill()
        // 2. Remove login item
        _ = LoginItemManager.setEnabled(false)
        // 3. Delete Keychain entries
        _ = KeychainSecretStore.deleteStatus(account: "apiToken")
        _ = KeychainSecretStore.deleteStatus(account: "enrollmentToken")
        _ = KeychainSecretStore.deleteStatus(account: "webrtcTurnPass")
        // 4. Remove Application Support directory (best-effort)
        try? FileManager.default.removeItem(at: appSupportURL)
        // 5. Clear UserDefaults
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        // 6. Quit
        NSApp.terminate(nil)
    }
}
