import AppKit
import SwiftUI

/// Status word, the Hub host and uptime, and the agent controls.
struct MenuBarHeaderSection: View {
    @ObservedObject var status: AgentStatus
    @ObservedObject var agentProcess: AgentProcess
    @ObservedObject var settings: AgentSettings
    @ObservedObject var runtime: LocalAPIRuntimeStore

    private var hero: AgentHeroPresentation {
        .resolve(agentProcess: agentProcess, status: status, runtime: runtime, settings: settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                AgentStatusText(hero: hero, needsRestart: agentProcess.needsRestart && agentProcess.isRunning, titleSize: 14)
                Spacer(minLength: LT.space8)
                AgentControlButtons(agentProcess: agentProcess, settings: settings)
            }
            .padding(EdgeInsets(top: LT.space8, leading: LT.space8, bottom: LT.space8, trailing: LT.space4))

            if let fix = connectFix {
                Text(fix)
                    .font(LT.font(12))
                    .foregroundStyle(LT.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, LT.space8)
                    .padding(.bottom, LT.space8)
            }
        }
    }

    /// The fix for the agent's last connect failure, shown while reconnecting.
    private var connectFix: String? {
        guard runtime.snapshot.hubConnectionState == "connecting" else { return nil }
        return HubConnectReason(code: runtime.snapshot.lastErrorReason)?.fix
    }
}

/// The status word with its one line underneath. A problem turns the line amber or red.
struct AgentStatusText: View {
    let hero: AgentHeroPresentation
    var needsRestart = false
    var titleSize: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: titleSize > 14 ? 2 : 0) {
            Text(hero.label)
                .font(LT.font(titleSize, weight: .semibold))
                .foregroundStyle(LT.text)
            if !line.isEmpty {
                Text(line)
                    .font(LT.font(12).monospacedDigit())
                    .foregroundStyle(lineColor)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var line: String {
        needsRestart ? L10n.settingsRestartRequired : hero.subtitle
    }

    private var lineColor: Color {
        if needsRestart { return LT.warnText }
        switch hero.tone {
        case .bad: return LT.badText
        case .warn: return LT.warnText
        default: return LT.text3
        }
    }
}

/// Restart and Stop while the agent runs, Start when it is stopped.
struct AgentControlButtons: View {
    @ObservedObject var agentProcess: AgentProcess
    @ObservedObject var settings: AgentSettings

    private var canStartAgent: Bool {
        settings.isConfigured && settings.validationErrors().isEmpty && !agentProcess.isStarting
    }

    var body: some View {
        if agentProcess.isRunning {
            LTQuietIconButton(systemImage: "arrow.clockwise", label: "Restart agent") {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                NSApp.activate(ignoringOtherApps: true)
                agentProcess.restart()
            }
            LTQuietIconButton(systemImage: "stop", label: "Stop agent") {
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                NSApp.activate(ignoringOtherApps: true)
                agentProcess.stop()
            }
        } else if agentProcess.isStarting {
            LTSpinnerArc(color: LT.text3, size: 14)
                .frame(width: 28, height: 28)
        } else {
            LTQuietIconButton(systemImage: "play", label: "Start agent") {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                NSApp.activate(ignoringOtherApps: true)
                agentProcess.start()
            }
            .disabled(!canStartAgent)
            .opacity(canStartAgent ? 1 : 0.45)
        }
    }
}
