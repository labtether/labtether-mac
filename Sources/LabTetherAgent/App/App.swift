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
            .onAppear {
                appState.apiClient.setMenuVisible(true)
                appState.screenSharing.setMenuVisible(true)
                appState.status.setMenuVisible(true)
            }
            .onDisappear {
                appState.apiClient.setMenuVisible(false)
                appState.screenSharing.setMenuVisible(false)
                appState.status.setMenuVisible(false)
                appState.refreshMenuBarLabel()
            }
            .onChange(of: appState.shouldShowOnboarding) { shouldShow in
                if shouldShow {
                    openWindow(id: "onboarding")
                    appState.shouldShowOnboarding = false
                }
            }
        } label: {
            let presentation = appState.menuBarLabelPresentation

            HStack(spacing: 4) {
                LTMenuBarStatusIcon(kind: presentation.kind)
                if let primaryMetricsText = presentation.primaryMetricsText {
                    Text(primaryMetricsText)
                        .font(LT.mono(10, weight: .medium))
                    if let secondaryMetricsText = presentation.secondaryMetricsText {
                        Text(secondaryMetricsText)
                            .font(LT.mono(10, weight: .medium))
                    }
                }
            }
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView(
                settings: appState.settings,
                agentProcess: appState.agentProcess,
                status: appState.status,
                metadata: appState.apiClient.metadata
            )
        }
        .windowResizability(.contentSize)

        Window("Agent Logs", id: "log-viewer") {
            LogBufferView(logBuffer: appState.logBuffer, status: appState.status)
        }
        .defaultSize(width: 700, height: 500)

        Window("Welcome to LabTether", id: "onboarding") {
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
}

/// Handles app lifecycle events to ensure clean process management.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register bundled premium fonts before any SwiftUI views render.
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
