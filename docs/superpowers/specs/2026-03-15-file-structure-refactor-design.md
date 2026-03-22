# File Structure Refactor Design

**Date:** 2026-03-15
**Status:** Approved

## Goal

Reorganize the flat `Sources/LabTetherAgent/` directory (27 Swift files, ~9,450 lines) into logical subdirectories grouped by domain. Split oversized files into focused units. No logic changes — purely structural.

## Current State

All 27 source files live flat in `Sources/LabTetherAgent/`. The largest files mix multiple concerns:

| File | Lines | Issue |
|------|-------|-------|
| Components.swift | 1,226 | 20+ unrelated UI components |
| SettingsView.swift | 922 | 3 tab contents + shared builders |
| LogBufferView.swift | 893 | Cohesive — keep as-is |
| MenuBarView.swift | 758 | 9 section structs in one file |
| LocalAPIClient.swift | 747 | Cohesive enough — keep as-is |
| PopOutView.swift | 699 | 8 section structs in one file |
| AgentSettings.swift | 658 | Keep as-is (splitting adds coupling) |
| AgentProcess.swift | 451 | Extract LogPipeChunkDecoder |
| App.swift | 425 | 4 distinct types crammed together |

## Proposed Structure

```
Sources/LabTetherAgent/
├── App/
│   ├── App.swift
│   ├── AppState.swift
│   ├── FontLoader.swift
│   ├── LoginItemManager.swift
│   └── BundleHelper.swift
│
├── Process/
│   ├── AgentProcess.swift
│   └── LogPipeChunkDecoder.swift
│
├── Settings/
│   ├── AgentSettings.swift
│   ├── AgentSettingsNormalization.swift
│   └── KeychainSecretStore.swift
│
├── API/
│   └── LocalAPIClient.swift
│
├── State/
│   ├── AgentStatus.swift
│   └── LogParser.swift
│
├── Presentation/
│   ├── AgentHeroPresentation.swift
│   ├── MenuBarLabelPresentation.swift
│   ├── MetricsPresentation.swift
│   ├── DiagnosticsLogSummary.swift
│   └── MenuBarStatusIcon.swift
│
├── Monitoring/
│   ├── ScreenSharingMonitor.swift
│   ├── PerformanceAutomationController.swift
│   └── PerformanceSignposts.swift
│
├── Notifications/
│   └── NotificationManager.swift
│
├── Views/
│   ├── MenuBar/
│   │   ├── MenuBarView.swift
│   │   ├── MenuBarBackground.swift
│   │   ├── MenuBarHeroSection.swift
│   │   ├── MenuBarRestartBannerSection.swift
│   │   ├── MenuBarSystemSection.swift
│   │   ├── MenuBarConnectionSection.swift
│   │   ├── MenuBarAlertsSection.swift
│   │   ├── MenuBarScreenSharingSection.swift
│   │   ├── MenuBarQuickActionsSection.swift
│   │   └── MenuBarFooterSection.swift
│   │
│   ├── PopOut/
│   │   ├── PopOutView.swift
│   │   ├── PopOutWindowController.swift
│   │   ├── PopOutBackground.swift
│   │   ├── PopOutHeroSection.swift
│   │   ├── PopOutSystemSection.swift
│   │   ├── PopOutAlertsSection.swift
│   │   ├── PopOutScreenSharingSection.swift
│   │   ├── PopOutActionBarSection.swift
│   │   └── RecentEventsSection.swift
│   │
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   ├── SettingsConnectionTab.swift
│   │   ├── SettingsSecurityTab.swift
│   │   ├── SettingsAdvancedTab.swift
│   │   └── SettingsHelpers.swift
│   │
│   ├── LogViewer/
│   │   └── LogBufferView.swift
│   │
│   └── Shared/
│       ├── MetricsView.swift
│       └── AlertsView.swift
│
├── Components/
│   ├── AnimationLifecycle.swift
│   ├── Buttons.swift
│   ├── Cards.swift
│   ├── Badges.swift
│   ├── Controls.swift
│   ├── Indicators.swift
│   ├── Feedback.swift
│   └── Modifiers.swift
│
├── DesignSystem/
│   └── DesignTokens.swift
│
└── Resources/
    ├── Fonts/
    └── Info.plist
```

