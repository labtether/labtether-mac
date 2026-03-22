# Batch 1: User-Facing Essentials — Design Spec

**Date:** 2026-03-15
**Scope:** Onboarding, Test Connection, Connection Diagnostics, About Window, Copy Diagnostics
**Approach:** Standalone Windows (Approach A) — each feature gets its own SwiftUI window/sheet following existing architecture patterns.

---

## 1. Onboarding / First-Run Experience

### Trigger

On app launch, if `AgentSettings.isConfigured` returns `false` AND `@AppStorage("hasCompletedOnboarding")` is `false`, auto-open the onboarding window.

**Mechanism:** `AppState` publishes a `@Published var shouldShowOnboarding: Bool` flag, initially set during `init()`. In `App.swift`, the `MenuBarExtra` body observes this flag via `.onChange(of: appState.shouldShowOnboarding)` and calls `openWindow(id: "onboarding")` when it becomes `true`. This keeps `AppState` free of SwiftUI environment dependencies while using the standard `OpenWindowAction`.

### Window

`Window("Welcome to LabTether", id: "onboarding")` registered in `App.swift`. Fixed size (~500x450), non-resizable. Uses existing glass morphism design system (`LT` tokens).

### Steps

**Step 1 — Welcome + Hub URL:**
- App icon (large, centered)
- "Welcome to LabTether" headline
- Brief description: "Connect this Mac to your LabTether hub for remote management."
- Text field for Hub URL with default `wss://localhost:8443/ws/agent` pre-filled
- "Paste from Clipboard" convenience button

**Step 2 — Authentication:**
- Segmented picker: "Enrollment Token" (default) | "API Token"
- Single secure text field for the selected token type
- Help text: "Use an enrollment token to register this device, or an API token if already enrolled."

**Step 3 — Identity (Optional) + Test:**
- Optional Asset ID and Group ID text fields
- "Test Connection" button using `ConnectionTester.quickTest()`
- Inline result: green checkmark + "Connected" or red X + error message
- "Skip" link to proceed without testing

### Navigation

Back/Next buttons at bottom of each step. Step 3 has "Finish & Start Agent" as the primary action.

### On Finish

1. Write draft values to `AgentSettings` (hub URL, token, asset ID, group ID)
2. Set `hasCompletedOnboarding = true`
3. Call `AgentSettings.markChanged()`
4. Start the agent process

### Re-access

Menu bar footer section: "Setup Wizard..." item that sets `hasCompletedOnboarding = false` and opens the onboarding window.

### New Files

| File | Purpose |
|------|---------|
| `Views/Onboarding/OnboardingView.swift` | Wizard container with step navigation |
| `Views/Onboarding/OnboardingWelcomeStep.swift` | Step 1: welcome + hub URL |
| `Views/Onboarding/OnboardingAuthStep.swift` | Step 2: token selection |
| `Views/Onboarding/OnboardingIdentityStep.swift` | Step 3: optional identity + test |

### New State

`OnboardingState: ObservableObject` — holds draft values during the wizard flow:
- `hubURL: String`
- `tokenType: TokenType` (enum: `.enrollment`, `.apiToken`)
- `tokenValue: String`
- `assetID: String`
- `groupID: String`
- `currentStep: Int` (0, 1, 2)
- `connectionTestResult: ConnectionTestResult?`

Only writes to `AgentSettings` on "Finish" — no side effects during editing.

### Modified Files

| File | Change |
|------|--------|
| `App/App.swift` | Add `Window("Welcome to LabTether", id: "onboarding")` scene |
| `App/AppState.swift` | Check `isConfigured` + `hasCompletedOnboarding` on init, trigger window open |
| `Views/MenuBar/MenuBarFooterSection.swift` | Add "Setup Wizard..." item |
| `Settings/AgentSettings.swift` | Add `hasCompletedOnboarding` AppStorage property |

---

## 2. Test Connection

### Quick Test

An async function that reuses `AgentSettings.consoleURL` to derive the HTTP base URL (avoids duplicating the WS→HTTP conversion logic) and performs an HTTP GET. Returns success (with response time) or failure (with error description). Timeout: 10 seconds.

### UI Integration

**Settings Connection Tab:** "Test Connection" button below the Hub URL field. Shows inline result using `LTAnimatedCheck` for success or red error text for failure. Disabled while test is running (shows spinner).

