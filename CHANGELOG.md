# Changelog

All notable changes to the LabTether Mac Agent will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [CalVer](https://calver.org/) versioning: `YYYY.N`.

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

[2026.1]: https://github.com/labtether/mac-agent/releases/tag/v2026.1
