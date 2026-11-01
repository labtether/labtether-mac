import Foundation
import Combine

private func debugBootProcess(_ message: @autoclosure () -> String) {
    guard ProcessInfo.processInfo.environment["LABTETHER_AGENT_DEBUG_BOOT"] == "1" else { return }
    fputs("[proc] \(message())\n", stderr)
}

/// Manages the Go agent binary lifecycle: start, stop, restart.
/// Reads stdout/stderr and feeds lines through the LogParser.
@MainActor
final class AgentProcess: ObservableObject {
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var pendingRestart = false
    private(set) var crashRestartTask: Task<Void, Never>?
    private let childOwnership: AgentChildOwnership?
    private let makeProcess: () -> Process
    private let agentBinaryPath: () -> String
    private let waitForCrashRestart: @MainActor (TimeInterval) async -> Void

    let status: AgentStatus
    let settings: AgentSettings
    let notifications: NotificationManager
    let logBuffer: LogBuffer
    let sessionHistory: SessionHistoryTracker

    @Published var isRunning: Bool = false
    @Published var isStarting: Bool = false
    @Published var needsRestart: Bool = false

    private var userInitiatedStop = false
    let crashCoordinator = CrashRestartCoordinator()

    private var settingsObserver: AnyCancellable?

    private struct ParsedLogLine: Sendable {
        let raw: String
        let event: AgentEvent
    }