**Onboarding Step 3:** Reuses the same `ConnectionTester.quickTest()` call.

**Menu Bar Quick Actions:** "Test Connection" button that runs the quick test and shows result as a brief notification via `NotificationManager`.

### New Files

| File | Purpose |
|------|---------|
| `Services/ConnectionTester.swift` | Async actor with `quickTest()` and `fullDiagnostics()` methods |

### Modified Files

| File | Change |
|------|--------|
| `Views/Settings/SettingsConnectionTab.swift` | Add "Test Connection" button + inline result |
| `Views/MenuBar/MenuBarQuickActionsSection.swift` | Add "Test Connection" action |

---

## 3. Connection Diagnostics

### Full Diagnostics

Extends `ConnectionTester` with a `fullDiagnostics()` method that runs 4 sequential checks, publishing results as they complete:

1. **DNS Resolution** — `getaddrinfo` on hub hostname. Reports resolved IP addresses or failure. Timeout: 5 seconds.
2. **TCP Connection** — `NWConnection` to host:port. Reports latency or timeout. Timeout: 5 seconds.
3. **TLS Handshake** — If `wss://`, validates certificate chain respecting `tlsSkipVerify` and `tlsCAFile`. Reports cert subject + expiry or error. Timeout: 5 seconds.
4. **HTTP Reachability** — `URLSession` GET to HTTP base URL (via `AgentSettings.consoleURL`). Reports status code + response time. Timeout: 10 seconds.

### Results Model

```swift
struct DiagnosticStep {
    let name: String           // "DNS Resolution", "TCP Connection", etc.
    var status: StepStatus     // .pending, .running, .success(String), .failure(String)
}

enum StepStatus {
    case pending
    case running
    case success(String)       // detail message
    case failure(String)       // error message
}
```

### UI

A sheet presented from the Settings Connection tab. Triggered by "Run Full Diagnostics..." link that appears below the quick test result.

Shows a vertical list of the 4 steps, each with:
- Status icon: gray circle (pending), spinner (running), green checkmark (success), red X (failure)
- Step name
- Detail/error text when complete

"Close" button at bottom. "Copy Results" button that formats all steps as text and copies to clipboard.

### New Files

| File | Purpose |
|------|---------|
| `Views/Settings/ConnectionDiagnosticsSheet.swift` | Sheet showing step-by-step diagnostic results |

### Modified Files

| File | Change |
|------|--------|
| `Views/Settings/SettingsConnectionTab.swift` | Add "Run Full Diagnostics..." link |
| `Services/ConnectionTester.swift` | Add `fullDiagnostics()` method and result models |

---

## 4. About Window

### Window

`Window("About LabTether", id: "about")` registered in `App.swift`. Compact fixed size (~340x380), non-resizable, centered.

### Content (top to bottom)

1. App icon (64pt, centered)
2. "LabTether Agent" title (`LT.title` typography)
3. App version + build: `Bundle.main.infoDictionary["CFBundleShortVersionString"]` + `CFBundleVersion`
4. Agent binary version: The existing `AgentStatusResponse` model has an `agentVersion` field but it is not currently forwarded into `LocalAPIMetadataSnapshot`. Add `agentVersion: String?` to `LocalAPIMetadataSnapshot` and populate it during the poll cycle. The About view reads from `LocalAPIMetadataStore.snapshot.agentVersion`. Falls back to "Agent not running" when nil.
5. macOS version: `ProcessInfo.processInfo.operatingSystemVersionString`
6. Device fingerprint: read from `AgentSettings.deviceFingerprintFilePath`, truncated to 16 chars with "..." and copy button
7. Horizontal divider
8. Links row: "Website" | "Documentation" | "Support" — `Link` views opening URLs in default browser
9. Footer: "© 2026 LabTether"

### Access Points

Menu bar footer section: "About LabTether..." item using `OpenWindowAction`.

### New Files

| File | Purpose |
|------|---------|
| `Views/About/AboutView.swift` | Complete About window content |

### Modified Files

| File | Change |
|------|--------|
| `App/App.swift` | Add `Window("About LabTether", id: "about")` scene |
| `Views/MenuBar/MenuBarFooterSection.swift` | Add "About LabTether..." item |

---

## 5. Copy Diagnostics

### Collected Information

Markdown-formatted string containing:

