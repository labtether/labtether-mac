# Session History & Cumulative Bandwidth Tracking — Design Spec

**Date:** 2026-03-15
**Scope:** Session history persistence and UI, cumulative bandwidth accumulation and UI
**Approach:** JSON file persistence in Application Support, UI sections in the pop-out dashboard

---

## 1. Session History

### Data Capture

The existing `LogParser` emits typed `AgentEvent` cases for session activity:
- `.terminalSession(detail:)` — remote shell sessions
- `.desktopSession(detail:)` — remote desktop sessions
- `.fileTransfer(detail:)` — file transfer sessions
- `.vncSession(detail:)` — VNC sessions

A new `SessionHistoryTracker` observes these events from `AgentStatus` and creates persistent records.

### Data Model

```swift
enum SessionType: String, Codable, CaseIterable {
    case terminal
    case desktop
    case fileTransfer
    case vnc
}

struct SessionRecord: Codable, Identifiable {
    let id: UUID
    let type: SessionType
    let detail: String
    let timestamp: Date
}
```

### Storage

- **File:** `~/Library/Application Support/LabTether/session-history.json`
- **Format:** JSON array of `SessionRecord`, sorted newest-first
- **Retention:** Max 500 records AND max 30 days — prune on load and before each write
- **Write strategy:** Debounced 5-second timer. When a session event arrives, schedule a write 5s later. Additional events within the window reset the timer. Also writes synchronously on app termination via `applicationWillTerminate`.

### Wiring

`SessionHistoryTracker` is `@MainActor` and conforms to `ObservableObject`. It is owned by `AppState` and initialized in `AppState.init()`.

**Event forwarding mechanism:** `LogLine` does not store a parsed `AgentEvent` — the event parsing happens inside `AgentProcess.handleParsedLines()` which is private. The wiring point is `AgentProcess.handleParsedLines()`, which already calls `status.handleEvent(line.event)` for each parsed line. Add a second call at the same site: `sessionHistoryTracker.handleEvent(line.event, timestamp: Date())`.

`SessionHistoryTracker` exposes a `handleEvent(_ event: AgentEvent, timestamp: Date)` method that checks if the event is a session type and, if so, creates and appends a `SessionRecord`. `AgentProcess` receives the tracker as an init parameter (matching the existing pattern where it already receives `status`, `notifications`, `logBuffer`).

Modified files for wiring:
- `Process/AgentProcess.swift` — add `sessionHistoryTracker` parameter, call `handleEvent` in `handleParsedLines`

### UI

New section `PopOutSessionHistorySection` in the pop-out dashboard, placed after `RecentEventsSection`.

**Layout:**
- Section header: "Session History" with a count badge
- Scrollable list of sessions grouped by calendar day
- Each row shows:
  - Type icon: `terminal.fill` (terminal), `desktopcomputer` (desktop), `folder.fill` (file transfer), `display` (VNC)
  - Detail text — `LT.inter(12)`, `LT.textPrimary`
  - Relative timestamp — `LT.mono(10)`, `LT.textMuted` ("2h ago", "Yesterday 3:14 PM")
- Day group headers — `LT.mono(10, weight: .medium)`, `LT.textSecondary` ("Today", "Yesterday", "Mar 12")
- Empty state: "No sessions recorded yet" in `LT.textMuted`
- "Clear History" button at bottom — `LT.inter(11)`, `LT.textSecondary`, with confirmation

### New Files

| File | Purpose |
|------|---------|
| `Services/SessionHistoryTracker.swift` | Event observation, record storage, JSON persistence |
| `Views/PopOut/PopOutSessionHistorySection.swift` | Pop-out dashboard section |

### Modified Files

| File | Change |
|------|--------|
| `App/AppState.swift` | Create and own `SessionHistoryTracker` |
| `App/App.swift` (AppDelegate) | Call tracker save on `applicationWillTerminate` |
| `Process/AgentProcess.swift` | Accept `SessionHistoryTracker`, call `handleEvent` in `handleParsedLines` |
| `Views/PopOut/PopOutView.swift` | Add `PopOutSessionHistorySection` |

---

## 2. Cumulative Bandwidth Tracking

### Data Capture

The existing `LocalAPIClient` polls `MetricsSnapshot` which includes `netRXBytesPerSec: Double` and `netTXBytesPerSec: Double` with a `collectedAt: Date?` timestamp.

A new `BandwidthTracker` observes each successful poll's metrics and accumulates bytes transferred.

### Accumulation Logic

On each new `MetricsSnapshot`:
1. Guard `collectedAt` is non-nil — skip the sample entirely if `collectedAt` is `nil`
2. Compute `elapsed = collectedAt - lastSampleTime` (in seconds)
3. If `elapsed > 0` AND `elapsed < 90` (skip gaps where agent was down — 90s allows for hidden-mode 30s polling with one missed poll):
   - Compute `rxDelta = UInt64(netRXBytesPerSec * elapsed)` and `txDelta = UInt64(netTXBytesPerSec * elapsed)` (truncation is acceptable)
   - `currentSessionRX += rxDelta`, `currentSessionTX += txDelta`
   - Add to current hourly bucket: `hourlyRX += rxDelta`, `hourlyTX += txDelta`
4. Update `lastSampleTime = collectedAt`
5. If the current hour has rolled over (new hour bucket), flush the previous bucket to `samples`, persist, and start a new bucket.

### Data Model

```swift
struct BandwidthSample: Codable, Identifiable {
    var id: Date { date }
    let date: Date        // rounded to the hour
    var rxBytes: UInt64
    var txBytes: UInt64
}
```

