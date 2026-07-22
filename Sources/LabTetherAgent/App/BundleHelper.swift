import Foundation

/// Locates the Go agent binary bundled inside the .app Resources directory.
enum BundleHelper {
    private static let bundledAgentName = "labtether-agent"
    private static let resourceBundleName = "LabTetherAgent_LabTetherAgent"

    /// Path to the Go binary inside the app bundle.
    /// Falls back to a development path if not running from a bundle.
    static var agentBinaryPath: String {
        let bundledPath = Bundle.main.path(forResource: bundledAgentName, ofType: nil)
        let overridePath = ProcessInfo.processInfo.environment["LABTETHER_AGENT_BINARY_PATH"]
        return resolveAgentBinaryPath(
            bundledPath: bundledPath,
            overridePath: overridePath,
            executableURL: Bundle.main.executableURL,
            currentDirectoryPath: FileManager.default.currentDirectoryPath
        )
    }

    /// Resource bundle emitted by SwiftPM and copied into Contents/Resources
    /// by scripts/build-app.sh. The Bundle.module fallback keeps `swift run`
    /// and `swift test` working outside an application bundle.
    static var resourceBundle: Bundle {
        if let url = Bundle.main.url(forResource: resourceBundleName, withExtension: "bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }

    /// Resolve the child agent without relying on a fixed number of `.build`
    /// path components. The split-repository layout keeps generated artifacts
    /// under mac-agent/build, next to this package.
    static func resolveAgentBinaryPath(
        bundledPath: String?,
        overridePath: String?,
        executableURL: URL?,
        currentDirectoryPath: String,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String {
        var candidates: [String] = []

        if let bundledPath, !bundledPath.isEmpty {
            candidates.append(bundledPath)
        }

        if let overridePath {
            let trimmed = overridePath.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("/") {
                candidates.append(trimmed)
            }
        }

        if let executableURL,
           let repositoryRoot = macAgentRepositoryRoot(containing: executableURL) {
            candidates.append(
                repositoryRoot.appendingPathComponent("build/labtether-agent-darwin").path
            )
        }

        candidates.append(
            URL(fileURLWithPath: currentDirectoryPath, isDirectory: true)
                .appendingPathComponent("build/labtether-agent-darwin")
                .path
        )

        if let match = candidates.first(where: isExecutable) {
            return match
        }

        // Last resort: allow normal PATH lookup. AgentProcess rejects a missing
        // or non-executable child with an actionable error before launch.
        return bundledAgentName
    }

    private static func macAgentRepositoryRoot(containing executableURL: URL) -> URL? {
        var cursor = executableURL.deletingLastPathComponent()
        while cursor.path != "/" {
            if cursor.lastPathComponent == "mac-agent" {
                return cursor
            }
            cursor.deleteLastPathComponent()
        }
        return nil
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
