# File Structure Refactor Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize flat `Sources/LabTetherAgent/` (27 files) into domain-grouped subdirectories (58 files across 16 dirs) with no logic changes.

**Architecture:** Pure file moves and extractions. SPM recursively discovers `.swift` files so no Package.swift changes. All types stay `internal` within the same module. View sections that are currently `private struct` become `internal struct` in their own files.

**Tech Stack:** Swift 5.9, SwiftUI, SPM

**Spec:** `docs/superpowers/specs/2026-03-15-file-structure-refactor-design.md`

---

## Chunk 1: Move Unchanged Files

These 21 files move to new directories with zero code modifications. Done in a single task using `git mv` to preserve blame history.

### Task 1: Create directory structure and move files

**Files:**
- Move: 21 files (see list below)
- No modifications

- [ ] **Step 1: Create all target directories**

```bash
cd Sources/LabTetherAgent
mkdir -p App Process Settings API State Presentation Monitoring Notifications
mkdir -p Views/MenuBar Views/PopOut Views/Settings Views/LogViewer Views/Shared
mkdir -p Components DesignSystem
```

- [ ] **Step 2: Move files with git mv**

```bash
# App/
git mv LoginItemManager.swift App/
git mv BundleHelper.swift App/

# Settings/
git mv AgentSettings.swift Settings/
git mv AgentSettingsNormalization.swift Settings/
git mv KeychainSecretStore.swift Settings/

# API/
git mv LocalAPIClient.swift API/

# State/
git mv AgentStatus.swift State/
git mv LogParser.swift State/

# Presentation/
git mv AgentHeroPresentation.swift Presentation/
git mv MetricsPresentation.swift Presentation/
git mv DiagnosticsLogSummary.swift Presentation/
git mv MenuBarStatusIcon.swift Presentation/

# Monitoring/
git mv ScreenSharingMonitor.swift Monitoring/
git mv PerformanceAutomationController.swift Monitoring/
git mv PerformanceSignposts.swift Monitoring/

# Notifications/
git mv NotificationManager.swift Notifications/

# DesignSystem/
git mv DesignTokens.swift DesignSystem/

# Views/
git mv LogBufferView.swift Views/LogViewer/
git mv MetricsView.swift Views/Shared/
git mv AlertsView.swift Views/Shared/
git mv PopOutWindowController.swift Views/PopOut/
```

- [ ] **Step 3: Build to verify**

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: move 21 unchanged files into domain subdirectories"
```

---

## Chunk 2: Split App.swift

Extract `AppState`, `FontLoader`, and `MenuBarLabelPresentation` from `App.swift` into their own files.

### Task 2: Extract FontLoader from App.swift

**Files:**
- Create: `Sources/LabTetherAgent/App/FontLoader.swift`
- Modify: `Sources/LabTetherAgent/App.swift`

- [ ] **Step 1: Create FontLoader.swift**

Copy lines 1-55 from App.swift into `App/FontLoader.swift`. The file contains:
- `import SwiftUI` and `import CoreText`
- `FontLoader` enum (lines 8-55)
- Its own `debugBoot()` private function (copy the `debugBoot` from lines 59-62)

```swift
import SwiftUI
import CoreText

// MARK: - Font Loader

private func debugBoot(_ message: @autoclosure () -> String) {
    guard ProcessInfo.processInfo.environment["LABTETHER_AGENT_DEBUG_BOOT"] == "1" else { return }
    fputs("[boot] \(message())\n", stderr)
}

/// Registers all bundled premium fonts with Core Text at app launch.
enum FontLoader {
    // ... exact content from App.swift lines 10-54
}
```

- [ ] **Step 2: Create MenuBarLabelPresentation.swift**

Copy `MenuBarLabelPresentation` struct (lines 132-163) and `safePercent()` (lines 127-130) into `Presentation/MenuBarLabelPresentation.swift`.

```swift
import SwiftUI

/// Safely converts a Double to Int, returning 0 for NaN/infinity.
private func safePercent(_ value: Double) -> Int {
    guard value.isFinite else { return 0 }
    return Int(value.rounded())
}

