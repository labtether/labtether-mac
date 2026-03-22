import SwiftUI

struct MenuBarQuickActionsSection: View {
    @ObservedObject var status: AgentStatus
    @ObservedObject var settings: AgentSettings
    @ObservedObject var logBuffer: LogBuffer
    let onOpenConsole: () -> Void
    let onOpenDevicePage: () -> Void
    let onPopOut: () -> Void
    let onOpenLogWindow: () -> Void
    let onTestConnection: () -> Void
    let onCopyDiagnostics: () -> Void
    let onOpenSettings: () -> Void

    private var errorLogCount: Int {
        logBuffer.summary.errorCount
    }

    var body: some View {
        VStack(spacing: 0) {
            if settings.consoleURL != nil {
                LTMenuRow(icon: "globe", label: L10n.menuOpenConsole, showChevron: true, action: onOpenConsole)
                if !status.assetID.isEmpty {
                    LTMenuRow(icon: "desktopcomputer", label: L10n.menuViewDevice, showChevron: true, action: onOpenDevicePage)
                }
            }

            LTMenuRow(
                icon: "rectangle.portrait.and.arrow.right",
                label: L10n.menuPopOut,
                shortcut: "⌘⇧P",
                action: onPopOut
            )
            LTMenuRow(
                icon: "doc.text",
                label: L10n.menuViewLogs,
                shortcut: "⌘L",
                badge: errorLogCount > 0 ? "\(errorLogCount)" : nil,
                badgeColor: LT.bad,
                action: onOpenLogWindow
            )
            LTMenuRow(
                icon: "antenna.radiowaves.left.and.right",
                label: L10n.menuTestConnection,
                action: onTestConnection
            )
            LTMenuRow(icon: "doc.on.clipboard", label: L10n.menuCopyDiagnostics, shortcut: "⌘D", action: onCopyDiagnostics)
            LTMenuRow(icon: "gearshape", label: L10n.menuSettings, shortcut: "⌘,", action: onOpenSettings)
        }
        .padding(.horizontal, LT.space4)
        .padding(.bottom, LT.space4)
    }
}
