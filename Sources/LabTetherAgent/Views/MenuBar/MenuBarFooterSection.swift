import SwiftUI

struct MenuBarFooterSection: View {
    @ObservedObject var metadata: LocalAPIMetadataStore
    let agentProcess: AgentProcess
    @ObservedObject var settings: AgentSettings
    @Environment(\.openWindow) private var openWindow
    @State private var hoveredItem: String?
    @State private var showUninstallConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
        HStack(spacing: LT.space12) {
            Button(L10n.menuAbout) {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "about")
            }
            .buttonStyle(.plain)
            .font(LT.inter(11))
            .foregroundColor(LT.textSecondary)

            Button(L10n.menuSetupWizard) {
                settings.hasCompletedOnboarding = false
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "onboarding")
            }
            .buttonStyle(.plain)
            .font(LT.inter(11))
            .foregroundColor(LT.textSecondary)

            Button(L10n.menuUninstall) {
                showUninstallConfirmation = true
            }
            .buttonStyle(.plain)
            .font(LT.inter(11))
            .foregroundColor(LT.bad)

            Spacer()
        }
        .padding(.horizontal, LT.space12)
        .padding(.bottom, LT.space4)

        HStack(spacing: LT.space4) {
            Image(systemName: "cube.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(LT.accent.opacity(0.5))
                .shadow(color: LT.accent.opacity(0.3), radius: 3)
            Text("LabTether")
                .font(LT.sora(9, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [LT.textMuted.opacity(0.7), LT.accent.opacity(0.5), LT.textMuted.opacity(0.7)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            Text("·")
                .font(LT.inter(9))
                .foregroundStyle(LT.textMuted.opacity(0.4))
            Text("v\(BundleHelper.appVersion)")
                .font(LT.mono(9))
                .foregroundStyle(LT.textMuted.opacity(0.5))

            if metadata.snapshot.updateAvailable,
               let latest = metadata.snapshot.latestVersion {
                LTCapsuleBadge(text: "→ \(latest)", color: LT.warn, withGlow: true)
            }

            Spacer()

            Button {
                NSApp.activate(ignoringOtherApps: true)
                agentProcess.forceKill()
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(hoveredItem == "quit" ? LT.bad : LT.textMuted.opacity(0.5))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(hoveredItem == "quit" ? LT.bad.opacity(0.15) : Color.clear)
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(hoveredItem == "quit" ? LT.bad.opacity(0.3) : Color.clear, lineWidth: 0.5)
                    )
                    .shadow(color: hoveredItem == "quit" ? LT.bad.opacity(0.3) : Color.clear, radius: 6)
            }
            .buttonStyle(.plain)
            .onHover { h in hoveredItem = h ? "quit" : nil }
            .animation(.easeInOut(duration: LT.animFast), value: hoveredItem)
        }
        .padding(.horizontal, LT.space12)
        .padding(.vertical, LT.space6)
        }
        .alert(L10n.uninstallTitle, isPresented: $showUninstallConfirmation) {
            Button(L10n.uninstallConfirm, role: .destructive) {
                UninstallManager.performUninstall(
                    agentProcess: agentProcess,
                    settings: settings
                )
            }
            Button(L10n.uninstallCancel, role: .cancel) {}
        } message: {
            Text(L10n.uninstallMessage)
        }
        .background(LT.panelGlass)
        .overlay(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Color.white.opacity(0.04), location: 0.3),
                    .init(color: Color.white.opacity(0.04), location: 0.7),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 0.5)
        }
    }
}
