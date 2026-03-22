# Code Quality Refactor Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate duplicated logic, extract mixed concerns, and centralize scattered patterns. No behavioral changes.

**Architecture:** Extract-and-delegate pattern throughout. New types are thin, focused classes/structs. Existing types delegate to them. All types stay internal within same SPM module.

**Tech Stack:** Swift 5.9, SwiftUI, SPM

**Spec:** `docs/superpowers/specs/2026-03-15-code-quality-refactor-design.md`

---

## Task 1: Centralize Hero Presentation Resolution

**Files:**
- Modify: `Sources/LabTetherAgent/Presentation/AgentHeroPresentation.swift`
- Modify: `Sources/LabTetherAgent/Views/MenuBar/MenuBarHeroSection.swift`
- Modify: `Sources/LabTetherAgent/Views/MenuBar/MenuBarBackground.swift`
- Modify: `Sources/LabTetherAgent/Views/PopOut/PopOutHeroSection.swift`

- [ ] **Step 1: Read all 4 files to understand the current duplication**

- [ ] **Step 2: Add convenience factory to AgentHeroPresentation**

Add a static method that takes the observable objects directly:

```swift
static func resolve(
    agentProcess: AgentProcess,
    status: AgentStatus,
    runtime: LocalAPIRuntimeStore
) -> AgentHeroPresentation {
    resolve(
        processIsRunning: agentProcess.isRunning,
        processIsStarting: agentProcess.isStarting,
        statusState: status.state,
        statusLastError: status.lastError,
        statusUptime: status.uptime,
        apiUptime: runtime.snapshot.uptime,
        apiLastError: runtime.snapshot.lastError,
        hubConnectionState: runtime.snapshot.hubConnectionState,
        isReachable: runtime.snapshot.isReachable
    )
}
```

- [ ] **Step 3: Update all 3 view files to use the new factory**

Replace the verbose `resolve(processIsRunning:processIsStarting:...)` calls with the new `resolve(agentProcess:status:runtime:)`.

- [ ] **Step 4: Build to verify**

Run: `swift build`

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "refactor: centralize AgentHeroPresentation resolution"
```

---

## Task 2: Centralize Gauge Color Thresholds

**Files:**
- Modify: `Sources/LabTetherAgent/Presentation/MetricsPresentation.swift`
- Modify: `Sources/LabTetherAgent/Views/MenuBar/MenuBarHeroSection.swift`
- Modify: `Sources/LabTetherAgent/Views/PopOut/PopOutSystemSection.swift`
- Modify: `Sources/LabTetherAgent/Views/Shared/MetricsView.swift`

- [ ] **Step 1: Read MetricsPresentation.swift and the 3 view files that have inline color logic**

- [ ] **Step 2: Add a static gaugeColor method to MetricsPresentation or a new extension**

```swift
extension MetricGaugePresentation {
    var color: Color {
        if rawValue >= 90 { return LT.bad }
        if rawValue >= 75 { return LT.warn }
        return LT.ok
    }
}
```

- [ ] **Step 3: Replace all inline gauge color functions in view files**

Remove `miniGaugeColor()` from MenuBarHeroSection, `popOutGaugeColor()` from PopOutSystemSection, and any inline threshold checks in MetricsView. Use `gauge.color` instead.

- [ ] **Step 4: Build to verify**

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "refactor: centralize metric gauge color thresholds"
```

---

## Task 3: Extract VisibilityAware Protocol

**Files:**
- Create: `Sources/LabTetherAgent/App/VisibilityAware.swift`
- Modify: `Sources/LabTetherAgent/API/LocalAPIClient.swift`
- Modify: `Sources/LabTetherAgent/Monitoring/ScreenSharingMonitor.swift`
- Modify: `Sources/LabTetherAgent/State/AgentStatus.swift`

- [ ] **Step 1: Read the visibility pattern in all 3 files**

- [ ] **Step 2: Create VisibilityAware.swift**

Define a protocol that captures the shared pattern. Since these are classes with stored properties, use a base class or just a protocol with required stored property accessors.

- [ ] **Step 3: Adopt in all 3 classes**

- [ ] **Step 4: Build to verify**

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "refactor: extract VisibilityAware protocol for surface tracking"
```

---

## Task 4: Extract LogLine Model from LogBufferView

**Files:**
- Create: `Sources/LabTetherAgent/State/LogLine.swift`
- Modify: `Sources/LabTetherAgent/Views/LogViewer/LogBufferView.swift`

- [ ] **Step 1: Read LogBufferView.swift to identify all types to extract**

Identify: `LogLine` struct, `LogLevel` enum, `LogBuffer` class, and any supporting types that are data models rather than views.

- [ ] **Step 2: Create State/LogLine.swift with extracted types**

Move all non-view types. Keep access level as `internal`.

- [ ] **Step 3: Remove extracted types from LogBufferView.swift**

LogBufferView.swift should contain only SwiftUI view code.

- [ ] **Step 4: Build to verify**

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "refactor: extract LogLine model and LogBuffer from LogBufferView"
```

---

## Task 5: Split LocalAPIClient

