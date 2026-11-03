import AppKit
import SwiftUI

/// "Connected" with the Hub host and uptime, the ⋯ menu and the one rose button.
struct PopOutHeaderSection: View {
    @ObservedObject var status: AgentStatus
    @ObservedObject var agentProcess: AgentProcess
    @ObservedObject var settings: AgentSettings
    @ObservedObject var runtime: LocalAPIRuntimeStore
    let onOpenConsole: () -> Void
    let onOpenDevicePage: () -> Void
    @Environment(\.openWindow) private var openWindow

    private var hero: AgentHeroPresentation {
        .resolve(agentProcess: agentProcess, status: status, runtime: runtime, settings: settings)
    }

    private var canStartAgent: Bool {
        settings.isConfigured && settings.validationErrors().isEmpty && !agentProcess.isStarting
    }

    var body: some View {
        HStack(alignment: .top, spacing: LT.space6) {
            AgentStatusText(hero: hero, needsRestart: agentProcess.needsRestart && agentProcess.isRunning, titleSize: 16)
            Spacer(minLength: LT.space8)
            LTMoreMenu(label: "More: agent controls, device page, logs, settings", bordered: true) {
                menuItems
            }
            if settings.consoleURL != nil {
                Button(L10n.menuOpenConsole, action: onOpenConsole)
                    .buttonStyle(LTPrimaryButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        if agentProcess.isRunning {
            Button("Restart agent") {
                NSApp.activate(ignoringOtherApps: true)
                agentProcess.restart()
            }
            Button("Stop agent") {
                NSApp.activate(ignoringOtherApps: true)
                agentProcess.stop()
            }
        } else {
            Button("Start agent") {
                NSApp.activate(ignoringOtherApps: true)
                agentProcess.start()
            }
            .disabled(!canStartAgent)
        }
        Divider()
        if settings.consoleURL != nil && !status.assetID.isEmpty {
            Button(L10n.menuViewDevice, action: onOpenDevicePage)
        }
        Button(L10n.menuViewLogs) {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "log-viewer")
        }
        Button(L10n.menuSettings) {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "settings")
        }
    }
}
