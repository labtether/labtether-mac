import Foundation
import os

/// Finds the web console for the configured Hub.
///
/// The Hub URL from Add device is usually the Hub API origin (port 8443),
/// which answers `/` with JSON whose `console_url` names the console (port
/// 3000, or the Hub's LABTETHER_CONSOLE_URL). Opening the API origin shows
/// that JSON instead of the console. A console ingress origin serves the
/// console itself and redirects `/`, so its own origin stays the answer.
enum HubConsoleLocator {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.labtether.agent",
        category: "HubConsole"
    )

    /// Reads `console_url` from the Hub API root response. Only http and
    /// https URLs with a host are accepted; a query or fragment is dropped.
    static func consoleURL(fromHubRoot body: Data) -> URL? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              object["service"] as? String == "labtether-hub",
              let raw = (object["console_url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              var components = URLComponents(string: raw),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil
        else { return nil }
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// Asks the Hub API root for its console with the same TLS trust as the
    /// bundled agent. Nil when the Hub URL is not the API origin, the Hub
    /// cannot be reached, or the answer names no console.
    static func locate(hubURL: String, tlsSkipVerify: Bool, tlsCAFile: String) async -> URL? {
        guard let root = ConnectionTester.httpBaseURL(from: hubURL),
              let response = try? await ConnectionTester.probeHub(
                  url: root, tlsSkipVerify: tlsSkipVerify, tlsCAFile: tlsCAFile),
              response.statusCode == 200
        else { return nil }
        return consoleURL(fromHubRoot: response.body)
    }

    static func record(_ url: URL?) {
        guard let url else { return }
        logger.notice("Hub console: \(url.absoluteString, privacy: .public)")
    }
}

extension AgentSettings {
    /// Looks up the console the connected Hub names and keeps it for this
    /// Hub URL only. Called on each connection; failures keep the fallback.
    func refreshHubConsoleURL() {
        guard let wsURL = normalizedHubWebSocketURL() else { return }
        let configuredCA = tlsCAFile.trimmingCharacters(in: .whitespacesAndNewlines)
        // The bundled agent trusts the CA the Hub returned at enrollment
        // when no CA file is configured.
        let enrolledCA = appSupportDirectory.appendingPathComponent("ca.crt").path
        let caFile = !configuredCA.isEmpty ? configuredCA
            : (FileManager.default.fileExists(atPath: enrolledCA) ? enrolledCA : "")
        let skipVerify = tlsSkipVerify
        Task { @MainActor [weak self] in
            let url = await HubConsoleLocator.locate(hubURL: wsURL, tlsSkipVerify: skipVerify, tlsCAFile: caFile)
            guard let self, let url, self.normalizedHubWebSocketURL() == wsURL else { return }
            self.hubConsoleSource = wsURL
            if self.hubConsoleURL != url { self.hubConsoleURL = url }
            HubConsoleLocator.record(url)
        }
    }
}
