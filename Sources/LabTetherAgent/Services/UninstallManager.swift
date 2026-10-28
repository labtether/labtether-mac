import AppKit

/// Performs a clean uninstall: stops agent, removes the Hub SSH key it added,
/// removes config, credentials, and history, then quits.
enum UninstallManager {
    @MainActor
    static func performUninstall(
        agentProcess: AgentProcess,
        settings: AgentSettings
    ) {
        guard settings.allowsSystemIntegration else { return }
        // Capture path before cleanup (accessing appSupportDirectory creates it as side effect)
        let appSupportURL = settings.appSupportDirectory
        // 1. Stop agent
        agentProcess.forceKill()
        // 2. Remove the Hub SSH key line the agent added, while its record
        //    still exists. This never stops the uninstall.
        if case .failed(let detail) = HubSSHKeyRemover.run(
            agentBinaryPath: BundleHelper.agentBinaryPath,
            tokenFilePath: settings.tokenFilePath,
            agentSettingsFilePath: settings.agentSettingsFilePath
        ) {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "The Hub's SSH key was not removed"
            alert.informativeText = "LabTether could not remove the line it added to ~/.ssh/authorized_keys (\(detail)). Remove that line by hand. Uninstall will continue."
            alert.runModal()
        }
        // 3. Remove login item
        _ = LoginItemManager.setEnabled(false)
        // 4. Delete Keychain entries
        _ = KeychainSecretStore.deleteStatus(account: "apiToken")
        _ = KeychainSecretStore.deleteStatus(account: "enrollmentToken")
        _ = KeychainSecretStore.deleteStatus(account: "webrtcTurnPass")
        // 5. Remove Application Support directory (best-effort)
        try? FileManager.default.removeItem(at: appSupportURL)
        // 6. Clear UserDefaults
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        // 7. Quit
        NSApp.terminate(nil)
    }
}
