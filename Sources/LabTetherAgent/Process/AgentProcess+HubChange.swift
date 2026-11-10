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
                // Cancel on Restart leaves the agent running on its old
                // address, so only a cancelled Start is "not started".
                if !self.isRunning {
                    self.status.markError("Not started. The new Hub address needs a token from that Hub.")
                }
                return
            }
            self.settings.confirmedHubChangeScope = self.settings.pendingHubScope
            retry()
        }
        return false
    }

    /// A saved CA file that has never verified this Hub alone is checked once
    /// per start. When it passes it is the agent's only root from this start
    /// on; when it does not, or the Hub does not answer, the agent starts
    /// with it as before and one line says so.
    func chosenCASettled(then retry: @escaping @MainActor () -> Void) -> Bool {
        guard settings.chosenCANeedsCheck, !chosenCACheckedForThisStart else { return true }
        guard !checkingChosenCA else { return false }
        checkingChosenCA = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let line = await self.settings.checkSavedChosenCA()
            self.checkingChosenCA = false
            self.chosenCACheckedForThisStart = true
            if let line { self.logBuffer.append("[app] \(line)") }
            retry()
        }
        return false
    }

    /// The same check after each connection: a Hub that was away at start is
    /// there now. A file that passes is the only root from the next start.
    func recheckChosenCAAfterConnect() {
        guard settings.chosenCANeedsCheck, !recheckingChosenCA else { return }
        recheckingChosenCA = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let line = await self.settings.checkSavedChosenCA()
            self.recheckingChosenCA = false
            guard let line else { return }
            let applies = line == AgentSettings.chosenCANowOnlyRoot ? " The running agent uses it from its next start." : ""
            self.logBuffer.append("[app] \(line)\(applies)")
        }
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