**Files:**
- Create: `Sources/LabTetherAgent/API/MetricsHistory.swift`
- Create: `Sources/LabTetherAgent/API/AlertDeduplicator.swift`
- Modify: `Sources/LabTetherAgent/API/LocalAPIClient.swift`

- [ ] **Step 1: Read LocalAPIClient.swift to identify extraction boundaries**

- [ ] **Step 2: Extract MetricsHistory**

Move the `MetricsHistory` ring buffer class and `SparklineSeries` to `API/MetricsHistory.swift`.

- [ ] **Step 3: Extract AlertDeduplicator**

Move alert deduplication logic (known alert ID tracking, firing/resolved state) to `API/AlertDeduplicator.swift`.

- [ ] **Step 4: Update LocalAPIClient to use extracted types**

LocalAPIClient should delegate to MetricsHistory and AlertDeduplicator rather than implementing the logic inline.

- [ ] **Step 5: Build to verify**

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "refactor: extract MetricsHistory and AlertDeduplicator from LocalAPIClient"
```

---

## Task 6: Extract CrashRestartCoordinator

**Files:**
- Create: `Sources/LabTetherAgent/Process/CrashRestartCoordinator.swift`
- Modify: `Sources/LabTetherAgent/Process/AgentProcess.swift`

- [ ] **Step 1: Read AgentProcess.swift to identify crash restart logic**

Look for: `crashTimestamps`, `crashLoopActive`, `crashCooldownTask`, `attemptCrashRestart()`, constants like `maxCrashRestarts`, `crashWindowSeconds`, `crashCooldownSeconds`.

- [ ] **Step 2: Create CrashRestartCoordinator**

A `@MainActor` class that owns:
- Crash timestamp tracking
- Crash loop detection
- Exponential backoff calculation
- Cooldown timer management
- Published `crashLoopActive` state

Interface: `func recordCrash() -> CrashAction` where `CrashAction` is an enum like `.restart(delay:)` or `.enterCooldown` or `.giveUp`.

- [ ] **Step 3: Update AgentProcess to delegate to coordinator**

AgentProcess keeps process lifecycle. On unexpected termination, calls `coordinator.recordCrash()` and acts on the result.

- [ ] **Step 4: Build to verify**

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "refactor: extract CrashRestartCoordinator from AgentProcess"
```

---

## Task 7: Split AgentSettings Concerns

**Files:**
- Create: `Sources/LabTetherAgent/Settings/AgentEnvironmentBuilder.swift`
- Create: `Sources/LabTetherAgent/Settings/AgentSettingsValidator.swift`
- Modify: `Sources/LabTetherAgent/Settings/AgentSettings.swift`

- [ ] **Step 1: Read AgentSettings.swift to identify extraction boundaries**

Look for: `buildEnvironment()` method, `validationErrors()` method.

- [ ] **Step 2: Extract AgentEnvironmentBuilder**

An enum with a static method `buildEnvironment(from settings: AgentSettings) throws -> [String: String]`. Move all the conditional environment variable logic here.

- [ ] **Step 3: Extract AgentSettingsValidator**

An enum with a static method `validationErrors(for settings: AgentSettings) -> [String]`. Move all validation logic here.

- [ ] **Step 4: Update AgentSettings to delegate**

```swift
func buildEnvironment() throws -> [String: String] {
    try AgentEnvironmentBuilder.buildEnvironment(from: self)
}

func validationErrors() -> [String] {
    AgentSettingsValidator.validationErrors(for: self)
}
```

- [ ] **Step 5: Build to verify**

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "refactor: extract AgentEnvironmentBuilder and AgentSettingsValidator"
```

---

## Task 8: Split Indicators.swift

**Files:**
- Create: 7 new files in `Sources/LabTetherAgent/Components/`
- Delete: `Sources/LabTetherAgent/Components/Indicators.swift`

- [ ] **Step 1: Read Indicators.swift to identify each component and its boundaries**

- [ ] **Step 2: Create 7 individual component files**

| Component | New File |
|-----------|----------|
| `LTHealthOrb` | `Components/HealthOrb.swift` |
| `LTMetricBar` | `Components/MetricBar.swift` |
| `LTSparkline` | `Components/Sparkline.swift` |
| `LTConnectionPulse` | `Components/ConnectionPulse.swift` |
| `LTSpinnerArc` | `Components/SpinnerArc.swift` |
| `LTAnimatedCheck` | `Components/AnimatedCheck.swift` |
| `LTProgressRing` | `Components/ProgressRing.swift` |

- [ ] **Step 3: Delete Indicators.swift**

```bash
git rm Sources/LabTetherAgent/Components/Indicators.swift
```

- [ ] **Step 4: Build to verify**

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "refactor: split Indicators.swift into individual component files"
```

---

## Task 9: Final Verification

- [ ] **Step 1: Clean build**

```bash
swift package clean && swift build
```

- [ ] **Step 2: Run all tests**

```bash
swift test
```

Expected: All 40 tests pass.

- [ ] **Step 3: Verify file count**

```bash
find Sources/LabTetherAgent -name '*.swift' | wc -l
```

Expected: ~68 files (58 + 10 new files created, minus 1 deleted)
