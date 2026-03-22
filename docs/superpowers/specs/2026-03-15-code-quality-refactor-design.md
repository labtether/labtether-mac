# Code Quality Refactor Design

**Date:** 2026-03-15
**Status:** Approved

## Goal

Eliminate duplicated logic, extract mixed concerns, and centralize scattered patterns across the codebase. No behavioral changes — purely structural improvements.

## Items

### 1. Centralize Hero Presentation Resolution

**Problem:** `AgentHeroPresentation.resolve()` is called with identical 9 parameters in 3 files: `MenuBarHeroSection.swift`, `PopOutHeroSection.swift`, `MenuBarBackground.swift`.

**Fix:** Add a computed property to a shared location. Since all three views already have access to `status`, `agentProcess`, and `runtime` as `@ObservedObject`, create a static helper or extension that takes these objects and returns the presentation. The cleanest approach: add a convenience initializer or factory on `AgentHeroPresentation` that takes the observable objects directly.

**Files:**
- Modify: `Presentation/AgentHeroPresentation.swift` — add convenience factory
- Modify: `Views/MenuBar/MenuBarHeroSection.swift` — use factory
- Modify: `Views/MenuBar/MenuBarBackground.swift` — use factory
- Modify: `Views/PopOut/PopOutHeroSection.swift` — use factory

### 2. Extract VisibilityGate Protocol

**Problem:** `setMenuVisible()`/`setPanelVisible()`/`anySurfaceVisible` pattern is copy-pasted across `LocalAPIClient`, `ScreenSharingMonitor`, and `AgentStatus` (~30 LOC each).

**Fix:** Create a `VisibilityAware` protocol with stored property requirements and default computed property for `anySurfaceVisible`. Each class adopts the protocol.

**Files:**
- Create: `App/VisibilityAware.swift` — protocol definition
- Modify: `API/LocalAPIClient.swift` — adopt protocol
- Modify: `Monitoring/ScreenSharingMonitor.swift` — adopt protocol
- Modify: `State/AgentStatus.swift` — adopt protocol

### 3. Centralize Gauge Color Thresholds

**Problem:** CPU/memory/disk color logic (>90 = bad, >75 = warn, else ok) is hardcoded in `MenuBarHeroSection`, `PopOutSystemSection`, `MetricsView`, and others.

**Fix:** Add a static method `MetricGaugePresentation.color` or similar on the existing `MetricsPresentation` types. Views call this instead of inline threshold checks.

**Files:**
- Modify: `Presentation/MetricsPresentation.swift` — add color helper
- Modify: `Views/MenuBar/MenuBarHeroSection.swift` — use helper
- Modify: `Views/PopOut/PopOutSystemSection.swift` — use helper, remove `popOutGaugeColor()`
- Modify: `Views/Shared/MetricsView.swift` — use helper

### 4. Extract LogLine Model from LogBufferView

**Problem:** `LogLine` struct with 10+ parsing methods is embedded inside `LogBufferView.swift` (893 lines). It's a data model, not a view.

**Fix:** Move `LogLine`, `LogLevel`, `LogBuffer`, and related parsing types to `State/LogLine.swift`. Keep only the SwiftUI view code in `LogBufferView.swift`.

**Files:**
- Create: `State/LogLine.swift` — LogLine struct, LogLevel enum, LogBuffer class
- Modify: `Views/LogViewer/LogBufferView.swift` — remove extracted types

### 5. Split LocalAPIClient into Focused Types

**Problem:** `LocalAPIClient.swift` (747 lines) mixes HTTP polling, metrics aggregation, alert deduplication, ETag caching, and network monitoring.

**Fix:** Extract:
- `MetricsHistory` ring buffer + sparkline caching → `API/MetricsHistory.swift`
- Alert deduplication logic → `API/AlertDeduplicator.swift`
- Keep `LocalAPIClient` as the polling orchestrator + facade

The 4 store classes (`LocalAPIRuntimeStore`, `LocalAPIMetricsStore`, `LocalAPIAlertsStore`, `LocalAPIMetadataStore`) stay in LocalAPIClient.swift — they're thin ObservableObject wrappers tightly coupled to it.

**Files:**
- Create: `API/MetricsHistory.swift`
- Create: `API/AlertDeduplicator.swift`
- Modify: `API/LocalAPIClient.swift` — remove extracted types, delegate to new classes

### 6. Extract CrashRestartCoordinator from AgentProcess

**Problem:** `AgentProcess.swift` (404 lines) mixes process lifecycle with crash detection/backoff/cooldown logic.

**Fix:** Extract crash restart logic into `CrashRestartCoordinator` — a focused class that tracks crash timestamps, manages backoff delays, detects crash loops, and handles cooldown recovery.

**Files:**
- Create: `Process/CrashRestartCoordinator.swift`
- Modify: `Process/AgentProcess.swift` — delegate crash logic to coordinator

### 7. Split AgentSettings Concerns

**Problem:** `AgentSettings.swift` (658 lines) mixes @AppStorage bindings, keychain sync, environment variable building (125 lines), and validation.

**Fix:** Extract:
- `buildEnvironment()` → `Settings/AgentEnvironmentBuilder.swift`
- `validationErrors()` → `Settings/AgentSettingsValidator.swift`
- Keep AgentSettings as the observable property store + keychain sync

**Files:**
- Create: `Settings/AgentEnvironmentBuilder.swift`
- Create: `Settings/AgentSettingsValidator.swift`
- Modify: `Settings/AgentSettings.swift` — delegate to new types

### 8. Split Indicators.swift

**Problem:** 7 unrelated indicator components (328 lines) in one file.

**Fix:** Each component gets its own file in `Components/`.

**Files:**
- Create: `Components/HealthOrb.swift` — LTHealthOrb
- Create: `Components/MetricBar.swift` — LTMetricBar
- Create: `Components/Sparkline.swift` — LTSparkline
- Create: `Components/ConnectionPulse.swift` — LTConnectionPulse
- Create: `Components/SpinnerArc.swift` — LTSpinnerArc
- Create: `Components/AnimatedCheck.swift` — LTAnimatedCheck
- Create: `Components/ProgressRing.swift` — LTProgressRing
- Delete: `Components/Indicators.swift`

## What We Are NOT Doing

- No behavioral changes
- No new features
- No test changes (all types stay internal, same module)
- No Package.swift changes
- Not restructuring tests

## Verification

- `swift build` must pass after each item
- `swift test` must pass after all items complete
