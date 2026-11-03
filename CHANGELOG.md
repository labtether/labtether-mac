# Changelog

All notable changes to the LabTether Mac Agent will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/). The older
`2026.1` entry predates the switch from calendar versions.

## [2.0.0] - unreleased

The version moves to 2.0.0 with the LabTether 2.0 release. The bundled agent
core is `labtether-agent v2.0.0`.

### Changed
- The app uses the LabTether 2.0 look: the Hub console's light and dark
  colours, following the system appearance, the system font, and plain sheets
  in place of glass cards, glows and icon boxes. Text meets WCAG AA contrast.
- The menu bar icon is drawn from the mascot. It shows a dot only when
  something needs attention: amber for an alert or high usage, red for a
  critical alert or a refused token. Starting, offline and stopped dim it.
- The menu bar window shows status, usage once, alerts, actions and one
  footer line with the version and "Update available".
- The pop-out lists alerts first, then usage, recent events, bandwidth,
  sessions and Remote View. Agent controls are in its ⋯ menu.
- Setup is one window: Hub address, token, test and Connect. Asset ID and
  group ID are under Advanced.
- Settings opens on the agent's status, then the Hub form. Asset ID and group
  ID are under Identity; paths, process ID and fingerprint are under
  Advanced › Diagnostics.
- Status reads as a word plus a time, for example "Stopped · since 21:12".
  Notifications and messages use plain wording.
- The quick connection test shows "Reachable · 24 ms" instead of copying
  the result to the clipboard.
- The setup hint points to **Settings › Agents** in the Hub, where the
  address and enrollment tokens are.

### Fixed
- The signed release script no longer stops while writing the release record
  on macOS 27.2, where `plutil` cannot add keys to a JSON file.
- **Open Console**, the device link and the alert links open the Hub's web
  console. With the Hub URL that Add device shows (the Hub API port, 8443)
  they opened the API's JSON reply instead. The app now asks the Hub which
  console to open each time it connects.
- The app starts its agent core when it runs from a folder under /private,
  such as the copy macOS runs when the app is opened from Downloads without
  moving it first. It used to stop the core it had started and show
  "Failed to launch".

## [1.7.1] - 2026-10-31

Changes since the last public release, v1.4.0. v1.7.0 was tagged but never
released.

### Added
- An "Update available" item appears in the menu when a newer signed release
  is published. The app asks GitHub at most once a day, opens the release page
  when clicked, and never downloads anything itself. Turn it off with
  Settings > Advanced > Check for App Updates Daily.
- Hub URLs on a loopback address work, so a local tunnel to the Hub can be used.
- Launching with `--state-directory PATH` keeps that copy's settings and
  secrets apart from the installed app.

### Changed
- The bundled agent core now updates only together with the signed app; it no
  longer replaces itself.
- The bundled agent core is built with Go 1.27.3.
- The Hub is told which remote desktop features this Mac supports.
- Custom CA trust and the enrollment group now match what the Hub expects.
- Numeric settings such as ports and intervals are checked before they are used.
- Agent logs use bounded memory. Very long log lines are split instead of
  growing without limit.
- Decorative pulses and glows play once, and stay off with Reduce Motion or
  Low Power Mode.

### Fixed
- The Screen Sharing "Fix" button now shows an error when macOS could not grant
  control access, instead of failing silently.
- The Documentation link in About opens https://labtether.com/docs.
- A stopped or replaced agent can no longer change the status shown in the menu.
- A settings save that fails is now reported instead of ignored.
- The connection test accepts the same Hub URLs and CA files as the agent.
- The menu window no longer collapses, and a stale "starting" state no longer
  sticks.
- The Screen Sharing grant command and console links are escaped safely.
- With Allow Remote Overrides off, settings pushed earlier by the Hub are
  removed on the next start, so the agent runs the values shown in Settings.
- The macOS Local Network prompt now says why the app asks: "LabTether Agent
  connects to your LabTether Hub on your local network."
- While the agent cannot reach the Hub, the menu shows why (for example
  "Can't reach the Hub" or "The Hub's certificate is not trusted") instead
  of "transient". When macOS blocks Local Network access, it says where to
  turn it on.
- `--state-directory` spelled under `/private` (for example
  `/private/var/folders/...`) no longer makes the app exit at start.

### Security
- Releases are signed and notarized on the maintainer's machine. Hosted CI only
  checks the tagged sources and never holds signing credentials.
- Changing the Hub URL no longer sends the token saved for the previous Hub to
  the new address. On the next start the old token, the enrollment record and
  the previous Hub's CA are removed, and the app asks for an enrollment token
  from the new Hub. A token typed after the change is kept.
- The app no longer suggests the Hub owner token. Hubs from 1.7.1 refuse it
  from agents. If you saved the owner token here, clear it in Settings, enroll
  with an enrollment token, and change the owner token on the Hub.
- The TURN password is no longer written to a file, because macOS does not use
  WebRTC. A copy left by an older version is removed on the next start.
- Release builds no longer listen for the profiling notification that any
  local app could send to stop the agent.
- Reset & Uninstall removes the Hub's SSH key line that the agent added to
  `~/.ssh/authorized_keys`.

## [2026.1] - Unreleased

### Added
- macOS menu bar agent with health gauges, alerts feed, and dynamic status indicator
- Pop-out floating dashboard with sparklines and live events feed
- LocalAPIClient to poll the bundled Go agent's HTTP API
- Session history tracker with persistence and pop-out display
- Bandwidth tracker with hourly bucketing, persistence, and 7-day bar chart
- Connection diagnostics sheet with live DNS/TCP/TLS/HTTP step waterfall
- ConnectionTester service for full diagnostic sweep
- Three-step onboarding wizard
- About view with version, fingerprint, and external links
- UninstallManager with Reset & Uninstall wired into menu bar
- WebRTC remote desktop with Screen Recording permission handling
- Localization infrastructure (L10n) with English and Spanish string files
- Accessibility identifiers, labels, and hints across all views (VoiceOver support)
- Design token system with premium components and bundled fonts (JetBrains Mono)
- Glass-morphism treatment for alerts, settings, and tab surfaces
- Exponential backoff reconnect with NWPathMonitor network awareness
- DiagnosticsCollector, CrashRestartCoordinator, and AgentEnvironmentBuilder services
- Tailscale Serve integration, TLS management, and agent enrollment preference

### Changed
- Decomposed MenuBarView into 10 section files
- Split SettingsView into per-tab files with shared helpers
- Split Components.swift and Indicators.swift into individual domain files
- Extracted LogPipeChunkDecoder, FontLoader, AppState, and MenuBarLabelPresentation from monolithic files
- Moved source files into domain subdirectories
- Centralized metric gauge color thresholds and AgentHeroPresentation resolution
- Replaced hardcoded UI strings with L10n constants
- Pinned agent version to v2026.1

### Fixed
- Audit event early-break bug in menu bar animations
- NaN, race conditions, and alert dedup issues in mini dashboard
- Shadow layer reduction and cached MetricsHistory for smoother performance
- Gated all repeatForever animations on popover visibility to eliminate idle CPU usage
- @Sendable annotation and unused result warning in ConnectionTester

[2.0.0]: https://github.com/labtether/labtether-mac/releases/tag/v2.0.0
[1.7.1]: https://github.com/labtether/labtether-mac/releases/tag/v1.7.1
[2026.1]: https://github.com/labtether/labtether-mac/releases/tag/v2026.1
