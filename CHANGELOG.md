# Changelog

All notable changes to the LabTether Mac Agent will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/). The older
`2026.1` entry predates the switch from calendar versions.

## [1.7.0] - unreleased

Changes since the last public release, v1.4.0.

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

### Security
- Releases are signed and notarized on the maintainer's machine. Hosted CI only
  checks the tagged sources and never holds signing credentials.

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

[1.7.0]: https://github.com/labtether/labtether-mac/releases/tag/v1.7.0
[2026.1]: https://github.com/labtether/labtether-mac/releases/tag/v2026.1
