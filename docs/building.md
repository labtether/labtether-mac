# Build from source

Use stable Xcode 27 for local builds. The macOS 13 deployment target and
Swift 5 language mode remain supported. Hosted CI uses the current stable
`macos-26` image (Xcode 26.6 / Swift 6.3.3) until Xcode 27 is available on
a stable runner image; no preview or larger paid runner is required.
The sibling [`labtether-agent`](https://github.com/labtether/labtether-agent)
checkout and its declared Go toolchain are also required because the native app
always ships the Go agent core inside its signed application bundle.

```bash
git clone https://github.com/labtether/labtether-agent ../labtether-agent
./scripts/build-app.sh --configuration release
```

The result is `build/LabTether Agent.app`. The builder fails if the Go child,
Swift host, resource bundle, icon, expected architecture, or signature is
missing. Use `LABTETHER_AGENT_REPO` when the agent checkout is elsewhere.

To put that app in a disk image with an Applications shortcut:

```bash
./scripts/build-dmg.sh --app "build/LabTether Agent.app" --output build/labtether-agent-macos-universal.dmg
```

Maintainers should follow the [local-only signing, notarization, and publication
runbook](releasing.md). Hosted CI verifies source tags but never receives
signing or notarization credentials and never publishes release bytes.

For most users, download the pre-built app from [Releases](https://github.com/labtether/labtether-mac/releases/latest) instead.

## Mac App Store edition

The same source builds a second app for the Mac App Store:

```bash
./scripts/build-app.sh --edition store --configuration release
```

It needs `cargo` and the Rust agent in the sibling checkout
(`labtether-agent/rust`). The script compiles the Swift app with
`-D LABTETHER_STORE`, builds the Rust agent (`labtether-agent-rs`, the
macOS monitoring edition) and checks its version before signing, puts it in
`Contents/MacOS/labtether-agent`, and signs both ad hoc with the
entitlements in `packaging/app-store/`. Apple Distribution signing,
provisioning and upload are separate steps the owner does. For a QA copy,
`LABTETHER_APP_BUNDLE_ID` and `LABTETHER_APP_DISPLAY_NAME` set another
identifier and name (Store edition only).

### Entitlements

App (`packaging/app-store/LabTetherAgent.entitlements`):

| Key | Why |
|---|---|
| `com.apple.security.app-sandbox` | Required for the Mac App Store |
| `com.apple.security.network.client` | The Hub connection, the app's connection test and the Hub's console address; the agent's connection runs under the app's sandbox |
| `com.apple.security.network.server` | The agent serves its status to the app on 127.0.0.1 (`AGENT_PORT`); without it the sandbox refuses the bind |
| `com.apple.security.files.user-selected.read-only` | Reading the Hub CA file picked in Settings › Security |

Agent (`packaging/app-store/labtether-agent.entitlements`):
`com.apple.security.app-sandbox` and `com.apple.security.inherit`, the only
keys Apple allows a helper tool in a sandboxed app. No temporary exception
and no Keychain group: the app's Keychain items work in the sandbox without
one.

### Info.plist

Only the Store edition changes the copied `Info.plist`:
`LSApplicationCategoryType` is `public.app-category.utilities`, and a QA
copy may override `CFBundleIdentifier`, `CFBundleName` and
`CFBundleDisplayName`. `NSLocalNetworkUsageDescription` stays.

### What the Store edition leaves out

| Left out or changed | Where | Why |
|---|---|---|
| Update check, its setting and the "Update available" link | `AppUpdateChecker` (request compiled out), `AppState`, `SettingsStartupSection`, `MenuBarFooterSection` | The App Store updates the app; Guideline 2.4.5(vii) allows no other update mechanism |
| Screen Sharing check, its admin "Fix" and the Remote View settings | `ScreenSharingMonitor` (never runs; the admin grant is compiled out), `SettingsAdvancedTab` | Guideline 2.4.5(v) forbids asking for admin rights; the monitoring agent has no Remote View or clipboard |
| Hub SSH key removal in Reset and uninstall | `UninstallManager` (compiled out) | The agent adds no key, has no `ssh-key` command, and the sandbox keeps it out of `~/.ssh` |
| Docker, file access, service discovery, WebRTC and capture settings | `SettingsAdvancedTab`; `AgentEnvironmentBuilder` passes none of them | The monitoring agent has none of those pages; a hidden value must not reach it |
| Hub CA file | `SettingsPickedCARow`, `PickedHubCA.swift` | A typed path cannot be read in the sandbox: the file comes from the file panel, a copy in the app's container goes to the agent, and a security-scoped bookmark lets each start notice a changed or removed file |
| Local Network step in setup | `LocalNetworkStep`, `LocalNetworkAccess` | macOS blocks a new app from the LAN until the person allows it; setup says so and opens the setting when access is off |
| "Monitoring only" under the agent's state | `AgentStatusText` | The agent offers no actions |
| Keychain service | `AppEdition.keychainService` | The app's bundle identifier, so a Store and a direct install never share tokens |
