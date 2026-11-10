import AppKit
import SwiftUI

/// The menu bar window: status, usage (shown once), alerts, actions, footer.
struct MenuBarView: View {
    let status: AgentStatus
    let agentProcess: AgentProcess
    let settings: AgentSettings
    let screenSharing: ScreenSharingMonitor
    let logBuffer: LogBuffer
    let apiClient: LocalAPIClient
    var appUpdates: AppUpdateChecker?
    /// Called when the user activates "Pop out". Wired in App.swift to the shared controller.
    var onPopOut: () -> Void = {}
    @Environment(\.openWindow) private var openWindow
    @State private var toast: MenuBarToast?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuBarHeaderSection(
                status: status,
                agentProcess: agentProcess,
                settings: settings,
                runtime: apiClient.runtime
            )
            LTSeparator()
            MenuBarUsageSection(
                runtime: apiClient.runtime,
                metrics: apiClient.metrics,
                agentProcess: agentProcess,
                screenSharing: screenSharing,
                settings: settings
            )
            MenuBarAlertsSection(alerts: apiClient.alerts, consoleBaseURL: settings.consoleURL)
            MenuBarQuickActionsSection(
                status: status,
                settings: settings,
                onOpenConsole: {
                    NSApp.activate(ignoringOtherApps: true)
                    openConsole()
                },
                onOpenDevicePage: {
                    NSApp.activate(ignoringOtherApps: true)
                    openDevicePage()
                },
                onPopOut: {
                    NSApp.activate(ignoringOtherApps: true)
                    onPopOut()
                },
                onOpenLogWindow: {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "log-viewer")
                },
                onTestConnection: testConnection,
                onCopyDiagnostics: {
                    NSApp.activate(ignoringOtherApps: true)
                    copyDiagnostics()
                },
                onOpenSettings: {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "settings")
                }
            )
            LTSeparator()
            MenuBarFooterSection(
                metadata: apiClient.metadata,
                agentProcess: agentProcess,
                settings: settings,
                appUpdates: appUpdates
            )
        }
        .padding(LT.space6)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .background(LT.pop)
        .overlay(alignment: .top) {
            if let toast {
                LTToast(text: toast.text, isError: toast.isError)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, LT.space8)
                    .padding(.horizontal, LT.space12)
            }
        }
        .animation(LT.springSnappy, value: toast)
    }

    // MARK: - Actions

    private func show(_ text: String, isError: Bool = false) {
        let next = MenuBarToast(text: text, isError: isError)
        toast = next
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            if toast == next { toast = nil }
        }
    }

    private func testConnection() {
        Task {
            let result = await ConnectionTester.quickTest(
                hubURL: settings.hubURL,
                tlsSkipVerify: settings.tlsSkipVerify,
                tlsCAFile: settings.effectiveTLSCAFile
            )
            switch result {
            case .success(responseTimeMs: let ms):
                show(ConnectionTestText.success(ms))
            case .failure(error: let error):
                show(error, isError: true)
            }
        }
    }

    private func openConsole() {
        if let url = settings.consoleURL {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor private func openDevicePage() {
        if let base = settings.consoleURL,
           let deviceURL = ConsoleURLBuilder.nodeURL(base: base, assetID: status.assetID) {
            NSWorkspace.shared.open(deviceURL)
        }
    }

    @MainActor private func copyDiagnostics() {
        let logSummary = DiagnosticsLogSummary(logLines: logBuffer.logLines)
        let report = DiagnosticsCollector.collect(
            appVersion: BundleHelper.appVersion,
            buildNumber: BundleHelper.buildNumber,
            agentVersion: apiClient.metadata.snapshot.agentVersion,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: BundleHelper.architecture,
            hubURL: settings.hubURL,
            connectionState: status.state.rawValue,
            apiTokenConfigured: !settings.apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || settings.hasPersistedAgentToken,
            enrollmentTokenConfigured: !settings.enrollmentToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            assetID: status.assetID.isEmpty ? settings.assetID : status.assetID,
            groupID: settings.groupID,
            pid: status.pid,
            uptime: status.uptime,
            tlsSkipVerify: settings.tlsSkipVerify,
            dockerMode: settings.normalizedDockerMode(),
            filesRootMode: settings.normalizedFilesRootMode(),
            allowRemoteOverrides: settings.allowRemoteOverrides,
            logLevel: settings.normalizedLogLevel(),
            webrtcEnabled: settings.effectiveWebRTCEnabled,
            screenSharingEnabled: screenSharing.isEnabled,
            screenSharingControlAccess: screenSharing.hasControlAccess,
            validationErrors: settings.validationErrors(),
            secretPersistenceErrors: settings.secretPersistenceErrors,
            logSummaryLines: logSummary.reportLines
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        show("Diagnostics copied")
    }
}

private struct MenuBarToast: Equatable {
    let id = UUID()
    let text: String
    let isError: Bool
}

/// The quick connection test result, shared by the menu, Settings and setup.
enum ConnectionTestText {
    static func success(_ milliseconds: Int) -> String {
        "Reachable · \(milliseconds) ms"
    }
}
