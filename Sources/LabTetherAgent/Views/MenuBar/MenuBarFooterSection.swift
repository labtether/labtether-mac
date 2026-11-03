import AppKit
import SwiftUI

/// Version, "Update available", the ⋯ menu (About, setup, uninstall) and Quit.
struct MenuBarFooterSection: View {
    @ObservedObject var metadata: LocalAPIMetadataStore
    let agentProcess: AgentProcess
    @ObservedObject var settings: AgentSettings
    var appUpdates: AppUpdateChecker?
    @Environment(\.openWindow) private var openWindow
    @State private var showUninstallConfirmation = false

    var body: some View {
        HStack(spacing: LT.space6) {
            Text(BundleHelper.appVersion)
                .font(LT.font(12).monospacedDigit())
                .foregroundStyle(LT.text3)
                .accessibilityLabel("Version \(BundleHelper.appVersion)")
            MenuBarUpdateLink(updates: appUpdates, metadata: metadata)
            Spacer(minLength: LT.space8)
            LTMoreMenu(label: "More: About LabTether, Run setup again, Reset and uninstall") {
                Button(L10n.menuAbout) {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "about")
                }
                Button(L10n.menuSetupWizard) {
                    settings.hasCompletedOnboarding = false
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "onboarding")
                }
                Divider()
                Button(L10n.menuUninstall) {
                    showUninstallConfirmation = true
                }
                .disabled(!settings.allowsSystemIntegration)
            }
            Button(L10n.menuQuit) {
                NSApp.activate(ignoringOtherApps: true)
                agentProcess.forceKill()
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(LTSecondaryButtonStyle(height: 24, fontSize: 12))
            .accessibilityLabel("Quit LabTether")
        }
        .padding(.leading, LT.space8)
        .frame(height: 32)
        .alert(L10n.uninstallTitle, isPresented: $showUninstallConfirmation) {
            Button(L10n.uninstallConfirm, role: .destructive) {
                UninstallManager.performUninstall(agentProcess: agentProcess, settings: settings)
            }
            Button(L10n.uninstallCancel, role: .cancel) {}
        } message: {
            Text(L10n.uninstallMessage)
        }
    }
}

/// "· ↑ Update available" in secondary text, not rose. The new version is in the tooltip.
/// The signed app is never replaced in place; the link opens the release page.
private struct MenuBarUpdateLink: View {
    let updates: AppUpdateChecker?
    @ObservedObject var metadata: LocalAPIMetadataStore

    var body: some View {
        if let updates {
            ObservedUpdateLink(updates: updates, metadata: metadata)
        } else if metadata.snapshot.updateAvailable, let latest = metadata.snapshot.latestVersion {
            UpdateLabel(version: latest, pageURL: AppUpdateRelease.fallbackPage)
        }
    }
}

private struct ObservedUpdateLink: View {
    @ObservedObject var updates: AppUpdateChecker
    @ObservedObject var metadata: LocalAPIMetadataStore

    var body: some View {
        if let update = updates.availableUpdate {
            UpdateLabel(version: update.version, pageURL: update.pageURL)
        } else if metadata.snapshot.updateAvailable, let latest = metadata.snapshot.latestVersion {
            UpdateLabel(version: latest, pageURL: AppUpdateRelease.fallbackPage)
        }
    }
}

private struct UpdateLabel: View {
    let version: String
    let pageURL: URL?

    var body: some View {
        HStack(spacing: LT.space6) {
            Text("·")
                .font(LT.font(12))
                .foregroundStyle(LT.text3)
                .accessibilityHidden(true)
            Button {
                guard let pageURL else { return }
                NSApp.activate(ignoringOtherApps: true)
                NSWorkspace.shared.open(pageURL)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10, weight: .semibold))
                    Text(L10n.menuUpdateAvailable)
                }
            }
            .buttonStyle(LTTextButtonStyle(fontSize: 12))
            .help("Version \(version) is available")
            .accessibilityLabel("Update available, version \(version)")
            .accessibilityHint(pageURL == nil ? "" : "Opens the release page")
        }
    }
}
