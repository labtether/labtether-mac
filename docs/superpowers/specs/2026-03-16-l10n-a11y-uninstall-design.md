# Localization, Accessibility & Uninstall — Design Spec

**Date:** 2026-03-16
**Scope:** i18n infrastructure + key string localization, VoiceOver accessibility labels, clean uninstall/reset

---

## 1. Localization (i18n Infrastructure)

### Approach

Traditional `Localizable.strings` with `NSLocalizedString` wrapped in a type-safe `L10n` enum. The project is an SPM executable target, so `xcstrings` catalogs are not used.

### Setup

- Create `Sources/LabTetherAgent/Resources/en.lproj/Localizable.strings` (English — default)
- Create `Sources/LabTetherAgent/Resources/es.lproj/Localizable.strings` (Spanish — validation language)
- Create `Sources/LabTetherAgent/Localization/L10n.swift` — enum with static computed properties per string key
- Update `Package.swift`: keep existing `.copy("Resources/Fonts")` for font files, add `.process("Resources/en.lproj")` and `.process("Resources/es.lproj")` to enable localization resource processing without changing how fonts are bundled

### L10n Pattern

```swift
enum L10n {
    private static let bundle = Bundle.module

    static var connected: String {
        NSLocalizedString("status.connected", bundle: bundle, comment: "Agent connection status")
    }
    // ...
}
```

**Note:** SPM generates `Bundle.module` when resources are processed. Use `Bundle.module` (not `Bundle.main`) for correct resource resolution in both the app and test targets.

Views use `L10n.connected` instead of `"Connected"`.

### Strings to Localize (~60 strings)

**Status/Connection:**
- "Connected", "Disconnected", "Connecting", "Starting", "Stopped", "Error", "Reconnecting", "Enrolling", "Auth Failed", "Status Unavailable"

**Menu Bar Quick Actions:**
- "Open Web Console", "View This Device", "Pop Out Window", "View Logs", "Copy Diagnostics", "Test Connection", "Settings"

**Menu Bar Footer:**
- "About", "Setup Wizard", "Reset & Uninstall..."

**Settings Tabs & Labels:**
- "Connection", "Security", "Advanced"
- "Hub URL", "API Token", "Enrollment Token", "Asset ID", "Group ID"
- "Test Connection", "Full Diagnostics...", "Start", "Stop", "Restart"
- "Restart Required"

**Onboarding:**
- "Welcome to LabTether", "Connect this Mac to your LabTether hub for remote management."
- "Authentication", "Use an enrollment token to register this device, or an API token if already enrolled."
- "Identity (Optional)", "Set an asset ID and group, or leave blank for automatic detection."
- "Next", "Back", "Finish & Start Agent", "Skip"
- "Paste from Clipboard"

**About Window:**
- "LabTether Agent", "Version", "Agent:", "Not running", "Website", "Documentation", "Support"

**Session History & Bandwidth:**
- "Session History", "No sessions recorded yet", "Clear History", "Clear Session History?", "This will remove all recorded session events."
- "Today", "Yesterday"
- "Bandwidth", "This Session", "Last 30 Days", "Bandwidth data will appear after the agent runs for a while"

**Connection Diagnostics:**
- "Connection Diagnostics", "Run", "Re-run", "Close", "Copy Results"
- "DNS Resolution", "TCP Connection", "TLS Handshake", "HTTP Reachability"

**Uninstall:**
- "Reset & Uninstall...", "Uninstall LabTether Agent?", "This will remove all configuration, credentials, and history. The app will quit.", "Uninstall & Quit", "Cancel"

### New Files

| File | Purpose |
|------|---------|
| `Localization/L10n.swift` | Type-safe string constants |
| `Resources/en.lproj/Localizable.strings` | English strings |
| `Resources/es.lproj/Localizable.strings` | Spanish strings |

### Modified Files

| File | Change |
|------|--------|
| `Package.swift` | Add `.process("Resources/en.lproj")` and `.process("Resources/es.lproj")` |
| All view files with user-facing strings | Replace hardcoded strings with `L10n.*` |

---

## 2. Accessibility

### Scope

