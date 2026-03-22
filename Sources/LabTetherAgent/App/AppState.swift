import SwiftUI
import Combine

// MARK: - Debug Boot

private func debugBoot(_ message: @autoclosure () -> String) {
    guard ProcessInfo.processInfo.environment["LABTETHER_AGENT_DEBUG_BOOT"] == "1" else { return }
    fputs("[boot] \(message())\n", stderr)
}

// MARK: - App State

/// Eagerly initialized app state — not lazy like MenuBarExtra content.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    let settings = AgentSettings.shared
    let status = AgentStatus()
    let notifications = NotificationManager()
    let logBuffer = LogBuffer()
    let agentProcess: AgentProcess
    let screenSharing: ScreenSharingMonitor
    let apiClient = LocalAPIClient()
    let popOutController = PopOutWindowController()
    let performanceAutomation: PerformanceAutomationController
    let sessionHistory: SessionHistoryTracker
    let bandwidthTracker: BandwidthTracker
    private var bandwidthMetricsObserver: AnyCancellable?

    @Published var shouldShowOnboarding = false

    private var runningObserver: AnyCancellable?
    private var apiClientObserver: AnyCancellable?
    private var apiMetricsObserver: AnyCancellable?
    private var apiAlertsObserver: AnyCancellable?
    private var popOutVisibilityObserver: AnyCancellable?
    private var statusObserver: AnyCancellable?
    private var settingsObserver: AnyCancellable?
    private var performanceControlObserver: NSObjectProtocol?
    private var pendingMenuBarLabelRefresh = false
    private lazy var lastMenuBarLabelPresentation = menuBarLabelPresentation

    init() {
        debugBoot("AppState init begin")
        sessionHistory = SessionHistoryTracker(
            filePath: settings.appSupportDirectory.appendingPathComponent("session-history.json").path
        )
        bandwidthTracker = BandwidthTracker(
            filePath: settings.appSupportDirectory.appendingPathComponent("bandwidth-history.json").path
        )
        let proc = AgentProcess(
            status: status,
            settings: settings,
            notifications: notifications,
            logBuffer: logBuffer,
            sessionHistory: sessionHistory
        )
        self.agentProcess = proc
        self.screenSharing = ScreenSharingMonitor(notifications: notifications)
        self.performanceAutomation = PerformanceAutomationController(logBuffer: logBuffer)
        apiClient.notifications = notifications
        debugBoot("Settings snapshot autoStart=\(settings.autoStart) isConfigured=\(settings.isConfigured) hubURL=\(settings.hubURL) port=\(settings.agentPort)")

        // Start/stop API polling when agent process starts/stops
        runningObserver = proc.$isRunning
            .removeDuplicates()
            .sink { [weak self] running in
                guard let self = self else { return }
                if running {
                    self.apiClient.start(
                        port: self.settings.agentPort,
                        authToken: self.settings.localAPIAuthToken
                    )
                } else {
                    self.apiClient.stop()
                    self.bandwidthTracker.resetSession()
                }
            }

        apiClientObserver = apiClient.runtime.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleMenuBarLabelRefreshIfNeeded()
            }

        bandwidthMetricsObserver = apiClient.metrics.$snapshot
            .compactMap(\.current)
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.bandwidthTracker.accumulate(snapshot)
            }

        apiMetricsObserver = apiClient.metrics.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleMenuBarLabelRefreshIfNeeded()
            }

        apiAlertsObserver = apiClient.alerts.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleMenuBarLabelRefreshIfNeeded()
            }

        statusObserver = status.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleMenuBarLabelRefreshIfNeeded()
            }

        settingsObserver = settings.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleMenuBarLabelRefreshIfNeeded()
            }

        // Keep polling and animation lifecycle aware of detached panel visibility.
        popOutVisibilityObserver = popOutController.$panelVisible
            .removeDuplicates()
            .sink { [weak self] visible in
                self?.apiClient.setPanelVisible(visible)
                self?.screenSharing.setPanelVisible(visible)
                self?.status.setPanelVisible(visible)
            }

        // Auto-start if configured and enabled.
        if settings.autoStart {
            if settings.isConfigured {
                let validationErrors = settings.validationErrors()
                debugBoot("Auto-start validation errors: \(validationErrors)")
                if validationErrors.isEmpty {
                    // Delay slightly to let the app finish launching.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        debugBoot("Auto-start invoking AgentProcess.start()")
                        proc.start()
                    }
                } else {
                    status.markError(validationErrors[0])
                }
            } else {
                debugBoot("Auto-start skipped: settings not configured")
                status.markError("Not configured — open Settings to set Hub URL and token")
            }
        } else {
            debugBoot("Auto-start disabled")
        }

        // Trigger onboarding if not configured and hasn't been completed
        if !settings.isConfigured && !settings.hasCompletedOnboarding {
            shouldShowOnboarding = true
        }

        // Sync login item state
        if LoginItemManager.isEnabled != settings.startAtLogin {
            _ = LoginItemManager.setEnabled(settings.startAtLogin)
        }

        // Start monitoring Screen Sharing status
        screenSharing.startMonitoring()
        installPerformanceControlObserver()
        debugBoot("AppState init complete")
    }

    func refreshMenuBarLabel() {
        lastMenuBarLabelPresentation = menuBarLabelPresentation
        LTPerformanceSignposts.emitMenuBarLabelRefresh(changed: true, menuVisible: apiClient.isMenuVisible)
        objectWillChange.send()
    }

    private func scheduleMenuBarLabelRefreshIfNeeded() {
        guard !pendingMenuBarLabelRefresh else { return }
        pendingMenuBarLabelRefresh = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingMenuBarLabelRefresh = false
            self.refreshMenuBarLabelIfNeeded()
        }
    }

    private func refreshMenuBarLabelIfNeeded() {
        let nextPresentation = menuBarLabelPresentation
        guard nextPresentation != lastMenuBarLabelPresentation else {
            LTPerformanceSignposts.emitMenuBarLabelRefresh(changed: false, menuVisible: apiClient.isMenuVisible)
            return
        }
        lastMenuBarLabelPresentation = nextPresentation
        LTPerformanceSignposts.emitMenuBarLabelRefresh(changed: true, menuVisible: apiClient.isMenuVisible)

        // Prevent label redraw churn while the menu window is open.
        // SwiftUI can collapse MenuBarExtra(.window) when the label
        // tree is refreshed mid-interaction.
        if !apiClient.isMenuVisible {
            objectWillChange.send()
        }
    }

    var menuBarLabelPresentation: MenuBarLabelPresentation {
        MenuBarLabelPresentation.resolve(
            displayMode: settings.menuBarDisplayMode,
            statusState: status.state,
            hubConnectionState: apiClient.hubConnectionState,
            isReachable: apiClient.isReachable,
            metrics: apiClient.metrics.snapshot.current,
            hasFiringAlerts: !apiClient.alerts.snapshot.firingAlerts.isEmpty
        )
    }

    /// Visual state for the menu bar icon, reflecting health thresholds and hub status.
    var menuBarIconKind: MenuBarIconKind {
        menuBarLabelPresentation.kind
    }

    private func installPerformanceControlObserver() {
        performanceControlObserver = DistributedNotificationCenter.default().addObserver(
            forName: .ltPerformanceControlCommand,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            Task { @MainActor in
                self.handlePerformanceControl(notification.userInfo ?? [:])
            }
        }
    }

    private func handlePerformanceControl(_ userInfo: [AnyHashable: Any]) {
        guard let command = userInfo["command"] as? String else { return }
        debugBoot("Performance control command: \(command)")
        switch command {
        case "show_popout":
            popOutController.show(appState: self)
        case "run_scroll_profile":
            let durationSeconds = (userInfo["duration_seconds"] as? NSNumber)?.doubleValue ?? 12
            popOutController.show(appState: self)
            performanceAutomation.runPopOutScrollProfile(durationSeconds: durationSeconds)
        case "run_log_burst":
            let durationSeconds = (userInfo["duration_seconds"] as? NSNumber)?.doubleValue ?? 12
            let linesPerBatch = (userInfo["lines_per_batch"] as? NSNumber)?.intValue ?? 40
            popOutController.show(appState: self)
            performanceAutomation.runLogBurst(durationSeconds: durationSeconds, linesPerBatch: linesPerBatch)
        case "run_scroll_and_log_burst":
            let durationSeconds = (userInfo["duration_seconds"] as? NSNumber)?.doubleValue ?? 12
            let linesPerBatch = (userInfo["lines_per_batch"] as? NSNumber)?.intValue ?? 40
            popOutController.show(appState: self)
            performanceAutomation.runPopOutScrollProfile(durationSeconds: durationSeconds)
            performanceAutomation.runLogBurst(durationSeconds: durationSeconds, linesPerBatch: linesPerBatch)
        case "cancel_profile_automation":
            performanceAutomation.cancelAll()
        default:
            break
        }
    }
}

private extension Notification.Name {
    static let ltPerformanceControlCommand = Notification.Name("LabTetherPerformanceControlCommand")
}
