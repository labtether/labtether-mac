import Foundation

/// Decides the notifications and the crash-counter reset for Hub connection
/// changes. Two sources report them: the agent's log lines, which arrive
/// first with the Go agent, and its status endpoint, which every agent
/// serves whatever it prints. Each effect keys off the app's own state
/// before and after a change, so a change both sources report fires once.
struct HubConnectionEffects {
    enum Effect: Equatable {
        case announceConnected
        case resetCrashCounter
        case announceConnectionLost
    }

    /// The Go agent prints its "closed after" line only for a connection
    /// that lasted less than this (ws_reconnect.go, minStableSession).
    static let shortConnection: TimeInterval = 30

    /// When the app first saw the current connection, from either source.
    private var connectedSince: Date?
    /// The Hub closed the last connection soon after accepting it. The next
    /// "connected" is then not announced, so a Hub that keeps closing new
    /// connections does not raise a notification each time.
    private var hubClosedLastConnection = false
    /// The status showed a connection that lasted ends; the next failed
    /// reconnect the agent reports is announced as a lost connection.
    private var lostAnnouncementDue = false

    mutating func reset() {
        self = HubConnectionEffects()
    }

    /// The agent reported a connection, in its log or its status.
    mutating func connected(wasConnected: Bool, at now: Date) -> [Effect] {
        let closedShortly = hubClosedLastConnection
        hubClosedLastConnection = false
        lostAnnouncementDue = false
        guard !wasConnected else { return [] }
        connectedSince = now
        return closedShortly ? [.resetCrashCounter] : [.announceConnected, .resetCrashCounter]
    }

    /// Log: a connect attempt failed and the agent retries.
    mutating func logRetrying(wasConnected: Bool) -> [Effect] {
        guard wasConnected || lostAnnouncementDue else { return [] }
        lostAnnouncementDue = false
        connectedSince = nil
        return [.announceConnectionLost]
    }

    /// Log: the Hub closed a connection that lasted under 30 s.
    mutating func logHubClosedShortly() {
        hubClosedLastConnection = true
        lostAnnouncementDue = false
        connectedSince = nil
    }

    /// Status: the app's state went from connected to reconnecting.
    /// `disconnectedAt` is the agent's own time for it, when it sent one.
    mutating func statusLeftConnected(disconnectedAt: Date?, now: Date) {
        let since = connectedSince ?? now
        connectedSince = nil
        // The app sees a connection no earlier than it began, so with the
        // agent's time this is never longer than the real connection.
        // Without it, the time the app noticed the change stands in.
        if (disconnectedAt ?? now).timeIntervalSince(since) < Self.shortConnection {
            hubClosedLastConnection = true
        } else {
            lostAnnouncementDue = true
        }
    }

    /// Status: the agent is retrying after a failed connect.
    mutating func statusRetrying() -> [Effect] {
        guard lostAnnouncementDue else { return [] }
        lostAnnouncementDue = false
        return [.announceConnectionLost]
    }
}
