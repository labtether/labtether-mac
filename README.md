# LabTether macOS Agent

A menu bar app that connects your Mac to your [LabTether](https://labtether.com) hub — telemetry, remote access, and actions without leaving the menu bar.

## Install

Download **LabTether Agent.app** from [Releases](https://github.com/labtether/labtether-mac/releases/latest), drag to Applications, and launch. The menu bar icon walks you through hub enrollment.

For detailed setup, see the [full guide](https://labtether.com/docs/wiki/agents/macos).

## What It Does

- **System telemetry** — CPU, memory, disk, network, and temperature. Reported every heartbeat.
- **Remote terminal & desktop** — Open a shell or desktop session from the LabTether console. No VNC clients needed.
- **Menu bar status** — Connection state, alerts, and quick actions at a glance.
- **Service management** — Monitor and manage launchd services from the dashboard.
- **Notifications** — Native macOS alerts for hub events.

## Build From Source

Requires Xcode with Swift 5.9+ and macOS 13+ deployment target.

```bash
swift build
```

The Mac agent bundles the Go `labtether-agent` binary. See `AGENT_VERSION` for the pinned release.

Most users should grab the pre-built app from [Releases](https://github.com/labtether/labtether-mac/releases/latest).

## Links

| | |
|---|---|
| **LabTether Hub** | [github.com/labtether/labtether](https://github.com/labtether/labtether) |
| **Docs** | [labtether.com/docs](https://labtether.com/docs) |
| **Website** | [labtether.com](https://labtether.com) |

## License

Copyright 2026 LabTether. All rights reserved. See [LICENSE](LICENSE).
