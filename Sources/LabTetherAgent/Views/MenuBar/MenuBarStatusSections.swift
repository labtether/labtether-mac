import SwiftUI

/// Usage shown once (three meters and the network line) and the Screen Sharing row.
/// Draws its own trailing separator so an empty group leaves no double line.
struct MenuBarUsageSection: View {
    @ObservedObject var runtime: LocalAPIRuntimeStore
    @ObservedObject var metrics: LocalAPIMetricsStore
    @ObservedObject var agentProcess: AgentProcess
    @ObservedObject var screenSharing: ScreenSharingMonitor
    @ObservedObject var settings: AgentSettings

    private var presentation: LocalAPIMetricsPresentation? {
        runtime.snapshot.isReachable ? metrics.snapshot.presentation : nil
    }

    private var isWaitingForMetrics: Bool {
        presentation == nil && (agentProcess.isRunning || agentProcess.isStarting)
    }

    private var showsScreenSharing: Bool {
        screenSharing.hasChecked || (settings.effectiveWebRTCEnabled && !ScreenRecordingPermission.isGranted)
    }

    var body: some View {
        if presentation != nil || isWaitingForMetrics || showsScreenSharing {
            VStack(alignment: .leading, spacing: 0) {
                if let presentation {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: LT.space16) {
                            LTMeter(label: "CPU", gauge: presentation.cpu)
                            LTMeter(label: "Memory", gauge: presentation.memory)
                            LTMeter(label: "Disk", gauge: presentation.disk)
                        }
                        NetworkFiguresRow(network: presentation.network, compact: true)
                    }
                    .padding(EdgeInsets(top: 6, leading: LT.space8, bottom: 2, trailing: LT.space8))
                } else if isWaitingForMetrics {
                    Text("Waiting for usage")
                        .font(LT.font(12))
                        .foregroundStyle(LT.text3)
                        .padding(.horizontal, LT.space8)
                        .frame(height: 28)
                }
                if showsScreenSharing {
                    ScreenSharingRow(screenSharing: screenSharing, settings: settings)
                        .padding(.top, presentation == nil ? 0 : LT.space4)
                }
            }
            LTSeparator()
        }
    }
}

/// Firing alerts, if any, under a plain "Alerts" title.
struct MenuBarAlertsSection: View {
    @ObservedObject var alerts: LocalAPIAlertsStore
    let consoleBaseURL: URL?

    var body: some View {
        let firing = alerts.snapshot.firingAlerts
        if !firing.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(L10n.menuAlerts)
                    .font(LT.font(12, weight: .semibold))
                    .foregroundStyle(LT.text2)
                    .padding(EdgeInsets(top: LT.space4, leading: LT.space8, bottom: 2, trailing: LT.space8))
                    .accessibilityAddTraits(.isHeader)
                AlertRowsView(firingAlerts: firing, consoleBaseURL: consoleBaseURL, limit: 4)
            }
            LTSeparator()
        }
    }
}
