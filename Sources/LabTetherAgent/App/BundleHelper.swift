import Foundation

/// Locates the Go agent binary bundled inside the .app Resources directory.
enum BundleHelper {
    /// Path to the Go binary inside the app bundle.
    /// Falls back to a development path if not running from a bundle.
    static var agentBinaryPath: String {
        // When running from .app bundle: Contents/Resources/labtether-agent
        if let bundledPath = Bundle.main.path(forResource: "labtether-agent", ofType: nil) {
            return bundledPath
        }

        // Development fallback: look relative to the swift build output
        // The debug binary lives at apps/mac-agent/.build/debug/LabTetherAgent
        // The agent binary is at build/labtether-agent-darwin (project root)
        if let execURL = Bundle.main.executableURL {
            // Walk up from .build/debug/LabTetherAgent to apps/mac-agent, then to project root
            let macAgentDir = execURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let projectRoot = macAgentDir.deletingLastPathComponent().deletingLastPathComponent()
            let devPath = projectRoot.appendingPathComponent("build/labtether-agent-darwin").path
            if FileManager.default.fileExists(atPath: devPath) {
                return devPath
            }
        }

        // Also check CWD-relative path
        let cwdPath = FileManager.default.currentDirectoryPath + "/build/labtether-agent-darwin"
        if FileManager.default.fileExists(atPath: cwdPath) {
            return cwdPath
        }

        // Last resort: assume it's on PATH
        return "labtether-agent"
    }

    /// Whether the Go binary exists and is executable.
    static var binaryExists: Bool {
        let path = agentBinaryPath
        return FileManager.default.isExecutableFile(atPath: path)
    }

    /// App version from Info.plist (e.g. "1.0.0").
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    /// Build number from Info.plist (e.g. "1").
    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    /// CPU architecture (e.g. "arm64", "x86_64").
    static var architecture: String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }

    /// Query the Go binary for its version (synchronous, called once at startup).
    static var agentBinaryVersion: String {
        let path = agentBinaryPath
        guard FileManager.default.isExecutableFile(atPath: path) else { return "unknown" }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = ["--version"]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return "unknown"
        }

        guard let data = Optional(pipe.fileHandleForReading.availableData),
              let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return "unknown"
        }
        return output
    }
}
