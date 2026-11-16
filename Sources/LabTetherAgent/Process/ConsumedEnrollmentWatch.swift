import Foundation

/// Tells from files, not log words, when the agent has used the one-use
/// enrollment token, so the app can remove its Keychain copy.
///
/// The app writes the token to `enrollment-token` before each start. The
/// agent removes that file only after the Hub accepted the token, and only
/// after writing the agent token it was given (Go: `enroll.go`,
/// `enrollment_token_consumed.go`; Rust: `flow.rs`, `credential.rs`,
/// `state.rs`). If the agent token could not be written, the agent removes
/// any older one, so a missing or non-private agent token never counts.
/// The Go agent also prints "removed consumed enrollment token file" at that
/// point; this watch reaches the same answer when nothing is printed.
struct ConsumedEnrollmentWatch {
    /// The Keychain value the running child was started with, when it was
    /// given the enrollment token file. "" for a file supplied by an
    /// installer. nil when there is nothing to watch.
    private var launchedToken: String?
    /// "Enrolled" was announced for this child.
    private(set) var announced = false

    /// Call after a child starts with `environment`.
    mutating func launched(environment: [String: String]?, enrollmentToken: String) {
        announced = false
        launchedToken = environment?["LABTETHER_ENROLLMENT_TOKEN_FILE"] == nil
            ? nil
            : Self.trimmed(enrollmentToken)
    }

    /// The log said the child enrolled, or the Keychain copy was removed.
    mutating func markAnnounced() { announced = true }

    /// The log path already removed the Keychain copy for this child.
    mutating func finish() { launchedToken = nil }

    /// Whether the child has used the token it was started with: its file is
    /// gone and a private agent token is on disk. A token changed in
    /// Settings while the child runs ends the watch, because saving one
    /// also removes the file.
    mutating func consumed(settings: AgentSettings) -> Bool {
        guard let launchedToken else { return false }
        guard Self.trimmed(settings.enrollmentToken) == launchedToken else {
            self.launchedToken = nil
            return false
        }
        let path = settings.enrollmentTokenFilePath
        let fileGone = (try? FileManager.default.attributesOfItem(atPath: path)) == nil
        guard fileGone, settings.hasPersistedAgentToken else { return false }
        self.launchedToken = nil
        return true
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
