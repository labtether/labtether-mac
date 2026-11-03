import SwiftUI

struct MenuBarQuickActionsSection: View {
    @ObservedObject var status: AgentStatus
    @ObservedObject var settings: AgentSettings
    let onOpenConsole: () -> Void
    let onOpenDevicePage: () -> Void
    let onPopOut: () -> Void
    let onOpenLogWindow: () -> Void
    let onTestConnection: () -> Void
    let onCopyDiagnostics: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if settings.isConfigured, settings.consoleURL != nil {
                LTMenuItem(icon: "globe", label: L10n.menuOpenConsole, action: onOpenConsole)
                if !status.assetID.isEmpty {
                    LTMenuItem(icon: "lt.display", label: L10n.menuViewDevice, action: onOpenDevicePage)
                }
            }
            LTMenuItem(icon: "arrow.up.right.square", label: L10n.menuPopOut, shortcut: "⌘⇧P", action: onPopOut)
            LTMenuItem(icon: "doc.text", label: L10n.menuViewLogs, shortcut: "⌘L", action: onOpenLogWindow)
            LTMenuItem(icon: "dot.radiowaves.left.and.right", label: L10n.menuTestConnection, action: onTestConnection)
            LTMenuItem(icon: "lt.clipboard", label: L10n.menuCopyDiagnostics, shortcut: "⌘D", action: onCopyDiagnostics)
            LTMenuItem(icon: "slider.horizontal.3", label: L10n.menuSettings, shortcut: "⌘,", action: onOpenSettings)
        }
    }
}
