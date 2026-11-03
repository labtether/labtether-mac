import AppKit
import Foundation

extension Notification.Name {
    /// The token went with a move to another Hub; setup asks for a new one.
    static let labTetherNeedsHubToken = Notification.Name("LabTetherNeedsHubToken")
}

extension AgentProcess {
    /// Owner decision for 2.0: a new address of the same Hub keeps this Mac's
    /// token; another Hub is named first and removes the token only after the
    /// person agrees. Returns true when the start can go ahead now; otherwise
    /// `retry` runs once the check or the answer is in.
    func hubChangeSettled(then retry: @escaping @MainActor () -> Void) -> Bool {
        guard settings.hubChangeNeedsConfirmation else { return true }
        guard !checkingHubChange else { return false }
        checkingHubChange = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let verdict = await self.settings.checkHubChange()
            self.checkingHubChange = false
            guard verdict != .sameHub, self.settings.hubChangeNeedsConfirmation else {
                retry()
                return
            }
            guard self.confirmOtherHub(verdict) else {
                self.status.markError("Not started. The new Hub address needs a token from that Hub.")
                return
            }
            self.settings.confirmedHubChangeScope = self.settings.pendingHubScope
            retry()
        }
        return false
    }

    private func confirmOtherHub(_ verdict: HubChangeVerdict) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = verdict == .unknown ? "Can't confirm this is the same Hub" : "This is another Hub"
        alert.informativeText = "This Mac's token works only with the Hub that issued it. Continue removes it; then enter an enrollment token from the new Hub."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