struct MenuBarLabelPresentation: Equatable {
    // ... exact content from App.swift lines 132-163
}
```

- [ ] **Step 3: Create AppState.swift**

Copy `AppState` class (lines 217-421) and the `Notification.Name` extension (lines 423-425) into `App/AppState.swift`. Add its own `debugBoot()` copy.

```swift
import SwiftUI
import Combine

private func debugBoot(_ message: @autoclosure () -> String) {
    guard ProcessInfo.processInfo.environment["LABTETHER_AGENT_DEBUG_BOOT"] == "1" else { return }
    fputs("[boot] \(message())\n", stderr)
}

/// Eagerly initialized app state — not lazy like MenuBarExtra content.
@MainActor
final class AppState: ObservableObject {
    // ... exact content from App.swift lines 219-421
}

private extension Notification.Name {
    static let ltPerformanceControlCommand = Notification.Name("LabTetherPerformanceControlCommand")
}
```

- [ ] **Step 4: Trim App.swift to keep only what remains**

App.swift should contain only:
- `import SwiftUI`
- `@main struct LabTetherAgentApp: App { ... }` (lines 64-124)
- `class AppDelegate: NSObject, NSApplicationDelegate { ... }` (lines 166-214)
- `private func debugBoot(...)` (lines 59-62) — still needed by AppDelegate

Remove: `FontLoader` enum, `MenuBarLabelPresentation`, `safePercent()`, `AppState`, `Notification.Name` extension.

- [ ] **Step 5: Move App.swift to App/ directory**

```bash
git mv Sources/LabTetherAgent/App.swift Sources/LabTetherAgent/App/App.swift
```

- [ ] **Step 6: Build to verify**

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor: extract FontLoader, AppState, MenuBarLabelPresentation from App.swift"
```

---

## Chunk 3: Split AgentProcess.swift

### Task 3: Extract LogPipeChunkDecoder from AgentProcess.swift

**Files:**
- Create: `Sources/LabTetherAgent/Process/LogPipeChunkDecoder.swift`
- Modify: `Sources/LabTetherAgent/AgentProcess.swift`

- [ ] **Step 1: Create LogPipeChunkDecoder.swift**

Copy `LogPipeChunkDecoder` class (lines 13-54 of AgentProcess.swift) into `Process/LogPipeChunkDecoder.swift`.

```swift
import Foundation

/// Reassembles newline-delimited log lines from arbitrary pipe read chunks.
///
/// `FileHandle.availableData` does not guarantee chunk boundaries align with
/// line endings, so we keep any trailing fragment until the next read.
final class LogPipeChunkDecoder {
    // ... exact content from AgentProcess.swift lines 14-54
}
```

- [ ] **Step 2: Remove LogPipeChunkDecoder from AgentProcess.swift**

Delete lines 9-54 (the `/// Reassembles...` doc comment through the closing `}` of the class). Keep the `debugBootProcess` function and `AgentProcess` class.

