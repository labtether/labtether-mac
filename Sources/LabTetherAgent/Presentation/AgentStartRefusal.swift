import Foundation

/// The agent stops at start when it is told to trust only the Hub's CA and
/// cannot use the CA file, and says so in one log line. The app checks the
/// file before it starts the agent, so this is the rare case where the file
/// went away in between; the menu then says it in words, not "Exited with
/// code 1".
enum AgentStartRefusal {
    static func words(forLogLine line: String) -> String? {
        guard line.contains("LABTETHER_TLS_CA_ONLY") else { return nil }
        if line.contains("is on but") {
            return "The Hub's CA certificate cannot be read. Trust the Hub again with Test connection in Settings › Connection."
        }
        if line.contains("must be true or false") {
            return "The agent did not start: its certificate setting is not valid."
        }
        return nil
    }
}
