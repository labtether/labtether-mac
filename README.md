<div align="center">

<img src=".github/logo.svg" alt="LabTether" width="120" />

</div>

# LabTether macOS Agent

A native menu bar app that connects your Mac to your [LabTether](https://labtether.com) hub -- telemetry, remote access, and actions without leaving the menu bar.

[![Swift](https://img.shields.io/badge/Swift-5.9+-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-13+-000000?style=flat-square&logo=apple&logoColor=white)](https://developer.apple.com/macos/)

<!-- TODO: Add screenshot of menu bar agent -->

---

## Install

Download `labtether-agent-macos-universal.tar.gz` and its `.sha256` file from
[Releases](https://github.com/labtether/labtether-mac/releases/latest), then
verify and extract the signed application before dragging it to Applications:

```bash
shasum -a 256 -c labtether-agent-macos-universal.tar.gz.sha256
tar xzf labtether-agent-macos-universal.tar.gz
xcrun stapler validate "LabTether Agent.app"
codesign --verify --deep --strict --verbose=2 "LabTether Agent.app"
spctl --assess --type execute --verbose=4 "LabTether Agent.app"
```

Launch **LabTether Agent.app**. The menu bar icon walks you through hub enrollment.

For detailed setup, see the [macOS agent setup guide](https://labtether.com/docs/install-upgrade/agent-install-commands-by-os).

---

## What It Does

- **System telemetry** -- CPU, memory, disk, and network reported to your hub every heartbeat, with temperature included when macOS exposes a usable sensor source.
- **Remote access** -- Terminal and desktop sessions from the LabTether console. No VNC clients or SSH keys needed.
- **Menu bar status** -- Connection state, alerts, and quick actions at a glance.
- **Service management** -- Monitor and manage launchd services from the dashboard.
- **Notifications** -- Native macOS alerts for agent connection state and high/critical hub alert transitions.

---

## Requirements

- macOS 13 (Ventura) or later
- A running [LabTether hub](https://github.com/labtether/labtether) to connect to
- An enrollment token generated from the hub console

---

## Build From Source

Requires Xcode with Swift 5.9+ and macOS 13+ deployment target.
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

Maintainers should follow the [local-only signing, notarization, and publication
runbook](docs/releasing.md). Hosted CI verifies source tags but never receives
signing or notarization credentials and never publishes release bytes.

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