```
## LabTether Diagnostics Report
**Generated:** <ISO 8601 timestamp>

### Application
- App Version: <version> (<build>)
- Agent Version: <from API metadata or "Not running">
- macOS: <version> (<arch>)

### Connection
- Hub URL: <url>
- Connection State: <from AgentStatus>
- Agent PID: <pid or "Not running">
- Uptime: <formatted uptime>

### Screen Sharing
- Status: <enabled/disabled>
- Control Access: <full/observe-only/none>

### Issues
- Validation Errors: <list or "None">
- Secret Persistence Errors: <list or "None">

### Recent Logs (last 50 lines)
<log lines>
```

Security: Token values are never included. Hub URL is shown (not a secret — it's a server address). The report says "API Token: configured" / "not configured" without revealing values.

### Behavior

1. Collect all info from existing state objects
2. Copy to `NSPasteboard.general`
3. Show `LTAnimatedCheck` confirmation inline, fades after 2 seconds

### Access Points

- Menu bar footer section: "Copy Diagnostics" button
- Settings Connection tab: "Copy Diagnostics" button in footer area

### New Files

| File | Purpose |
|------|---------|
| `Services/DiagnosticsCollector.swift` | Static `collect()` function returning formatted string |

**Note:** An inline `copyDiagnostics()` implementation already exists in `MenuBarView.swift`. The new `DiagnosticsCollector` extracts and replaces that logic. `MenuBarView.copyDiagnostics()` will be refactored to call `DiagnosticsCollector.collect()` instead of building the string inline.

### Modified Files

| File | Change |
|------|--------|
| `Views/MenuBar/MenuBarView.swift` | Refactor `copyDiagnostics()` to call `DiagnosticsCollector.collect()` |
| `Views/MenuBar/MenuBarFooterSection.swift` | Add "Copy Diagnostics" button |
| `Views/Settings/SettingsConnectionTab.swift` | Add "Copy Diagnostics" button |

---

## Cross-Cutting Concerns

### Design System

All new views use existing `LT` design tokens:
- Colors: `LT.surface`, `LT.accent`, `LT.textPrimary`, `LT.textSecondary`
- Spacing: `LT.spacing.*`
- Typography: `LT.title`, `LT.body`, `LT.mono()`
- Components: `LTAnimatedCheck`, `LTGlassCard`, `LTButton`

### Architecture Patterns

- Follow existing MVVM with `@ObservableObject` + `@Published`
- Use `@MainActor` on all new observable classes
- New services are stateless or use async actor pattern
- No new singletons except where matching existing patterns (`OnboardingState` is owned by the onboarding view, not a singleton)

### File Organization

```
Sources/LabTetherAgent/
├── Services/                          # New directory
│   ├── ConnectionTester.swift         # Shared connection testing
│   └── DiagnosticsCollector.swift     # Diagnostics report builder
├── Views/
│   ├── Onboarding/                    # New directory
│   │   ├── OnboardingView.swift
│   │   ├── OnboardingWelcomeStep.swift
│   │   ├── OnboardingAuthStep.swift
│   │   └── OnboardingIdentityStep.swift
│   ├── About/                         # New directory
│   │   └── AboutView.swift
│   └── Settings/
│       └── ConnectionDiagnosticsSheet.swift  # New file
```

### Modified Files Summary

| File | Features Touching It |
|------|---------------------|
| `App/App.swift` | Onboarding window, About window, `.onChange` for onboarding trigger |
| `App/AppState.swift` | First-run detection (`shouldShowOnboarding` flag) |
| `Settings/AgentSettings.swift` | `hasCompletedOnboarding` property |
| `API/LocalAPIClient.swift` | Add `agentVersion` to `LocalAPIMetadataSnapshot` |
| `Views/Settings/SettingsConnectionTab.swift` | Test Connection, Full Diagnostics link, Copy Diagnostics |
| `Views/MenuBar/MenuBarView.swift` | Refactor `copyDiagnostics()` to use `DiagnosticsCollector` |
| `Views/MenuBar/MenuBarFooterSection.swift` | About, Setup Wizard, Copy Diagnostics |
| `Views/MenuBar/MenuBarQuickActionsSection.swift` | Test Connection |

### Dependencies

No new external dependencies. All features use Foundation, SwiftUI, Network framework (for TCP/DNS diagnostics), and Security framework (already imported).
