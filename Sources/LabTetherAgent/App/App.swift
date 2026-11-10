import SwiftUI
import Combine

// MARK: - Debug Boot

private func debugBoot(_ message: @autoclosure () -> String) {
    guard ProcessInfo.processInfo.environment["LABTETHER_AGENT_DEBUG_BOOT"] == "1" else { return }
    fputs("[boot] \(message())\n", stderr)
}

@main
struct LabTetherAgentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                status: appState.status,
                agentProcess: appState.agentProcess,
                settings: appState.settings,
                screenSharing: appState.screenSharing,
                logBuffer: appState.logBuffer,
                apiClient: appState.apiClient,
                appUpdates: appState.appUpdates,
                onPopOut: { AppState.shared.popOutController.toggle(appState: AppState.shared) }
            )
            .environment(\.animationsActive, appState.apiClient.animationsActive)
            // The menu window is ordered in and out, not rebuilt: onAppear
            // would report only the first opening. Ask the window itself, so
            // every opening refreshes at once and a closed menu polls slowly.
            .background(WindowVisibilityReporter { visible in
                appState.apiClient.setMenuVisible(visible)
                appState.screenSharing.setMenuVisible(visible)
                appState.status.setMenuVisible(visible)
                if !visible { appState.refreshMenuBarLabel() }
            })
        } label: {
            let presentation = appState.menuBarLabelPresentation

            HStack(spacing: 4) {
                Image(nsImage: MenuBarGlyph.image(for: presentation.kind))
                    .accessibilityLabel(presentation.kind.accessibilityLabel)
                if let metricsText = presentation.metricsText {
                    Text(metricsText)
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                }
            }
            // The label is on screen from launch; the menu content is built
            // only when the menu first opens, and onChange never reports the
            // value a view starts with. So first-launch setup opens from here.
            .onAppear { showOnboardingIfNeeded() }
            .onChange(of: appState.shouldShowOnboarding) { _ in showOnboardingIfNeeded() }
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView(
                settings: appState.settings,
                agentProcess: appState.agentProcess,
                status: appState.status,
                metadata: appState.apiClient.metadata,
                runtime: appState.apiClient.runtime
            )
        }
        .windowResizability(.contentSize)

        Window("Logs", id: "log-viewer") {
            LogBufferView(logBuffer: appState.logBuffer, status: appState.status)
        }
        .defaultSize(width: 700, height: 500)

        Window("Set up LabTether", id: "onboarding") {
            OnboardingView(
                settings: appState.settings,
                agentProcess: appState.agentProcess
            )
        }
        .windowResizability(.contentSize)

        Window("About LabTether", id: "about") {
            AboutView(
                metadata: appState.apiClient.metadata,
                deviceFingerprintPath: appState.settings.deviceFingerprintFilePath
            )
        }
        .windowResizability(.contentSize)
    }

    private func showOnboardingIfNeeded() {
        guard appState.shouldShowOnboarding else { return }
        appState.shouldShowOnboarding = false
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "onboarding")
    }
}

/// Handles app lifecycle events to ensure clean process management.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register the bundled mono font before any SwiftUI views render.
        FontLoader.registerAll()

        // The state-directory lock was acquired before AppState construction.

        // Ensure shared app state is initialized at launch time so auto-start
        // behavior does not depend on menu/window scene materialization timing.
        _ = AppState.shared
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.sessionHistory.save()
        AppState.shared.bandwidthTracker.save()
        // Force-kill the agent process so it doesn't orphan
        AppState.shared.agentProcess.forceKill()
        AppState.shared.settings.cleanupEphemeralSecrets()
    }
}