- [ ] **Step 3: Move AgentProcess.swift to Process/**

```bash
git mv Sources/LabTetherAgent/AgentProcess.swift Sources/LabTetherAgent/Process/AgentProcess.swift
```

- [ ] **Step 4: Build to verify**

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: extract LogPipeChunkDecoder from AgentProcess"
```

---

## Chunk 4: Split MenuBarView.swift

### Task 4: Extract MenuBarView sections into individual files

**Files:**
- Create: 9 new files in `Sources/LabTetherAgent/Views/MenuBar/`
- Modify: `Sources/LabTetherAgent/MenuBarView.swift` (trim to shell)

Each `private struct` in MenuBarView.swift becomes an `internal struct` (remove the `private` keyword) in its own file. The line ranges below reference the current MenuBarView.swift:

| Struct | Lines | New File |
|--------|-------|----------|
| `MenuBarBackground` | 190-236 | `Views/MenuBar/MenuBarBackground.swift` |
| `MenuBarHeroSection` | 238-374 | `Views/MenuBar/MenuBarHeroSection.swift` |
| `MenuBarRestartBannerSection` | 376-398 | `Views/MenuBar/MenuBarRestartBannerSection.swift` |
| `MenuBarSystemSection` | 400-436 | `Views/MenuBar/MenuBarSystemSection.swift` |
| `MenuBarConnectionSection` | 438-530 | `Views/MenuBar/MenuBarConnectionSection.swift` |
| `MenuBarAlertsSection` | 532-551 | `Views/MenuBar/MenuBarAlertsSection.swift` |
| `MenuBarScreenSharingSection` | 553-636 | `Views/MenuBar/MenuBarScreenSharingSection.swift` |
| `MenuBarQuickActionsSection` | 638-682 | `Views/MenuBar/MenuBarQuickActionsSection.swift` |
| `MenuBarFooterSection` | 684-758 | `Views/MenuBar/MenuBarFooterSection.swift` |

- [ ] **Step 1: Create each section file**

For each struct listed above:
1. Create a new file at the path shown
2. Add `import SwiftUI` at the top
3. Copy the struct verbatim from MenuBarView.swift
4. Change `private struct` to `struct` (removes file-private restriction)

**MetricsLoadingView note:** `MenuBarSystemSection` references a `MetricsLoadingView()` — check if this is defined elsewhere or inline. If it's defined in MenuBarView.swift, it must move with the section that uses it.

- [ ] **Step 2: Trim MenuBarView.swift to just the parent view**

Keep only:
- `import SwiftUI`
- `struct MenuBarView: View { ... }` (lines 3-188) — the main view body and its helper methods (`copyToClipboard`, `openConsole`, `openDevicePage`, `openLogWindow`, `copyDiagnostics`, `diagnosticsHubSummary`)

Remove all `private struct` sections (lines 190-758).

- [ ] **Step 3: Move MenuBarView.swift to Views/MenuBar/**

```bash
git mv Sources/LabTetherAgent/MenuBarView.swift Sources/LabTetherAgent/Views/MenuBar/MenuBarView.swift
```

- [ ] **Step 4: Build to verify**

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: split MenuBarView into 10 section files"
```

---

## Chunk 5: Split PopOutView.swift

### Task 5: Extract PopOutView sections into individual files

**Files:**
- Create: 7 new files in `Sources/LabTetherAgent/Views/PopOut/`
- Modify: `Sources/LabTetherAgent/PopOutView.swift` (trim to shell)

Line ranges reference current PopOutView.swift:

| Struct | Lines | New File |
|--------|-------|----------|
| `PopOutBackground` | 96-120 | `Views/PopOut/PopOutBackground.swift` |
| `PopOutHeroSection` | 122-243 | `Views/PopOut/PopOutHeroSection.swift` |
| `PopOutSystemSection` | 245-444 | `Views/PopOut/PopOutSystemSection.swift` |
| `PopOutAlertsSection` | 446-463 | `Views/PopOut/PopOutAlertsSection.swift` |
| `PopOutScreenSharingSection` | 465-523 | `Views/PopOut/PopOutScreenSharingSection.swift` |
| `PopOutActionBarSection` | 525-586 | `Views/PopOut/PopOutActionBarSection.swift` |
| `RecentEventsSectionView` + `EventRowView` | 597-699 | `Views/PopOut/RecentEventsSection.swift` |

- [ ] **Step 1: Create each section file**

Same pattern as MenuBarView: `import SwiftUI`, copy struct, change `private struct` to `struct`.

For `PopOutSystemSection`: move the free function `popOutGaugeColor()` (lines 588-592) into the file as a `private` method on `PopOutSystemSection`.

- [ ] **Step 2: Trim PopOutView.swift to just the parent view**

Keep only:
- `import SwiftUI`
- `struct PopOutView: View { ... }` (lines 10-94) — main body and helper methods

Remove all `private struct` sections and the free `popOutGaugeColor()` function.

- [ ] **Step 3: Move PopOutView.swift to Views/PopOut/**

```bash
git mv Sources/LabTetherAgent/PopOutView.swift Sources/LabTetherAgent/Views/PopOut/PopOutView.swift
```

- [ ] **Step 4: Build to verify**

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: split PopOutView into 8 section files"
```

---

## Chunk 6: Split SettingsView.swift

### Task 6: Extract SettingsView tabs and helpers into individual files

**Files:**
- Create: `Sources/LabTetherAgent/Views/Settings/SettingsHelpers.swift`
- Create: `Sources/LabTetherAgent/Views/Settings/SettingsConnectionTab.swift`
- Create: `Sources/LabTetherAgent/Views/Settings/SettingsSecurityTab.swift`
- Create: `Sources/LabTetherAgent/Views/Settings/SettingsAdvancedTab.swift`
- Modify: `Sources/LabTetherAgent/SettingsView.swift` (trim to shell)

Line ranges reference current SettingsView.swift.

**Architecture decision:** The shared helper functions (`settingsCard`, `iconField`, `secureIconField`, `toggleRow`) currently reference `self.focusedField` from the parent view. To make them standalone, convert each to a `View` struct that owns its own `@FocusState`/`@State` or accepts a `FocusState<String?>.Binding`. The cleanest approach: make `iconField` and `secureIconField` into structs (`SettingsIconField`, `SettingsSecureIconField`) that accept a `focusedField` binding, and `toggleRow`/`settingsCard` into structs that don't need focus state.

- [ ] **Step 1: Create SettingsHelpers.swift**

Extract reusable builder components into `Views/Settings/SettingsHelpers.swift` as standalone View structs:

```swift
import SwiftUI

/// Wraps content in a titled glass card.
struct SettingsCardSection<Content: View>: View {
    let title: String
    let glowHint: Color?
    @ViewBuilder let content: () -> Content

    init(_ title: String, glowHint: Color? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.glowHint = glowHint
        self.content = content
    }

    var body: some View {
        // ... content from settingsCard() at lines 787-797
    }
}

/// A text field with a leading icon and focus ring.
struct SettingsIconField: View {
    let icon: String
    let label: String
    @Binding var text: String
    let prompt: String
    var onChange: () -> Void = {}
    @FocusState private var isFocused: Bool

    var body: some View {
        // ... content from iconField() at lines 799-819
        // Replace focusedField == label with isFocused
    }
}

/// A secure text field with a leading icon and focus ring.
struct SettingsSecureIconField: View {
    let icon: String
    let label: String
    @Binding var text: String
    let prompt: String
    var onChange: () -> Void = {}
    @FocusState private var isFocused: Bool

    var body: some View {
        // ... content from secureIconField() at lines 821-842
        // Replace focusedField == label with isFocused
    }
}

/// A toggle row with a leading icon.
struct SettingsToggleRow: View {
    let icon: String
    let label: String
    @Binding var isOn: Bool
    var onChange: (() -> Void)? = nil

    var body: some View {
        // ... content from toggleRow() at lines 844-872
    }
}
```

- [ ] **Step 2: Create SettingsConnectionTab.swift**

Extract `connectionContent` (lines 128-263) as a new `SettingsConnectionTab` view struct. This tab also needs its own `showToken` state (line 9) and uses `SettingsCardSection`, `SettingsIconField`, `SettingsSecureIconField`, `SettingsToggleRow` from SettingsHelpers.

The API Token field with show/hide toggle (lines 137-170) stays inline since it's custom (not a generic helper).

```swift
import SwiftUI

struct SettingsConnectionTab: View {
    @ObservedObject var settings: AgentSettings
    @ObservedObject var agentProcess: AgentProcess
    @ObservedObject var status: AgentStatus
    @State private var showToken = false

    var body: some View {
        LazyVStack(spacing: LT.space12) {
            // ... content from connectionContent (lines 129-263)
            // Replace settingsCard() calls with SettingsCardSection()
            // Replace iconField() calls with SettingsIconField()
            // Replace secureIconField() calls with SettingsSecureIconField()
        }
    }

    private var validationIssues: [String] { settings.validationErrors() }
    private var canStartAgent: Bool {
        settings.isConfigured && validationIssues.isEmpty && !agentProcess.isStarting
    }
}
```

- [ ] **Step 3: Create SettingsSecurityTab.swift**

Extract `securityContent` (lines 267-310) as `SettingsSecurityTab` view struct. `browseCAFile()` (lines 908-921) moves here since it's only used by this tab.

```swift
import SwiftUI
import UniformTypeIdentifiers

struct SettingsSecurityTab: View {
    @ObservedObject var settings: AgentSettings

    var body: some View {
        LazyVStack(spacing: LT.space12) {
            // ... content from securityContent (lines 268-310)
        }
    }

    private func browseCAFile() {
        // ... content from browseCAFile() at lines 908-921
    }
}
```

- [ ] **Step 4: Create SettingsAdvancedTab.swift**

Extract `advancedContent` (lines 314-703) as `SettingsAdvancedTab` view struct. Co-locate:
- `normalizedDockerMode` (lines 761-767)
- `normalizedFilesRootMode` (lines 769-775)
- `normalizedLogLevel` (lines 777-783)
- `displayModeDescription` (lines 745-751)
- `diagRow()` (lines 876-906) with its `@State private var diagHovered` (line 874) — only used by this tab

```swift
import SwiftUI

struct SettingsAdvancedTab: View {
    @ObservedObject var settings: AgentSettings
    @ObservedObject var status: AgentStatus
    @ObservedObject var metadata: LocalAPIMetadataStore
    @State private var diagHovered: String?

    var body: some View {
        LazyVStack(spacing: LT.space12) {
            // ... content from advancedContent (lines 315-703)
        }
    }

    private var normalizedDockerMode: String { /* lines 762-767 */ }
    private var normalizedFilesRootMode: String { /* lines 770-775 */ }
    private var normalizedLogLevel: String { /* lines 778-783 */ }
    private var displayModeDescription: String { /* lines 746-751 */ }

    private func diagRow(icon: String, label: String, value: String, iconColor: Color = LT.textMuted) -> some View {
        // ... content from diagRow() at lines 876-906
    }
}
```

- [ ] **Step 5: Trim SettingsView.swift to shell**

SettingsView.swift keeps only:
- `SettingsView` struct with `body`, `tabBar`, `tabButton`, `statusFooter`
- `validationIssues`, `canStartAgent` computed properties
- Tab switching references new view structs:

```swift
switch selectedTab {
case 0: SettingsConnectionTab(settings: settings, agentProcess: agentProcess, status: status)
case 1: SettingsSecurityTab(settings: settings)
case 2: SettingsAdvancedTab(settings: settings, status: status, metadata: metadata)
default: EmptyView()
}
```

Remove: all tab content computed properties, all helper functions, `showToken` state, `diagHovered` state.

- [ ] **Step 6: Move SettingsView.swift to Views/Settings/**

```bash
git mv Sources/LabTetherAgent/SettingsView.swift Sources/LabTetherAgent/Views/Settings/SettingsView.swift
```

- [ ] **Step 7: Build to verify**

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor: split SettingsView into tab files and shared helpers"
```

