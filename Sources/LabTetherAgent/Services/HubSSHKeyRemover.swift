import Foundation

/// Removes the Hub SSH key line the bundled agent added to authorized_keys.
/// Agent releases after 1.7.0 record that line next to the agent token and
/// remove it with `labtether-agent ssh-key remove`. The bundled 1.7.0 agent
/// answers "unknown command"; that means there is nothing it can remove.
enum HubSSHKeyRemover {
    enum Outcome: Equatable {
        case done(String)
        case unsupported
        case failed(String)
    }

    static func run(
        agentBinaryPath: String,
        tokenFilePath: String,
        agentSettingsFilePath: String,
        timeout: TimeInterval = 10
    ) -> Outcome {
        guard FileManager.default.isExecutableFile(atPath: agentBinaryPath) else { return .unsupported }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: agentBinaryPath)
        process.arguments = ["ssh-key", "remove"]
        // The agent finds its record beside this token file.
        var environment = [
            "LABTETHER_TOKEN_FILE": tokenFilePath,
            "LABTETHER_AGENT_SETTINGS_FILE": agentSettingsFilePath,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        ]
        if let home = ProcessInfo.processInfo.environment["HOME"] { environment["HOME"] = home }
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return .failed(error.localizedDescription) }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            kill(process.processIdentifier, SIGKILL)
            _ = finished.wait(timeout: .now() + 2)
            return .failed("the agent did not finish in time")
        }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return outcome(exitCode: process.terminationStatus, output: text)
    }

    static func outcome(exitCode: Int32, output: String) -> Outcome {
        let lastLine = output.split(whereSeparator: \.isNewline).last
            .map { String($0.trimmingCharacters(in: .whitespaces).prefix(300)) } ?? ""
        if exitCode == 0 { return .done(lastLine) }
        if output.contains("unknown command") { return .unsupported }
        return .failed(lastLine.isEmpty ? "the agent exited with code \(exitCode)" : lastLine)
    }
}