The tracker publishes:
- `currentSessionRX: UInt64` — bytes received since agent started (in-memory, resets on restart)
- `currentSessionTX: UInt64` — bytes sent since agent started
- `samples: [BandwidthSample]` — hourly history (persisted)

### Storage

- **File:** `~/Library/Application Support/LabTether/bandwidth-history.json`
- **Format:** JSON array of `BandwidthSample`, sorted by date
- **Retention:** Max 720 samples (30 days at hourly granularity) — prune on load
- **Write strategy:** Write on hourly rollover (when a new hour bucket starts) and on app termination. Much less frequent than session events.

### Wiring

`BandwidthTracker` is `@MainActor` and conforms to `ObservableObject`. It is owned by `AppState` and initialized in `AppState.init()`.

`AppState` adds a new Combine subscriber on `apiClient.metrics.$snapshot` (using `.receive(on: RunLoop.main)` to ensure the value has been set) and forwards each new `MetricsSnapshot` to `BandwidthTracker.accumulate(_:)`. This is a new sink, separate from the existing `apiMetricsObserver` which uses `objectWillChange` (pre-change) for menu bar label refresh.

When the agent process stops (`agentProcess.isRunning` becomes false), `BandwidthTracker.resetSession()` zeroes the current session counters.

### Presentation Helpers

```swift
enum BandwidthPresentation {
    /// Format bytes as human-readable: "1.2 GB", "340 MB", "4.5 KB"
    static func formatBytes(_ bytes: UInt64) -> String

    /// Aggregate samples for a given calendar day
    static func dailyTotals(from samples: [BandwidthSample]) -> [(date: Date, rx: UInt64, tx: UInt64)]

    /// Sum all samples in the last N days
    static func totalForPeriod(_ samples: [BandwidthSample], days: Int) -> (rx: UInt64, tx: UInt64)
}
```

### UI

New section `PopOutBandwidthSection` in the pop-out dashboard, placed after the system metrics section (`PopOutSystemSection`).

**Layout:**
- Section header: "Bandwidth"
- **Current session row:** "This Session: 1.2 GB ↓  340 MB ↑" — `LT.mono(12)`, down arrow in `LT.ok`, up arrow in `LT.accent`
- **Today row:** "Today: 4.5 GB ↓  1.1 GB ↑" — aggregated from hourly samples for today
- **7-day bar chart:** 7 vertical bars (one per day), each showing combined RX+TX. Uses `LT.accent` fill. Day labels below ("Mon", "Tue", etc.). The tallest bar fills the available height, others scale proportionally. Built as a custom SwiftUI view (not using `LTSparkline`, which is designed for line sparklines).
- **30-day total row:** "Last 30 Days: 42.3 GB ↓  8.1 GB ↑" — `LT.mono(11)`, `LT.textSecondary`
- **Empty state:** When no samples exist, show "Bandwidth data will appear after the agent runs for a while" in `LT.textMuted`

### New Files

| File | Purpose |
|------|---------|
| `Services/BandwidthTracker.swift` | Accumulation, hourly bucketing, JSON persistence |
| `Views/PopOut/PopOutBandwidthSection.swift` | Pop-out dashboard section with bar chart |
| `Presentation/BandwidthPresentation.swift` | Formatting helpers and aggregation functions |

### Modified Files

| File | Change |
|------|--------|
| `App/AppState.swift` | Create `BandwidthTracker`, forward metrics, reset on agent stop |
| `App/App.swift` (AppDelegate) | Call tracker save on `applicationWillTerminate` |
| `Views/PopOut/PopOutView.swift` | Add `PopOutBandwidthSection` |

---

## Cross-Cutting Concerns

### Shared Persistence Pattern

Both trackers follow the same persistence pattern:
1. Load JSON from Application Support on init
2. Prune old records/samples on load
3. Append new data in-memory
4. Write to disk on a trigger (debounced timer or hourly rollover)
5. Write synchronously on app termination

Consider extracting a lightweight `JSONFileStore<T: Codable>` utility if the boilerplate is similar enough, but only if it naturally reduces duplication — don't force an abstraction.

### File Organization

```
Sources/LabTetherAgent/
├── Services/
│   ├── SessionHistoryTracker.swift    # Session event capture + persistence
│   └── BandwidthTracker.swift         # Bandwidth accumulation + persistence
├── Presentation/
│   └── BandwidthPresentation.swift    # Formatting and aggregation helpers
└── Views/PopOut/
    ├── PopOutSessionHistorySection.swift  # Session history UI
    └── PopOutBandwidthSection.swift       # Bandwidth stats + bar chart UI
```

### Modified Files Summary

| File | Features Touching It |
|------|---------------------|
| `App/AppState.swift` | Both trackers: create, wire, forward metrics |
| `App/App.swift` (AppDelegate) | Both trackers: save on termination |
| `Process/AgentProcess.swift` | Session tracker: forward parsed events |
| `Views/PopOut/PopOutView.swift` | Both sections: add to pop-out layout |

### Design System

All new views use existing `LT` design tokens. No new components needed — the 7-day bar chart is a simple custom view using standard SwiftUI shapes.

### Dependencies

No new external dependencies. Uses Foundation `JSONEncoder`/`JSONDecoder` for persistence and `FileManager` for file operations.

### Testing

- `SessionHistoryTracker`: test record creation from events, pruning logic, JSON round-trip
- `BandwidthTracker`: test accumulation math, gap handling (>60s skip), hourly rollover, pruning
- `BandwidthPresentation`: test byte formatting, daily aggregation, period totals