---

## Chunk 7: Split Components.swift

### Task 7: Split Components.swift into 8 domain files

**Files:**
- Create: 8 new files in `Sources/LabTetherAgent/Components/`
- Delete: `Sources/LabTetherAgent/Components.swift`

Line ranges reference current Components.swift. Each MARK section maps to a destination file:

**AnimationLifecycle.swift** (lines 1-17):
- `AnimationsActiveKey` (private struct — stays private at file scope)
- `extension EnvironmentValues { animationsActive }`

**Cards.swift** (lines 19-96 + lines 918-954):
- `LTGlassCard`
- `extension View { ltGlassBackground() }`

**Controls.swift** (lines 98-156 + lines 457-476):
- `LTSectionHeader`
- `LTSeparator`

**Indicators.swift** (lines 158-228 + 478-571 + 644-691 + 707-723 + 769-810 + 1070-1124):
- `LTHealthOrb` (lines 158-228)
- `LTMetricBar` (lines 478-516)
- `LTSparkline` (lines 517-571)
- `LTConnectionPulse` (lines 644-691)
- `LTSpinnerArc` (lines 707-723)
- `LTAnimatedCheck` (lines 769-810)
- `LTProgressRing` (lines 1070-1124)

**Badges.swift** (lines 229-288 + 692-706 + 810-830):
- `LTStatusDot` (lines 229-288)
- `LTSeverityEdge` (lines 692-706)
- `LTCapsuleBadge` (lines 810-830)

