import AppKit
import SwiftUI

// MARK: - PopOutView

/// The floating panel: a canvas with sheets, problems first. Alerts, usage and
/// recent events come first; bandwidth, sessions and Remote View follow.
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

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear
                        .frame(height: 1)
                        .id(PerformanceAutomationController.popOutTopAnchorID)

                    PopOutHeaderSection(
                        status: status,
                        agentProcess: agentProcess,
                        settings: settings,
                        runtime: apiClient.runtime,
                        onOpenConsole: openConsole,
                        onOpenDevicePage: openDevicePage
                    )

                    PopOutAlertsSection(alerts: apiClient.alerts, consoleBaseURL: settings.consoleURL)
                        .padding(.top, 20)

                    PopOutUsageSection(runtime: apiClient.runtime, metrics: apiClient.metrics, agentProcess: agentProcess)
                        .padding(.top, LT.space24)

                    RecentEventsSectionView(logBuffer: logBuffer)
                        .padding(.top, LT.space24)

                    PopOutBandwidthSection(tracker: bandwidthTracker)
                        .padding(.top, LT.space24)

                    PopOutSessionHistorySection(tracker: sessionHistory)
                        .padding(.top, LT.space24)

                    PopOutScreenSharingSection(screenSharing: screenSharing, settings: settings)
                        .padding(.top, LT.space24)

                    Color.clear
                        .frame(height: 1)
                        .id(PerformanceAutomationController.popOutBottomAnchorID)
                }
                .padding(.horizontal, LT.space16)
                .padding(.top, 34)
                .padding(.bottom, LT.space24)
            }
            .onChange(of: automation.popOutScrollCommand) { command in
                guard let command else { return }
                withAnimation(.linear(duration: 0.28)) {
                    proxy.scrollTo(command.targetID, anchor: command.targetID == PerformanceAutomationController.popOutTopAnchorID ? .top : .bottom)
                }
            }
        }
        .background(LT.canvas)
        .frame(minWidth: 380, minHeight: 500)
    }

    private func openConsole() {
        if let consoleURL = settings.consoleURL {
            NSWorkspace.shared.open(consoleURL)
        }
    }

    @MainActor private func openDevicePage() {
        if let consoleURL = settings.consoleURL,
           let deviceURL = ConsoleURLBuilder.nodeURL(base: consoleURL, assetID: status.assetID) {
            NSWorkspace.shared.open(deviceURL)
        }
    }
}

/// Firing alerts in a sheet. Hidden when nothing is firing.
struct PopOutAlertsSection: View {
    @ObservedObject var alerts: LocalAPIAlertsStore
    let consoleBaseURL: URL?

    var body: some View {
        let firing = alerts.snapshot.firingAlerts
        if !firing.isEmpty {
            VStack(alignment: .leading, spacing: LT.space8) {
                LTSectionTitle(L10n.menuAlerts)
                LTSheet {
                    AlertRowsView(firingAlerts: firing, consoleBaseURL: consoleBaseURL, horizontalPadding: LT.space8)
                }
            }
        }
    }
}
