# LabTether macOS Agent

The macOS menu bar agent for [LabTether](https://labtether.com) — reports telemetry, executes actions, and enables remote access for your Mac.

## Install

Download **LabTether Agent.app** from [Releases](https://github.com/labtether/labtether-mac/releases/latest), drag it to Applications, and launch. The menu bar icon guides you through hub enrollment.

For detailed setup, see the [agent setup guide](https://labtether.com/docs/wiki/agents/macos).

## What It Does

- **System telemetry** — CPU, memory, disk, network, and temperature reported to your hub.
- **Remote access** — Terminal and desktop sessions from the LabTether console.
- **Menu bar status** — Connection state, alerts, and quick actions at a glance.
- **Service management** — Monitor and manage launchd services remotely.
- **Notifications** — Native macOS alerts for hub events.

## Build From Source

Requires Xcode with Swift 5.9+ and macOS 13+ deployment target.

```bash
swift build
```

The Mac agent bundles the Go `labtether-agent` binary. See `AGENT_VERSION` for the pinned version.

For most users, download the pre-built app from [Releases](https://github.com/labtether/labtether-mac/releases/latest) instead.

## Links

- **LabTether Hub** — [github.com/labtether/labtether](https://github.com/labtether/labtether)
- **Documentation** — [labtether.com/docs](https://labtether.com/docs)
- **Website** — [labtether.com](https://labtether.com)

## License

Copyright 2026 LabTether. All rights reserved. See [LICENSE](LICENSE).