**Result:** 27 files become 58 files across 16 directories. Average file size drops from ~350 lines to ~165 lines.

## Extraction Details

### App.swift (425 lines) -> 4 files

**App.swift** keeps:
- `@main LabTetherAgentApp` struct (scenes, body)
- `AppDelegate` class (lifecycle, duplicate detection)
- `debugBoot()` private helper
- `safePercent()` private helper

**AppState.swift** gets:
- `AppState` class (lines 217-421)
- `Notification.Name` extension for `ltPerformanceControlCommand`
- Own `debugBoot()` copy (same pattern, `[boot]` prefix)

**FontLoader.swift** gets:
- `FontLoader` enum (lines 8-55)
- `debugBoot()` reference — pass as closure or use own copy

**MenuBarLabelPresentation.swift** gets:
- `MenuBarLabelPresentation` struct (lines 132-163)
- `safePercent()` helper moves here as `private`

### MenuBarView.swift (758 lines) -> 10 files

Each `private struct` becomes `internal struct` in its own file:

| Struct | New File | Approx Lines |
|--------|----------|-------------|
| `MenuBarView` (body + helpers) | MenuBarView.swift | ~100 |
| `MenuBarBackground` | MenuBarBackground.swift | ~50 |
| `MenuBarHeroSection` | MenuBarHeroSection.swift | ~140 |
| `MenuBarRestartBannerSection` | MenuBarRestartBannerSection.swift | ~25 |
| `MenuBarSystemSection` | MenuBarSystemSection.swift | ~40 |
| `MenuBarConnectionSection` | MenuBarConnectionSection.swift | ~95 |
| `MenuBarAlertsSection` | MenuBarAlertsSection.swift | ~25 |
| `MenuBarScreenSharingSection` | MenuBarScreenSharingSection.swift | ~85 |
| `MenuBarQuickActionsSection` | MenuBarQuickActionsSection.swift | ~50 |
| `MenuBarFooterSection` | MenuBarFooterSection.swift | ~80 |

**Access control change:** Remove `private` from each struct declaration. Swift default `internal` access is sufficient within the same SPM target.

### PopOutView.swift (699 lines) -> 8 files (+1 moved in)

Same pattern as MenuBarView. Each `private struct` gets its own file with `internal` access.

| Struct | New File | Approx Lines |
|--------|----------|-------------|
| `PopOutView` (body + helpers) | PopOutView.swift | ~95 |
| `PopOutBackground` | PopOutBackground.swift | ~25 |
| `PopOutHeroSection` | PopOutHeroSection.swift | ~125 |
| `PopOutSystemSection` | PopOutSystemSection.swift | ~200 |
| `PopOutAlertsSection` | PopOutAlertsSection.swift | ~20 |
| `PopOutScreenSharingSection` | PopOutScreenSharingSection.swift | ~60 |
| `PopOutActionBarSection` | PopOutActionBarSection.swift | ~65 |
| `RecentEventsSectionView` + `EventRowView` | RecentEventsSection.swift | ~110 |

The free function `popOutGaugeColor()` moves into `PopOutSystemSection` as a `private` method.

### SettingsView.swift (922 lines) -> 5 files

| Content | New File | Approx Lines |
|---------|----------|-------------|
| `SettingsView` (body, tabBar, statusFooter, normalizers) | SettingsView.swift | ~130 |
| `connectionContent` | SettingsConnectionTab.swift | ~140 |
| `securityContent` | SettingsSecurityTab.swift | ~50 |
| `advancedContent` | SettingsAdvancedTab.swift | ~395 |
| Shared builders (settingsCard, iconField, secureIconField, toggleRow, diagRow, browseCAFile) | SettingsHelpers.swift | ~210 |

**Approach for tab extraction:** Each tab becomes its own `View` struct that receives the same `@ObservedObject` bindings. The shared builder functions move to `SettingsHelpers.swift` as free functions or a helper enum to avoid duplication.

### AgentProcess.swift (451 lines) -> 2 files

