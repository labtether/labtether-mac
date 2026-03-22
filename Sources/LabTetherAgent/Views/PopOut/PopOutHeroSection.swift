import SwiftUI

struct PopOutHeroSection: View {
    @ObservedObject var status: AgentStatus
    @ObservedObject var agentProcess: AgentProcess
    @ObservedObject var settings: AgentSettings
    @ObservedObject var runtime: LocalAPIRuntimeStore
    @ObservedObject var metrics: LocalAPIMetricsStore

    private var heroPresentation: AgentHeroPresentation {
        .resolve(agentProcess: agentProcess, status: status, runtime: runtime)
    }

    private func color(for tone: AgentHeroTone) -> Color {
        switch tone {
        case .ok:
            return LT.ok
        case .warn:
            return LT.warn
        case .accent:
            return LT.accent
        case .muted:
            return LT.textMuted
        case .bad:
            return LT.bad
        }
    }

    private var orbColor: Color {
        color(for: heroPresentation.tone)
    }

    private var orbBreatheDuration: Double {
        heroPresentation.breatheDuration
    }

    private var canStartAgent: Bool {
        settings.isConfigured && settings.validationErrors().isEmpty && !agentProcess.isStarting
    }

    var body: some View {
        LTGlassCard(glowColor: orbColor) {
            HStack(spacing: LT.space12) {
                ZStack {
                    RoundedRectangle(cornerRadius: LT.radiusMd, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [orbColor.opacity(0.08), Color.clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: 40
                            )
                        )
                        .frame(width: 60, height: 60)

                    LTHealthOrb(color: orbColor, size: 48, animated: false, breatheDuration: orbBreatheDuration)
                }
                .frame(width: 60, height: 60)

                VStack(alignment: .leading, spacing: LT.space4) {
                    Text(heroPresentation.label)
                        .font(LT.sora(20, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [orbColor, orbColor.opacity(0.65)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    Text(heroPresentation.subtitle)
                        .font(LT.inter(12))
                        .foregroundStyle(LT.textMuted)

                    HStack(spacing: LT.space4) {
                        if let pid = status.pid {
                            LTCapsuleBadge(text: "PID \(pid)", color: LT.accent)
                        }
                        if let uptime = status.uptime {
                            LTCapsuleBadge(text: uptime, color: LT.textMuted)
                        }
                        if runtime.snapshot.isReachable, let relativeSyncText = metrics.snapshot.presentation?.network.relativeSyncText {
                            LTCapsuleBadge(text: relativeSyncText, color: LT.ok)
                        }
                    }
                }

                Spacer()

                VStack(spacing: LT.space4) {
                    if agentProcess.isRunning {
                        LTMiniActionButton(icon: "arrow.clockwise", color: LT.warn) {
                            NSApp.activate(ignoringOtherApps: true)
                            agentProcess.restart()
                        }
                        LTMiniActionButton(icon: "stop.fill", color: LT.bad) {
                            NSApp.activate(ignoringOtherApps: true)
                            agentProcess.stop()
                        }
                    } else if agentProcess.isStarting {
                        LTSpinnerArc(color: LT.accent, size: 18)
                    } else {
                        LTMiniActionButton(icon: "play.fill", color: LT.ok) {
                            NSApp.activate(ignoringOtherApps: true)
                            agentProcess.start()
                        }
                        .opacity(canStartAgent ? 1 : 0.4)
                        .allowsHitTesting(canStartAgent)
                    }
                }
            }
        }
    }
}
