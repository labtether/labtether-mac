import SwiftUI

struct PopOutActionBarSection: View {
    @ObservedObject var status: AgentStatus
    @ObservedObject var settings: AgentSettings
    let onOpenConsole: () -> Void
    let onOpenDevicePage: () -> Void
    @Environment(\.openWindow) private var openWindow
    @State private var consoleButtonHovered = false

    var body: some View {
        LTGlassCard {
            HStack(spacing: LT.space8) {
                if settings.consoleURL != nil {
                    Button(action: onOpenConsole) {
                        HStack(spacing: LT.space4) {
                            Image(systemName: "globe")
                                .font(.system(size: 10, weight: .semibold))
                                .rotationEffect(.degrees(consoleButtonHovered ? 20 : 0))
                            Text("Console")
                                .font(LT.inter(11, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, LT.space12)
                        .padding(.vertical, LT.space4 + 2)
                        .background(
                            Capsule().fill(
                                LinearGradient(
                                    colors: consoleButtonHovered
                                        ? [LT.accent, LT.accent.opacity(0.8), Color(hex: "#ff3399")]
                                        : [LT.accent, LT.accent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        )
                        .shadow(color: LT.accent.opacity(consoleButtonHovered ? 0.6 : 0.4), radius: consoleButtonHovered ? 12 : 8)
                        .shadow(color: LT.accent.opacity(consoleButtonHovered ? 0.3 : 0.2), radius: 16)
                        .scaleEffect(consoleButtonHovered ? 1.04 : 1.0)
                    }
                    .buttonStyle(LTPressButtonStyle())
                    .onHover { consoleButtonHovered = $0 }
                    .animation(.easeInOut(duration: LT.animNormal), value: consoleButtonHovered)

                    if !status.assetID.isEmpty {
                        LTPillButton("Device", icon: "desktopcomputer", color: LT.ok, action: onOpenDevicePage)
                    }
                }

                LTPillButton("Logs", icon: "doc.text", color: LT.textSecondary) {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "log-viewer")
                }

                LTPillButton("Settings", icon: "gearshape", color: LT.textSecondary) {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "settings")
                }

                Spacer()
            }
        }
    }
}
