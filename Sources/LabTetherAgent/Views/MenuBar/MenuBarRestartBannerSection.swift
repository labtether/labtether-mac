import SwiftUI

struct MenuBarRestartBannerSection: View {
    @ObservedObject var agentProcess: AgentProcess

    var body: some View {
        if agentProcess.needsRestart {
            LTGlassCard(glowColor: LT.warn) {
                HStack(spacing: LT.space8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(LT.warn)
                    Text("Settings changed")
                        .font(LT.inter(11, weight: .medium))
                        .foregroundStyle(LT.warn)
                    Spacer()
                    LTPillButton("Restart", icon: "arrow.clockwise", color: LT.warn) {
                        NSApp.activate(ignoringOtherApps: true)
                        agentProcess.restart()
                    }
                }
            }
        }
    }
}
