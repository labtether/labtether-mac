import SwiftUI

struct MenuBarSystemSection: View {
    @ObservedObject var runtime: LocalAPIRuntimeStore
    @ObservedObject var metrics: LocalAPIMetricsStore
    @ObservedObject var agentProcess: AgentProcess

    private var isMetricsLoading: Bool {
        !runtime.snapshot.isReachable && (agentProcess.isRunning || agentProcess.isStarting)
    }

    var body: some View {
        Group {
            if let presentation = metrics.snapshot.presentation, runtime.snapshot.isReachable {
                VStack(spacing: LT.space4) {
                    LTSectionHeader("SYSTEM")
                        .padding(.horizontal, LT.space12)
                    LTGlassCard {
                        MetricsView(presentation: presentation)
                            .padding(-LT.space12)
                    }
                    .padding(.horizontal, LT.space12)
                }
                .padding(.bottom, LT.space6)
            } else if isMetricsLoading {
                VStack(spacing: LT.space4) {
                    LTSectionHeader("SYSTEM")
                        .padding(.horizontal, LT.space12)
                    LTGlassCard {
                        MetricsLoadingView()
                            .padding(-LT.space12)
                    }
                    .padding(.horizontal, LT.space12)
                }
                .padding(.bottom, LT.space6)
            }
        }
    }
}
