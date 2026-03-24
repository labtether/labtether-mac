# LabTether macOS Agent

A native menu bar app that connects your Mac to your [LabTether](https://labtether.com) hub -- telemetry, remote access, and actions without leaving the menu bar.

[![Swift](https://img.shields.io/badge/Swift-5.9+-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-13+-000000?style=flat-square&logo=apple&logoColor=white)](https://developer.apple.com/macos/)

<!-- TODO: Add screenshot of menu bar agent -->

---

## Install

Download **LabTether Agent.app** from [Releases](https://github.com/labtether/labtether-mac/releases/latest), drag it to Applications, and launch. The menu bar icon walks you through hub enrollment.

For detailed setup, see the [macOS agent setup guide](https://labtether.com/docs/install-upgrade/agent-install-commands-by-os).

---

## What It Does

- **System telemetry** -- CPU, memory, disk, network, and temperature reported to your hub every heartbeat.
- **Remote access** -- Terminal and desktop sessions from the LabTether console. No VNC clients or SSH keys needed.
- **Menu bar status** -- Connection state, alerts, and quick actions at a glance.
- **Service management** -- Monitor and manage launchd services from the dashboard.
- **Notifications** -- Native macOS alerts for hub events and incident updates.

---

## Requirements

- macOS 13 (Ventura) or later
- A running [LabTether hub](https://github.com/labtether/labtether) to connect to
- An enrollment token generated from the hub console

---

## Build From Source

Requires Xcode with Swift 5.9+ and macOS 13+ deployment target.

```bash
swift build
```

The Mac agent bundles the Go `labtether-agent` binary. See `AGENT_VERSION` for the pinned release.

For most users, download the pre-built app from [Releases](https://github.com/labtether/labtether-mac/releases/latest) instead.

---

## How It Works

The macOS agent runs as a lightweight menu bar app. On launch, it establishes a persistent WebSocket connection to your hub and begins reporting system telemetry. The hub can then issue commands back -- opening terminal sessions, querying service status, or triggering actions -- all through the encrypted channel.

The app bundles the same Go agent core used by the Linux agent, wrapped in a native Swift UI for macOS integration.

---

## Uninstall

1. Quit LabTether Agent from the menu bar.
2. Delete **LabTether Agent.app** from Applications.
3. Remove the agent from your hub's asset list via the console.

---

## Troubleshooting

- **Menu bar icon not appearing** -- Check System Settings > Login Items to confirm LabTether Agent is allowed.
- **Connection issues** -- Verify the hub URL is reachable and that your enrollment token is valid.
- **High CPU usage** -- Check Console.app for agent logs and report an issue if the problem persists.

---

## Links

- **LabTether Hub** -- [github.com/labtether/labtether](https://github.com/labtether/labtether)
- **Linux Agent** -- [github.com/labtether/labtether-agent](https://github.com/labtether/labtether-agent)
- **Windows Agent** -- [github.com/labtether/labtether-win](https://github.com/labtether/labtether-win)
- **Documentation** -- [labtether.com/docs](https://labtether.com/docs)
- **Website** -- [labtether.com](https://labtether.com)

## License

Copyright 2026 LabTether. All rights reserved. See [LICENSE](LICENSE).
