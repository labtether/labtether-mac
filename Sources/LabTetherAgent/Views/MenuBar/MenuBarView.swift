import SwiftUI

struct MenuBarView: View {
    let status: AgentStatus
    let agentProcess: AgentProcess
    let settings: AgentSettings
    let screenSharing: ScreenSharingMonitor
    let logBuffer: LogBuffer
    let apiClient: LocalAPIClient
    /// Called when the user activates "Pop Out Window". Wired in App.swift to the shared controller.
    var onPopOut: () -> Void = {}
    @Environment(\.openWindow) private var openWindow
    @Environment(\.animationsActive) private var animationsActive
    @State private var hoveredItem: String?
    @State private var copyToast: String?

    var body: some View {
        VStack(spacing: 0) {
            MenuBarHeroSection(
                status: status,
                agentProcess: agentProcess,
                settings: settings,
                runtime: apiClient.runtime,
                metrics: apiClient.metrics
            )

            MenuBarRestartBannerSection(agentProcess: agentProcess)
                .padding(.horizontal, LT.space12)
                .padding(.bottom, LT.space6)

            LTSeparator()
                .padding(.horizontal, LT.space12)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: LT.space4) {
                    MenuBarSystemSection(runtime: apiClient.runtime, metrics: apiClient.metrics, agentProcess: agentProcess)

                    MenuBarConnectionSection(
                        status: status,
                        settings: settings,
                        runtime: apiClient.runtime,
                        onCopy: copyToClipboard
                    )

                    MenuBarAlertsSection(alerts: apiClient.alerts, consoleBaseURL: settings.consoleURL)

                    MenuBarScreenSharingSection(screenSharing: screenSharing, settings: settings)

                    LTSeparator()
                        .padding(.horizontal, LT.space12)

                    MenuBarQuickActionsSection(
                        status: status,
                        settings: settings,
                        logBuffer: logBuffer,
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
                            openLogWindow()
                        },
                        onTestConnection: {
                            Task {
                                let result = await ConnectionTester.quickTest(
                                    hubURL: settings.hubURL,
                                    tlsSkipVerify: settings.tlsSkipVerify
                                )
                                let message: String
                                switch result {
                                case .success(responseTimeMs: let ms):
                                    message = "Connection successful (\(ms)ms)"
                                case .failure(error: let error):
                                    message = "Connection failed: \(error)"
                                }
                                copyToClipboard(message, label: "Test")
                            }
                        },
                        onCopyDiagnostics: {
                            NSApp.activate(ignoringOtherApps: true)
                            copyDiagnostics()
                        },
                        onOpenSettings: {
                            NSApp.activate(ignoringOtherApps: true)
                            openWindow(id: "settings")
                        }
                    )
                }
            }

            MenuBarFooterSection(metadata: apiClient.metadata, agentProcess: agentProcess, settings: settings)
        }
        .background(MenuBarBackground(status: status, agentProcess: agentProcess, runtime: apiClient.runtime))
        .frame(width: 340)
        .overlay(alignment: .top) {
            if let toast = copyToast {
                LTToast(text: toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
                    .zIndex(100)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: copyToast)
    }

    // MARK: - Helpers

    private func copyToClipboard(_ value: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        withAnimation(LT.springSnappy) {
            copyToast = "\(label) copied"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            if copyToast == "\(label) copied" {
                withAnimation(LT.springSnappy) {
                    copyToast = nil
                }
            }
        }
    }

    private func openConsole() {
        if let url = settings.consoleURL {
            NSWorkspace.shared.open(url)
        }
    }

    private func openDevicePage() {
        if let base = settings.consoleURL {
            let deviceURL = base.appendingPathComponent("nodes/\(status.assetID)")
            NSWorkspace.shared.open(deviceURL)
        }
    }

    private func openLogWindow() {
        openWindow(id: "log-viewer")
    }

    private func copyDiagnostics() {
        let logSummary = DiagnosticsLogSummary(logLines: logBuffer.logLines)
        let report = DiagnosticsCollector.collect(
            appVersion: BundleHelper.appVersion,
            buildNumber: BundleHelper.buildNumber,
            agentVersion: apiClient.metadata.snapshot.agentVersion,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: BundleHelper.architecture,
            hubURL: settings.hubURL,
            connectionState: status.state.rawValue,
            apiTokenConfigured: !settings.apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
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
        copyToClipboard(report, label: "Diagnostics")
    }
}
