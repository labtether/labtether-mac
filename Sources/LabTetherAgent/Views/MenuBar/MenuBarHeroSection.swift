import SwiftUI

struct MenuBarHeroSection: View {
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
        case .ok: return LT.ok
        case .warn: return LT.warn
        case .accent: return LT.accent
        case .muted: return LT.textMuted
        case .bad: return LT.bad
        }
    }

    private var orbColor: Color { color(for: heroPresentation.tone) }
    private var orbBreatheDuration: Double { heroPresentation.breatheDuration }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: LT.space8) {
                LTHealthOrb(color: orbColor, size: 36, animated: false, breatheDuration: orbBreatheDuration)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: LT.space4) {
                        Text(heroPresentation.label)
                            .font(LT.sora(14, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [orbColor, orbColor.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        if let pid = status.pid {
                            LTCapsuleBadge(text: "PID \(pid)", color: LT.textMuted)
                        }
                    }

                    Text(heroPresentation.subtitle)
                        .font(LT.inter(11))
                        .foregroundStyle(LT.textMuted)
                        .lineLimit(1)
                }

                Spacer()

                heroAction
            }
            .padding(.horizontal, LT.space12)
            .padding(.top, LT.space12)
            .padding(.bottom, LT.space6)

            if let presentation = metrics.snapshot.presentation, runtime.snapshot.isReachable {
                HStack(spacing: LT.space8) {
                    miniGauge("CPU", gauge: presentation.cpu)
                    miniGauge("MEM", gauge: presentation.memory)
                    miniGauge("DISK", gauge: presentation.disk)
                }
                .padding(.horizontal, LT.space12)
                .padding(.bottom, LT.space8)
            }
        }
    }

    @ViewBuilder
    private var heroAction: some View {
        if agentProcess.isRunning {
            HStack(spacing: LT.space4) {
                LTMiniActionButton(icon: "stop.fill", color: LT.bad) {
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                    NSApp.activate(ignoringOtherApps: true)
                    agentProcess.stop()
                }
                LTMiniActionButton(icon: "arrow.clockwise", color: LT.warn) {
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                    NSApp.activate(ignoringOtherApps: true)
                    agentProcess.restart()
                }
            }
        } else if agentProcess.isStarting {
            LTSpinnerArc(color: LT.accent, size: 14)
        } else {
            LTMiniActionButton(icon: "play.fill", color: LT.ok) {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                NSApp.activate(ignoringOtherApps: true)
                agentProcess.start()
            }
            .opacity(canStartAgent ? 1 : 0.4)
            .allowsHitTesting(canStartAgent)
        }
    }

    private var canStartAgent: Bool {
        settings.isConfigured && settings.validationErrors().isEmpty && !agentProcess.isStarting
    }

    private func miniGauge(_ label: String, gauge: MetricGaugePresentation) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(LT.mono(8, weight: .semibold))
                .foregroundStyle(LT.textMuted)
                .frame(width: 24, alignment: .leading)
            LTMetricBar(fraction: gauge.fraction, color: gauge.color, height: 3, cornerRadius: 1.5)
            .frame(height: 10)
            Text(gauge.percentText)
                .font(LT.mono(8, weight: .medium))
                .foregroundStyle(gauge.color)
                .frame(width: 22, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }
}
