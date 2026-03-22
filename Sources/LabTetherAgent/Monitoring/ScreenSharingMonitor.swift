import AppKit
import Foundation
import Network

/// Monitors whether macOS Screen Sharing (VNC on port 5900) is enabled and
/// whether the current user has full control privileges (not just observe).
/// Publishes state changes so the menu bar can prompt the user to fix issues.
@MainActor
final class ScreenSharingMonitor: ObservableObject {
    @Published var isEnabled: Bool = false
    @Published var hasControlAccess: Bool = true // assume true until checked
    @Published var hasChecked: Bool = false

    private var timer: Timer?
    private let visibleCheckInterval: TimeInterval = 30
    private let hiddenCheckInterval: TimeInterval = 180
    private var hasNotifiedDisabled = false
    private var hasNotifiedObserveOnly = false
    private var latestIsEnabled = false
    private var latestHasControlAccess = true
    private var latestHasChecked = false
    private let visibility = VisibilityGate()

    private weak var notifications: NotificationManager?

    init(notifications: NotificationManager? = nil) {
        self.notifications = notifications
    }

    func startMonitoring() {
        check()
        scheduleTimer()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    /// Mirrors menu visibility so we can suppress hidden-surface redraw churn.
    func setMenuVisible(_ visible: Bool) {
        guard visibility.setMenuVisible(visible) else { return }
        handleVisibilityTransition(becameVisible: visible)
    }

    /// Mirrors pop-out panel visibility so surface state matches operator intent.
    func setPanelVisible(_ visible: Bool) {
        guard visibility.setPanelVisible(visible) else { return }
        handleVisibilityTransition(becameVisible: visible)
    }

    func check() {
        Task {
            let enabled = await Self.probePort5900()
            let wasEnabled = self.latestIsEnabled
            let hadChecked = self.latestHasChecked
            self.latestIsEnabled = enabled
            self.latestHasChecked = true

            // Check control privileges when Screen Sharing is enabled
            if enabled {
                let control = await Self.checkControlPrivileges()
                let wasControl = self.latestHasControlAccess
                self.latestHasControlAccess = control

                // Notify once when we detect observe-only mode
                if !control && !self.hasNotifiedObserveOnly && wasControl {
                    self.hasNotifiedObserveOnly = true
                    self.notifications?.notify(.screenSharingObserveOnly)
                }
                if control {
                    self.hasNotifiedObserveOnly = false
                }
            } else {
                self.latestHasControlAccess = true // reset — irrelevant when disabled
            }

            // Notify once when we first detect Screen Sharing is off
            if !enabled && !self.hasNotifiedDisabled && (!hadChecked || wasEnabled) {
                self.hasNotifiedDisabled = true
                self.notifications?.notify(.screenSharingDisabled)
            }
            if enabled {
                self.hasNotifiedDisabled = false
            }

            if self.surfaceVisible {
                self.applyLatestToPublishedState()
            }
        }
    }

    private var surfaceVisible: Bool {
        visibility.anySurfaceVisible
    }

    private func handleVisibilityTransition(becameVisible: Bool) {
        if becameVisible {
            applyLatestToPublishedState()
            check()
        }
        scheduleTimer()
    }

    private func applyLatestToPublishedState() {
        assignIfChanged(\.isEnabled, latestIsEnabled)
        assignIfChanged(\.hasControlAccess, latestHasControlAccess)
        assignIfChanged(\.hasChecked, latestHasChecked)
    }

    private func assignIfChanged<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<ScreenSharingMonitor, T>, _ value: T) {
        if self[keyPath: keyPath] != value {
            self[keyPath: keyPath] = value
        }
    }

    private var currentCheckInterval: TimeInterval {
        surfaceVisible ? visibleCheckInterval : hiddenCheckInterval
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: currentCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
    }

    /// Opens System Settings > General > Sharing.
    static func openSharingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Sharing-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Grants full ARD control privileges using the kickstart tool (requires admin password).
    static func grantControlAccess() {
        let kickstart = "/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart"
        let user = NSUserName()
        // Quote the username for shell safety (defensive; macOS usernames are typically simple).
        let escapedUser = user.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        do shell script "\\\"\(kickstart)\\\" -configure -access -on -users '\(escapedUser)' -privs -all -restart -agent" with administrator privileges
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    /// Checks whether the current user has ARD control (not just observe) privileges
    /// by reading the naprivs attribute via dscl. Bit 1 (0x2) = Control and Observe.
    nonisolated private static func checkControlPrivileges() async -> Bool {
        let user = NSUserName()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        process.arguments = [".", "-read", "/Users/\(user)", "dsAttrTypeNative:naprivs"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            // If dscl fails, check if ARD_AllLocalUsers is set instead
            return checkAllLocalUsers()
        }

        guard process.terminationStatus == 0 else {
            // No naprivs key — user may not be in the ARD user list.
            // Check if "all local users" mode is active.
            return checkAllLocalUsers()
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return false }

        // Parse "dsAttrTypeNative:naprivs: <value>"
        let parts = output.split(separator: ":", maxSplits: 2)
        guard parts.count >= 3 else { return false }
        let valStr = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let privs = Int64(valStr) else { return false }

        let controlBit: Int64 = 0x2
        return privs & controlBit != 0
    }

    /// Checks if ARD is configured for all local users (fallback when per-user naprivs is absent).
    nonisolated private static func checkAllLocalUsers() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", "/Library/Preferences/com.apple.RemoteManagement", "ARD_AllLocalUsers"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }

        guard process.terminationStatus == 0 else { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return false }
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    /// Probes TCP port 5900 on localhost to check if Screen Sharing is running.
    nonisolated private static func probePort5900() async -> Bool {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: .ipv4(.loopback),
                port: 5900,
                using: .tcp
            )

            // Use a class to hold mutable state safely across closures
            final class ResumeGuard: @unchecked Sendable {
                private var _resumed = false
                private let lock = NSLock()

                func tryResume() -> Bool {
                    lock.lock()
                    defer { lock.unlock() }
                    if _resumed { return false }
                    _resumed = true
                    return true
                }
            }
            let guard_ = ResumeGuard()

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if guard_.tryResume() {
                        connection.cancel()
                        continuation.resume(returning: true)
                    }
                case .failed, .cancelled:
                    if guard_.tryResume() {
                        continuation.resume(returning: false)
                    }
                case .waiting:
                    if guard_.tryResume() {
                        connection.cancel()
                        continuation.resume(returning: false)
                    }
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .utility))

            // Timeout after 2 seconds
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if guard_.tryResume() {
                    connection.cancel()
                    continuation.resume(returning: false)
                }
            }
        }
    }
}