Add VoiceOver labels, values, hints, and traits to all custom components and key interactive elements. Add `accessibilityIdentifier` on key views for future UI testing.

### Custom Components

| Component | File | Label | Value | Trait |
|-----------|------|-------|-------|-------|
| `LTHealthOrb` | `Components/HealthOrb.swift` | "Connection health" | Tone description ("healthy"/"warning"/"critical"/"offline") | `.updatesFrequently` |
| `LTProgressRing` | `Components/ProgressRing.swift` | Passed-in label ("CPU usage") | Percent text ("87 percent") | `.updatesFrequently` |
| `LTSparkline` | `Components/Sparkline.swift` | Passed-in label ("CPU trend") | Hidden (decorative) | |
| `LTMenuBarStatusIcon` | `Presentation/MenuBarStatusIcon.swift` | "Agent status" | Kind description ("healthy"/"warning"/etc.) | |
| `MetricBar` | `Components/Controls.swift` | Passed-in label | Percent text | `.updatesFrequently` |
| `LTAnimatedCheck` | `Components/AnimatedCheck.swift` | "Success" | None | `.isImage` |
| `LTSpinnerArc` | `Components/SpinnerArc.swift` | "Loading" | None | `.isImage` |

For components that need a passed-in accessibility label (ProgressRing, Sparkline, MetricBar), add an `accessibilityLabel: String` parameter with a default empty string. The call sites provide context-specific labels ("CPU usage", "Memory usage", etc.).

### Interactive Elements

| Element | File | Accessibility Addition |
|---------|------|----------------------|
| Token eye toggle | `Views/Settings/SettingsConnectionTab.swift`, `Views/Onboarding/OnboardingAuthStep.swift` | Label: "Show token" / "Hide token" |
| Clipboard paste button | `Views/Onboarding/OnboardingWelcomeStep.swift` | Label: "Paste hub URL from clipboard" |
| Copy fingerprint button | `Views/About/AboutView.swift` | Label: "Copy device fingerprint" |
| Test connection button | `Views/Settings/SettingsConnectionTab.swift` | Hint: "Tests connectivity to the hub server" |
| Clear history button | `Views/PopOut/PopOutSessionHistorySection.swift` | Hint: "Removes all recorded session events" |
| Quick action rows | `Components/Controls.swift` (LTMenuRow) | Ensure label is set from the row's text |

### Accessibility Identifiers

Applied to key views for future UI test targeting:

- `"menubar-status-icon"` — `LTMenuBarStatusIcon`
- `"settings-hub-url"` — Hub URL text field
- `"settings-test-connection"` — Test Connection button
- `"onboarding-next"` — Next button
- `"onboarding-finish"` — Finish & Start Agent button
- `"about-version"` — Version text
- `"popout-bandwidth"` — Bandwidth section
- `"popout-session-history"` — Session History section

### New Files

None — all changes are modifications to existing component and view files.

### Modified Files

| File | Change |
|------|--------|
| `Components/HealthOrb.swift` | Add accessibility label, value, trait |
| `Components/ProgressRing.swift` | Add accessibilityLabel parameter, value, trait |
| `Components/Sparkline.swift` | Add accessibilityLabel parameter, mark decorative |
| `Components/SpinnerArc.swift` | Add accessibility label, trait |
| `Components/AnimatedCheck.swift` | Add accessibility label, trait |
| `Components/Controls.swift` | Add accessibility to MetricBar and LTMenuRow |
| `Presentation/MenuBarStatusIcon.swift` | Add accessibility label, value, identifier |
| `Views/Settings/SettingsConnectionTab.swift` | Add labels, hints, identifiers |
| `Views/Onboarding/OnboardingWelcomeStep.swift` | Add paste button label |
| `Views/Onboarding/OnboardingAuthStep.swift` | Add eye toggle label |
| `Views/Onboarding/OnboardingIdentityStep.swift` | Add finish button identifier |
| `Views/About/AboutView.swift` | Add copy button label, version identifier |
| `Views/PopOut/PopOutSessionHistorySection.swift` | Add section identifier, clear hint |
| `Views/PopOut/PopOutBandwidthSection.swift` | Add section identifier |