- `LogPipeChunkDecoder` (lines 13-54) moves to `Process/LogPipeChunkDecoder.swift`
- Already `final class` with no `private` dependency on AgentProcess — clean extraction

### Components.swift (1,226 lines) -> 8 files

| File | Types |
|------|-------|
| AnimationLifecycle.swift | `AnimationsActiveKey`, `EnvironmentValues.animationsActive` |
| Buttons.swift | `LTMiniActionButton`, `LTPillButton`, `LTPressButtonStyle`, `LTIconBox` |
| Cards.swift | `LTGlassCard`, `ltGlassBackground` modifier |
| Badges.swift | `LTCapsuleBadge`, `LTStatusDot`, `LTSeverityEdge` |
| Controls.swift | `LTMenuRow`, `LTCopyRow`, `LTSectionHeader`, `LTSeparator` |
| Indicators.swift | `LTHealthOrb`, `LTMetricBar`, `LTSparkline`, `LTSpinnerArc`, `LTConnectionPulse`, `LTProgressRing`, `LTAnimatedCheck` |
| Feedback.swift | `LTToast`, `LTEmptyState`, `LTShimmer` |
| Modifiers.swift | `ltScanShimmer`, `ltValueFlash`, `ltFocusRing`, `LTBorderTravel`, `LTStaggeredEntrance` (`ltStaggered`), `LTAnimatedBorder` (`ltAnimatedBorder`) |

**View extension co-location:** Each `extension View` convenience method lives in the same file as its underlying ViewModifier/View struct (e.g., `ltGlassBackground` in Cards.swift, `ltScanShimmer` and `ltStaggered` in Modifiers.swift).

### Files that move without changes

These files move to their new directory with zero code modifications:

| File | Destination |
|------|-------------|
| LoginItemManager.swift | App/ |
| BundleHelper.swift | App/ |
| AgentSettings.swift | Settings/ |
| AgentSettingsNormalization.swift | Settings/ |
| KeychainSecretStore.swift | Settings/ |
| LocalAPIClient.swift | API/ |
| AgentStatus.swift | State/ |
| LogParser.swift | State/ |
| AgentHeroPresentation.swift | Presentation/ |
| MetricsPresentation.swift | Presentation/ |
| DiagnosticsLogSummary.swift | Presentation/ |
| MenuBarStatusIcon.swift | Presentation/ |
| ScreenSharingMonitor.swift | Monitoring/ |
| PerformanceAutomationController.swift | Monitoring/ |
| PerformanceSignposts.swift | Monitoring/ |
| NotificationManager.swift | Notifications/ |
| DesignTokens.swift | DesignSystem/ |
| LogBufferView.swift | Views/LogViewer/ |
| MetricsView.swift | Views/Shared/ |
| AlertsView.swift | Views/Shared/ |
| PopOutWindowController.swift | Views/PopOut/ |

## Build & Package Impact

- **Package.swift:** No changes. SPM recursively discovers `.swift` files under the target path.
- **Excluded paths:** `CLAUDE.md` and `Resources/Info.plist` excludes still work (both stay in place).
- **Resource copying:** `Resources/Fonts` stays at `Resources/Fonts` — no change.
- **Tests:** No changes needed. Tests import `@testable import LabTetherAgent` and all types remain `internal`.
- **Access control:** Only change is `private struct` -> `struct` (internal) for extracted view sections.

## What We Are NOT Doing

- No logic changes, refactoring, or new abstractions
- Not splitting `AgentSettings.swift` (658 lines) — it's one cohesive settings object
- Not splitting `LocalAPIClient.swift` (747 lines) — stores are tightly coupled
- Not splitting `LogBufferView.swift` (893 lines) — it's a cohesive viewer/renderer pair
- Not creating new SPM modules or changing the build graph
- Not restructuring test files
- Not adding documentation, comments, or type annotations to moved files

## Risk Assessment

**Low risk:**
- All changes are file moves and access control tweaks
- Same SPM target, same module, same test surface
- `git mv` preserves blame history for pure moves
- Extractions are mechanical (existing MARK sections and private structs define the boundaries)

**Verification:**
- `swift build` must pass after each phase
- `swift test` must pass after completion
- No behavioral changes to verify — pure structural refactor