    init(
        status: AgentStatus,
        settings: AgentSettings,
        notifications: NotificationManager,
        logBuffer: LogBuffer,
        sessionHistory: SessionHistoryTracker,
        makeProcess: @escaping () -> Process = { Process() },
        agentBinaryPath: @escaping () -> String = { BundleHelper.agentBinaryPath },
        waitForCrashRestart: @escaping @MainActor (TimeInterval) async -> Void = { delay in
            try? await Task.sleep(for: .seconds(delay))
        }
    ) {
        self.status = status
        self.settings = settings
        self.notifications = notifications
        self.logBuffer = logBuffer
        self.sessionHistory = sessionHistory
        self.childOwnership = settings.stateLocation.map { AgentChildOwnership(location: $0) }
        self.makeProcess = makeProcess
        self.agentBinaryPath = agentBinaryPath
        self.waitForCrashRestart = waitForCrashRestart

        // Observe settings changes to show "restart required" when running
        settingsObserver = settings.$settingsVersion
            .dropFirst()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.isRunning {
                    self.needsRestart = true
                }
                // Reset crash tracking so new config gets fresh start
                self.crashCoordinator.reset()
            }
    }

    /// Immediately kill the agent process (used during app quit).
    func forceKill() {
        cancelCrashRestart()
        crashCoordinator.cancelCooldown()
        userInitiatedStop = true
        pendingRestart = false
        guard let proc = process else {
            settings.cleanupEphemeralSecrets()
            return
        }
        if proc.isRunning {
            kill(proc.processIdentifier, SIGKILL)
        }
        childOwnership?.retire(proc)
        process = nil
        isRunning = false
        isStarting = false
        settings.cleanupEphemeralSecrets()
    }

    func start(resetCrashHistory: Bool = true) {
        debugBootProcess("start called resetCrashHistory=\(resetCrashHistory) process_nil=\(process == nil) isStarting=\(isStarting)")
        guard process == nil && !isStarting else { return }
        cancelCrashRestart()

        if resetCrashHistory {
            crashCoordinator.reset()
        } else {
            crashCoordinator.cancelCooldown()
        }

        // A saved token belongs to the Hub that issued it. Remove it before
        // launching against a different Hub so it is never sent there.
        let droppedOtherHubCredentials: Bool
        do {
            droppedOtherHubCredentials = try settings.dropCredentialsFromOtherHub()
        } catch {
            status.markError("The token saved for the previous Hub could not be removed. The agent was not started.")
            logBuffer.append("[app] Could not remove the previous Hub's token: \(error.localizedDescription)")
            return
        }
        if droppedOtherHubCredentials {
            logBuffer.append("[app] The Hub address changed, so the token saved for the previous Hub was removed.")
        }

        // Validate config before launching
        guard settings.isConfigured else {
            debugBootProcess("start aborted: settings.isConfigured=false")
            status.markError(droppedOtherHubCredentials
                ? "The Hub changed. Add an enrollment token from the new Hub in Settings."
                : "Hub URL and token required — open Settings to configure")
            return
        }
        let validationErrors = settings.validationErrors()
        if !validationErrors.isEmpty {
            debugBootProcess("start aborted: validationErrors=\(validationErrors)")
            for issue in validationErrors {
                logBuffer.append("[app] Configuration error: \(issue)")
            }
            status.markError(validationErrors[0])
            return
        }

        let binaryPath = agentBinaryPath()
        debugBootProcess("binaryPath=\(binaryPath)")
        guard binaryPath.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: binaryPath) else {
            debugBootProcess("start aborted: binary not executable")
            status.markError("Agent binary not found at \(binaryPath)")
            return
        }

        userInitiatedStop = false
        needsRestart = false
        isStarting = true
        status.prepareForLaunch(
            hubURL: settings.normalizedHubWebSocketURL() ?? settings.hubURL
        )

        do { try childOwnership?.recover(binaryPath: binaryPath) }
        catch {
            isStarting = false
            status.markError("Saved child ownership could not be verified; no unknown process was stopped.")
            return
        }

        let proc = makeProcess()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        do {
            proc.environment = try settings.buildEnvironment()
        } catch {
            debugBootProcess("start aborted: buildEnvironment error=\(error.localizedDescription)")
            isStarting = false
            status.markError(error.localizedDescription)
            logBuffer.append("[app] Configuration error: \(error.localizedDescription)")
            return
        }

        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardOutput = stdout
        proc.standardError = stderr
        self.stdoutPipe = stdout
        self.stderrPipe = stderr

        // Handle process termination
        proc.terminationHandler = { [weak self] proc in
            Task { @MainActor [weak self] in
                self?.handleTermination(of: proc)
            }
        }

        do {
            try proc.run()
            self.process = proc
            try childOwnership?.register(proc, binaryPath: binaryPath)
        } catch {
            if proc.isRunning { kill(proc.processIdentifier, SIGKILL) }
            debugBootProcess("start failed to run process: \(error.localizedDescription)")
            isStarting = false
            settings.cleanupEphemeralSecrets()
            status.markError("Failed to launch: \(error.localizedDescription)")
            return
        }
        debugBootProcess("process launched pid=\(proc.processIdentifier)")

        self.process = proc
        self.isRunning = true
        self.isStarting = false
        status.markStarting(pid: proc.processIdentifier)

        logBuffer.append("[app] Agent started (PID \(proc.processIdentifier))")

        // Read stdout in background — handler receives all lines from a single
        // availableData read, dispatched in one Task to reduce allocations.
        readPipe(stdout) { [weak self, weak proc] lines in
            Task { @MainActor [weak self, weak proc] in
                guard let self, let proc, self.process === proc else { return }
                self.handleParsedLines(lines)
            }
        }
        // Read stderr in background (Go logs to stderr by default)
        readPipe(stderr) { [weak self, weak proc] lines in
            Task { @MainActor [weak self, weak proc] in
                guard let self, let proc, self.process === proc else { return }
                self.handleParsedLines(lines)
            }
        }
    }

    func stop(forRestart: Bool = false) {
        cancelCrashRestart()
        userInitiatedStop = true
        pendingRestart = forRestart
        crashCoordinator.cancelCooldown()
        isStarting = false
        guard let proc = process, proc.isRunning else {
            if let process { childOwnership?.retire(process) }
            process = nil
            isRunning = false
            settings.cleanupEphemeralSecrets()
            status.markStopped()
            pendingRestart = false
            if forRestart { start() }
            return
        }

        logBuffer.append("[app] Stopping agent...")

        // Graceful shutdown: SIGINT → wait 5s → SIGTERM → wait 2s → SIGKILL
        proc.interrupt() // SIGINT first (Go handles it gracefully)

        Task.detached {
            try? await Task.sleep(for: .seconds(5))
            if proc.isRunning {
                kill(proc.processIdentifier, SIGTERM)
                try? await Task.sleep(for: .seconds(2))
                if proc.isRunning {
                    kill(proc.processIdentifier, SIGKILL)
                }
            }
        }
    }

    func restart() {
        guard process != nil else {
            start()
            return
        }
        stop(forRestart: true)
    }

    /// The OS may queue termination after stop/start has installed a new child.
    /// Only the exact current Process owns runtime state and ephemeral secrets.
    func handleTermination(of proc: Process) {
        guard process === proc else { childOwnership?.retire(proc); return }
        childOwnership?.retire(proc)
        let previousState = status.state
        let wasUserStop = userInitiatedStop
        let shouldRestart = pendingRestart
        pendingRestart = false
        process = nil
        isRunning = false
        isStarting = false
        stdoutPipe = nil
        stderrPipe = nil
        settings.cleanupEphemeralSecrets()

        if wasUserStop || shouldRestart || proc.terminationStatus == 0 {
            status.markStopped()
        } else {
            status.markError("Exited with code \(proc.terminationStatus)")
        }
        if previousState == .connected && !wasUserStop && !shouldRestart {
            notifications.notify(.disconnected)
        }
        if shouldRestart {
            start()
        } else if proc.terminationStatus != 0 && !wasUserStop {
            attemptCrashRestart()
        }
    }

    private func attemptCrashRestart() {
        cancelCrashRestart()
        switch crashCoordinator.recordCrash() {
        case .enterCooldown(let duration):
            logBuffer.append("[app] Crash loop detected (\(CrashRestartCoordinator.maxCrashRestarts) crashes in \(Int(CrashRestartCoordinator.crashWindowSeconds))s). Will retry in \(Int(duration / 60)) minutes.")
            notifications.notify(.crashLoopDetected)

            crashCoordinator.scheduleCooldown(duration: duration) { [weak self] in
                guard let self else { return }
                self.logBuffer.append("[app] Crash cooldown expired. Attempting restart...")
                if self.process == nil && !self.userInitiatedStop {
                    self.start(resetCrashHistory: false)
                }
            }

        case .restart(let delay):
            let attempt = crashCoordinator.currentAttempt
            logBuffer.append("[app] Agent crashed. Auto-restarting in \(Int(delay))s (attempt \(attempt)/\(CrashRestartCoordinator.maxCrashRestarts))...")
            notifications.notify(.crashRestart(attempt: attempt))

            let wait = waitForCrashRestart
            crashRestartTask = Task { [weak self] in
                await wait(delay)
                // A retired delay must never act on a later child or cooldown.
                guard !Task.isCancelled, let self else { return }
                self.crashRestartTask = nil
                if self.process == nil && !self.userInitiatedStop {
                    self.start(resetCrashHistory: false)
                }
            }
        }
    }

    private func cancelCrashRestart() {
        crashRestartTask?.cancel()
        crashRestartTask = nil
    }

    private func handleParsedLines(_ lines: [ParsedLogLine]) {
        guard !lines.isEmpty else { return }
        logBuffer.appendBatch(lines.map(\.raw))

        for line in lines {
            let previousState = status.state
            status.handleEvent(line.event)
            sessionHistory.handleEvent(line.event, timestamp: Date())

            // Fire notifications on significant state transitions
            switch line.event {
            case .connected:
                if previousState != .connected {
                    notifications.notify(.connected)
                    // Reset crash counter on successful connection
                    crashCoordinator.reset()
                }
            case .reconnecting:
                if previousState == .connected {
                    notifications.notify(.connectionLost)
                }
            case .enrolled:
                notifications.notify(.enrolled)
            case .enrollmentTokenConsumed:
                settings.clearConsumedEnrollmentTokenPreservingAgentToken()
            default:
                break
            }
        }
    }

    /// Reads lines from `pipe` in a background thread.
    ///
    /// The handler is called once per `availableData` read with all non-empty
    /// lines from that chunk, rather than once per line, so callers can dispatch
    /// a single `Task` instead of one per line.
    private func readPipe(_ pipe: Pipe, handler: @escaping @Sendable ([ParsedLogLine]) -> Void) {
        let fileHandle = pipe.fileHandleForReading
        let decoder = LogPipeChunkDecoder()
        let parser = LogParser()

        fileHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                let trailing = decoder.finish()
                if !trailing.isEmpty {
                    handler(trailing.map { ParsedLogLine(raw: $0.text, event: Self.logEvent(for: $0, parser: parser)) })
                }
                handle.readabilityHandler = nil
                return
            }
            let lines = decoder.ingest(data)
            if !lines.isEmpty {
                handler(lines.map { ParsedLogLine(raw: $0.text, event: Self.logEvent(for: $0, parser: parser)) })
            }
        }
    }

    /// Partial text must never impersonate a complete lifecycle/auth log event.
    nonisolated static func logEvent(for line: LogPipeChunkDecoder.Line, parser: LogParser) -> AgentEvent {
        line.isContinuation ? .unknown(line: line.text) : parser.parse(line.text)
    }
}