**Buttons.swift** (lines 289-371 + 877-909):
- `LTPillButton` (lines 289-334)
- `LTPressButtonStyle` (lines 335-343)
- `LTIconBox` (lines 344-371)
- `LTMiniActionButton` (lines 877-909)

**Controls.swift** also gets (lines 372-456 + 1151-1193):
- `LTMenuRow` (lines 372-456)
- `LTCopyRow` (lines 1151-1193)

**Feedback.swift** (lines 831-876 + 1024-1069 + 1194-1226):
- `LTEmptyState` (lines 831-876)
- `LTShimmer` (lines 1024-1069)
- `LTToast` (lines 1194-1226)

**Modifiers.swift** (lines 573-643 + 724-768 + 912-917 + 956-970 + 972-998 + 999-1023 + 1125-1150):
- `LTStaggeredEntrance` (lines 573-599) + `ltStaggered` extension
- `LTAnimatedBorder` (lines 600-643) + `ltAnimatedBorder` extension
- `LTScanShimmer` (lines 724-768)
- `LTValueFlash` (lines 972-998) + `ltValueFlash` extension
- `LTFocusRing` (lines 999-1023) + `ltFocusRing` extension
- `LTBorderTravel` (lines 1125-1150)
- `extension View { ltScanShimmer() }` — extracted from wherever the View extension currently is