---

## 3. Uninstall / Reset

### Trigger

"Reset & Uninstall..." button in `MenuBarFooterSection`, alongside "About" and "Setup Wizard".

### Confirmation

A `.alert` on the menu bar footer section:
- Title: "Uninstall LabTether Agent?"
- Message: "This will remove all configuration, credentials, and history. The app will quit."
- Destructive button: "Uninstall & Quit"
- Cancel button: "Cancel"

### What Gets Removed

| Item | Method |
|------|--------|
| Application Support directory (`~/Library/Application Support/LabTether/`) | `FileManager.default.removeItem(at:)` — removes all files: agent-token, enrollment-token, device keys, agent-config.json, session-history.json, bandwidth-history.json, local-api-auth-token, webrtc-turn-pass |
| Keychain entries | `KeychainSecretStore.deleteStatus(account:)` for "apiToken", "enrollmentToken", "webrtcTurnPass" |
| UserDefaults | `UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)` |
| Login item | Remove via `LoginItemManager` before clearing defaults |
| Running agent process | `agentProcess.forceKill()` before cleanup |

### What Is NOT Removed

- The `.app` bundle itself (user deletes manually by dragging to Trash)
- System-level permissions (screen recording, accessibility — managed by macOS System Settings)

### UninstallManager

A stateless enum with a static method:

```swift
enum UninstallManager {
    static func performUninstall(
        agentProcess: AgentProcess,
        settings: AgentSettings
    ) {
        // Capture path before cleanup (accessing appSupportDirectory has a side effect of creating it)
        let appSupportURL = settings.appSupportDirectory
        // 1. Stop agent
        agentProcess.forceKill()
        // 2. Remove login item
        LoginItemManager.setEnabled(false)
        // 3. Delete Keychain entries (these are the only 3 Keychain-stored secrets)
        _ = KeychainSecretStore.deleteStatus(account: "apiToken")
        _ = KeychainSecretStore.deleteStatus(account: "enrollmentToken")
        _ = KeychainSecretStore.deleteStatus(account: "webrtcTurnPass")
        // 4. Remove Application Support directory (best-effort — partial failure is acceptable)
        try? FileManager.default.removeItem(at: appSupportURL)
        // 5. Clear UserDefaults
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        // 6. Quit
        NSApp.terminate(nil)
    }
}
```

### New Files

| File | Purpose |
|------|---------|
| `Services/UninstallManager.swift` | Static uninstall/reset logic |

### Modified Files

| File | Change |
|------|--------|
| `Views/MenuBar/MenuBarFooterSection.swift` | Add "Reset & Uninstall..." button with confirmation alert |

---

## Cross-Cutting Concerns

### Dependencies Between Features

These 3 features are independent and can be implemented in parallel:
- Localization doesn't depend on accessibility or uninstall
- Accessibility doesn't depend on localization (labels can be hardcoded English first, then switched to `L10n.*` when localization lands)
- Uninstall doesn't depend on either

**Recommended implementation order:** Uninstall first (smallest), then Accessibility (medium, no new files), then Localization last (largest, touches most files). Localization goes last because it modifies the same view files that accessibility modifies — doing accessibility first means localization just replaces the hardcoded accessibility label strings with `L10n.*` calls.

### Testing

- **Localization:** Test that `L10n` properties return non-empty strings. Test that Spanish strings file has the same keys as English.
- **Accessibility:** No automated tests (would require UI testing target). Manual VoiceOver verification.
- **Uninstall:** Test that `UninstallManager.performUninstall` calls the right cleanup methods. Use a protocol or mock for FileManager operations if needed, but given the simplicity, a basic "does it compile" test may suffice.

### File Organization

```
Sources/LabTetherAgent/
├── Localization/
│   └── L10n.swift                    # Type-safe string constants
├── Resources/
│   ├── en.lproj/
│   │   └── Localizable.strings       # English strings
│   └── es.lproj/
│       └── Localizable.strings       # Spanish strings
└── Services/
    └── UninstallManager.swift        # Clean uninstall logic
```
