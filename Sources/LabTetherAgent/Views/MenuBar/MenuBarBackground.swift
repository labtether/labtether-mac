import SwiftUI

struct MenuBarBackground: View {
    @ObservedObject var status: AgentStatus
    @ObservedObject var agentProcess: AgentProcess
    @ObservedObject var runtime: LocalAPIRuntimeStore

    private var orbColor: Color {
        switch heroPresentation.tone {
        case .ok: return LT.ok
        case .warn: return LT.warn
        case .accent: return LT.accent
        case .muted: return LT.textMuted
        case .bad: return LT.bad
        }
    }

    private var heroPresentation: AgentHeroPresentation {
        .resolve(agentProcess: agentProcess, status: status, runtime: runtime)
    }

    var body: some View {
        ZStack {
            LT.bg
            RadialGradient(
                colors: [orbColor.opacity(0.08), Color.clear],
                center: UnitPoint(x: 0.5, y: 0.06),
                startRadius: 0,
                endRadius: 220
            )
            RadialGradient(
                colors: [LT.accent.opacity(0.03), Color.clear],
                center: UnitPoint(x: 0.8, y: 0.7),
                startRadius: 0,
                endRadius: 160
            )
        }
    }
}