- [ ] **Step 1: Create all 8 component files**

For each file:
1. Add `import SwiftUI`
2. Copy the relevant structs/extensions from Components.swift
3. Ensure all `extension View` convenience methods are co-located with their ViewModifier

**Important:** The `extension View` block at lines 912-970 contains 5 methods that must be split across files. Each method gets its own `extension View` block in the file that contains its underlying type:
- `ltStaggered()` (line 914) → Modifiers.swift (with `LTStaggeredEntrance`)
- `ltGlassBackground()` (line 923) → Cards.swift (standalone, no modifier struct)
- `ltAnimatedBorder()` (line 957) → Modifiers.swift (with `LTAnimatedBorder`)
- `ltValueFlash()` (line 962) → Modifiers.swift (with `LTValueFlash`)
- `ltFocusRing()` (line 967) → Modifiers.swift (with `LTFocusRing`)

- [ ] **Step 2: Verify all types are accounted for**

Cross-check: every `struct` and `extension` in Components.swift must appear in exactly one new file. Run:

```bash
grep -c 'struct \|extension ' Components.swift
# Compare with total across all new files
```

- [ ] **Step 3: Delete Components.swift**

```bash
git rm Sources/LabTetherAgent/Components.swift
```

- [ ] **Step 4: Build to verify**

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: split Components.swift into 8 domain files"
```

---

## Chunk 8: Final Verification

### Task 8: Run full build and tests

- [ ] **Step 1: Full clean build**

```bash
swift package clean && swift build
```

Expected: BUILD SUCCEEDED

- [ ] **Step 2: Run all tests**

```bash
swift test
```

Expected: All tests pass (same count as before refactor).

- [ ] **Step 3: Verify file count**

```bash
find Sources/LabTetherAgent -name '*.swift' | wc -l
```

Expected: 58

- [ ] **Step 4: Verify no files remain in root**

```bash
ls Sources/LabTetherAgent/*.swift 2>/dev/null | wc -l
```

Expected: 0 (all files should be in subdirectories)

- [ ] **Step 5: Final commit if any cleanup needed**

```bash
git status
# If clean, no action needed
# If any stragglers, add and commit
```

- [ ] **Step 6: Run tests one more time**

```bash
swift test
```

Expected: All tests pass. Refactor complete.
