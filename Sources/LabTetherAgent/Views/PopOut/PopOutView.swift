import SwiftUI

// MARK: - PopOutView

/// Extended floating dashboard that provides a richer, scrollable view of agent state.
///
/// Displays a large health orb hero section, three-column metric cards with sparklines,
/// network statistics, firing alerts, recent log events, screen sharing status, and
/// a horizontal action bar. An ambient orb animation runs continuously in the background.
struct PopOutView: View {
    let status: AgentStatus
    let agentProcess: AgentProcess
    let settings: AgentSettings
    let screenSharing: ScreenSharingMonitor
    let automation: PerformanceAutomationController
    let logBuffer: LogBuffer
    let apiClient: LocalAPIClient
    let sessionHistory: SessionHistoryTracker
    let bandwidthTracker: BandwidthTracker

    // MARK: - Body

    var body: some View {
        ZStack {
            PopOutBackground()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: LT.space16) {
                        Color.clear
                            .frame(height: 1)
                            .id(PerformanceAutomationController.popOutTopAnchorID)

                        PopOutHeroSection(
                            status: status,
                            agentProcess: agentProcess,
                            settings: settings,
                            runtime: apiClient.runtime,
                            metrics: apiClient.metrics
                        )

                        LTSeparator()

                        PopOutSystemSection(runtime: apiClient.runtime, metrics: apiClient.metrics, agentProcess: agentProcess)

                        LTSeparator()

                        PopOutBandwidthSection(tracker: bandwidthTracker)

                        LTSeparator()

                        PopOutAlertsSection(alerts: apiClient.alerts, consoleBaseURL: settings.consoleURL)

                        recentEventsSection

                        PopOutSessionHistorySection(tracker: sessionHistory)

                        PopOutScreenSharingSection(screenSharing: screenSharing)

                        LTSeparator()

                        PopOutActionBarSection(
                            status: status,
                            settings: settings,
                            onOpenConsole: openConsole,
                            onOpenDevicePage: openDevicePage
                        )

                        Color.clear
                            .frame(height: 1)
                            .id(PerformanceAutomationController.popOutBottomAnchorID)
                    }
                    .padding(LT.space16)
                }
                .onChange(of: automation.popOutScrollCommand) { command in
                    guard let command else { return }
                    withAnimation(.linear(duration: 0.28)) {
                        proxy.scrollTo(command.targetID, anchor: command.targetID == PerformanceAutomationController.popOutTopAnchorID ? .top : .bottom)
                    }
                }
            }
        }
        .ltGlassBackground()
        .frame(minWidth: 380, minHeight: 500)
    }

    private var recentEventsSection: some View {
        RecentEventsSectionView(logBuffer: logBuffer)
    }

    private func openConsole() {
        if let consoleURL = settings.consoleURL {
            NSWorkspace.shared.open(consoleURL)
        }
    }

    @MainActor private func openDevicePage() {
        if let consoleURL = settings.consoleURL, !status.assetID.isEmpty {
            let deviceURL = consoleURL.appendingPathComponent("nodes/\(status.assetID)")
            NSWorkspace.shared.open(deviceURL)
        }
    }
}
