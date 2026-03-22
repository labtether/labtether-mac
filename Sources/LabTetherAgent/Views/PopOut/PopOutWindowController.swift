import AppKit
import SwiftUI

private struct PopOutRootView: View {
    @ObservedObject var controller: PopOutWindowController
    @ObservedObject var status: AgentStatus
    @ObservedObject var agentProcess: AgentProcess
    @ObservedObject var settings: AgentSettings
    @ObservedObject var screenSharing: ScreenSharingMonitor
    @ObservedObject var automation: PerformanceAutomationController
    let logBuffer: LogBuffer
    let apiClient: LocalAPIClient
    let sessionHistory: SessionHistoryTracker
    let bandwidthTracker: BandwidthTracker

    var body: some View {
        PopOutView(
            status: status,
            agentProcess: agentProcess,
            settings: settings,
            screenSharing: screenSharing,
            automation: automation,
            logBuffer: logBuffer,
            apiClient: apiClient,
            sessionHistory: sessionHistory,
            bandwidthTracker: bandwidthTracker
        )
        .environment(\.animationsActive, controller.panelVisible)
    }
}

// MARK: - PopOutWindowController

/// Manages the lifecycle of the floating pop-out dashboard panel.
///
/// Call `toggle(appState:)` from menu actions to show or hide the panel.
/// The panel uses `NSPanel` with `.nonactivatingPanel` so it floats above other
/// windows without stealing focus from the menu bar interaction.
@MainActor
final class PopOutWindowController: ObservableObject {
    private var panel: NSPanel?
    private var closeObserver: NSObjectProtocol?

    /// Published visibility flag. Use this to drive `animationsActive` in `PopOutView`.
    @Published var panelVisible = false

    // MARK: - Public API

    /// Toggles the panel: closes it if visible, opens it if hidden or nil.
    func toggle(appState: AppState) {
        if let panel, panel.isVisible {
            close()
        } else {
            show(appState: appState)
        }
    }

    /// Shows the panel, bringing an existing one to front or creating a new one.
    func show(appState: AppState) {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            panelVisible = true
            return
        }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
            styleMask: [
                .titled,
                .closable,
                .resizable,
                .fullSizeContentView,
                .nonactivatingPanel
            ],
            backing: .buffered,
            defer: true
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = NSColor(LT.bg)
        panel.level = .floating
        panel.hasShadow = true
        panel.minSize = NSSize(width: 380, height: 500)
        panel.title = "LabTether Agent"

        let hostView = NSHostingView(
            rootView: PopOutRootView(
                controller: self,
                status: appState.status,
                agentProcess: appState.agentProcess,
                settings: appState.settings,
                screenSharing: appState.screenSharing,
                automation: appState.performanceAutomation,
                logBuffer: appState.logBuffer,
                apiClient: appState.apiClient,
                sessionHistory: appState.sessionHistory,
                bandwidthTracker: appState.bandwidthTracker
            )
        )
        panel.contentView = hostView
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        panelVisible = true

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                if let closeObserver = self?.closeObserver {
                    NotificationCenter.default.removeObserver(closeObserver)
                    self?.closeObserver = nil
                }
                self?.panel = nil
                self?.panelVisible = false
            }
        }
    }

    /// Closes and releases the panel.
    func close() {
        panel?.close()
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            self.closeObserver = nil
        }
        panel = nil
        panelVisible = false
    }

    /// Whether the panel is currently visible on screen.
    var isVisible: Bool { panel?.isVisible ?? false }
}
