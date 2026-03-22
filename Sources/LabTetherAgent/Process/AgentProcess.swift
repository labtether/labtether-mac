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
        sessionHistory: SessionHistoryTracker
    ) {
        self.status = status
        self.settings = settings
        self.notifications = notifications
        self.logBuffer = logBuffer
        self.sessionHistory = sessionHistory

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

    /// Kill any orphaned agent processes from previous app runs.
    ///
    /// This only targets absolute executable paths to avoid broad pattern matches.
    func killOrphanedAgents(matching binaryPath: String) {
        let orphaned = orphanedAgentPIDs(matching: binaryPath)
        guard !orphaned.isEmpty else { return }

        for pid in orphaned {
            _ = kill(pid, SIGKILL)
        }

        logBuffer.append("[app] Reaped \(orphaned.count) orphaned agent process(es)")
    }

    /// Immediately kill the agent process (used during app quit).
    func forceKill() {
        guard let proc = process else { return }
        userInitiatedStop = true
        pendingRestart = false
        if proc.isRunning {
            kill(proc.processIdentifier, SIGKILL)
        }
        process = nil
        isRunning = false
        isStarting = false
    }

    func start(resetCrashHistory: Bool = true) {
        debugBootProcess("start called resetCrashHistory=\(resetCrashHistory) process_nil=\(process == nil) isStarting=\(isStarting)")
        guard process == nil && !isStarting else { return }

        if resetCrashHistory {
            crashCoordinator.reset()
        } else {
            crashCoordinator.cancelCooldown()
        }

        // Validate config before launching
        guard settings.isConfigured else {
            debugBootProcess("start aborted: settings.isConfigured=false")
            status.markError("Hub URL and token required — open Settings to configure")
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

        let binaryPath = BundleHelper.agentBinaryPath
        debugBootProcess("binaryPath=\(binaryPath)")
        guard binaryPath.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: binaryPath) else {
            debugBootProcess("start aborted: binary not executable")
            status.markError("Agent binary not found at \(binaryPath)")
            return
        }

        userInitiatedStop = false
        needsRestart = false
        isStarting = true
        status.markStarting()

        // Clean up any orphaned agents from previous runs.
        killOrphanedAgents(matching: binaryPath)

        let proc = Process()
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
            Task { @MainActor in
                guard let self = self else { return }
                let previousState = self.status.state
                let wasUserStop = self.userInitiatedStop
                let shouldRestart = self.pendingRestart
                self.pendingRestart = false
                self.process = nil
                self.isRunning = false
                self.isStarting = false
                self.stdoutPipe = nil
                self.stderrPipe = nil

                if wasUserStop || shouldRestart || proc.terminationStatus == 0 {
                    self.status.markStopped()
                } else {
                    self.status.markError("Exited with code \(proc.terminationStatus)")
                }

                if previousState == .connected && !wasUserStop && !shouldRestart {
                    self.notifications.notify(.disconnected)
                }

                if shouldRestart {
                    self.start()
                    return
                }

                // Auto-restart on unexpected crash (non-zero exit, not user-initiated)
                if proc.terminationStatus != 0 && !wasUserStop {
                    self.attemptCrashRestart()
                }
            }
        }

        do {
            try proc.run()
        } catch {
            debugBootProcess("start failed to run process: \(error.localizedDescription)")
            isStarting = false
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
        readPipe(stdout) { [weak self] lines in
            Task { @MainActor in
                guard let self else { return }
                self.handleParsedLines(lines)
            }
        }
        // Read stderr in background (Go logs to stderr by default)
        readPipe(stderr) { [weak self] lines in
            Task { @MainActor in
                guard let self else { return }
                self.handleParsedLines(lines)
            }
        }
    }

    func stop(forRestart: Bool = false) {
        userInitiatedStop = true
        pendingRestart = forRestart
        crashCoordinator.cancelCooldown()
        isStarting = false
        guard let proc = process, proc.isRunning else {
            process = nil
            isRunning = false
            status.markStopped()
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

    private func attemptCrashRestart() {
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

            Task {
                try? await Task.sleep(for: .seconds(delay))
                // Re-check that user hasn't manually started/stopped in the meantime
                if self.process == nil && !self.userInitiatedStop {
                    self.start(resetCrashHistory: false)
                }
            }
        }
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
                    handler(trailing.map { ParsedLogLine(raw: $0, event: parser.parse($0)) })
                }
                handle.readabilityHandler = nil
                return
            }
            let lines = decoder.ingest(data)
            if !lines.isEmpty {
                handler(lines.map { ParsedLogLine(raw: $0, event: parser.parse($0)) })
            }
        }
    }

    private func orphanedAgentPIDs(matching binaryPath: String) -> [Int32] {
        guard binaryPath.hasPrefix("/"),
              FileManager.default.isExecutableFile(atPath: binaryPath) else {
            return []
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid=,command="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
        } catch {
            return []
        }
        // Drain stdout before waitUntilExit() to avoid pipe-buffer deadlocks
        // when process listings are large.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8) else {
            return []
        }

        let selfPID = ProcessInfo.processInfo.processIdentifier
        var pids: [Int32] = []

        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let pieces = trimmed.split(
                maxSplits: 1,
                omittingEmptySubsequences: true,
                whereSeparator: { $0 == " " || $0 == "\t" }
            )
            guard pieces.count == 2, let pid = Int32(pieces[0]), pid != selfPID else { continue }
            let command = String(pieces[1])
            if command == binaryPath || command.hasPrefix("\(binaryPath) ") {
                pids.append(pid)
            }
        }

        return pids
    }
}
