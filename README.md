<div align="center">

<img src=".github/logo.svg" alt="LabTether" width="120" />

# LabTether for Mac

**A menu bar app that connects your Mac to your [LabTether](https://github.com/labtether/labtether) hub.**

[![macOS](https://img.shields.io/badge/macOS-13+-000000?style=flat-square&logo=apple&logoColor=white)](https://developer.apple.com/macos/)

</div>

Install it once and your Mac shows up in the hub next to your servers. You can
open a terminal or a remote desktop on it from any browser, and the menu bar
tells you whether it is connected.

## What you get

- **Live metrics.** CPU, memory, disk and network, plus temperature when macOS
  has a readable sensor.
- **Terminal and remote desktop** from the hub. No VNC client or SSH keys needed.
- **Status in the menu bar.** Connection state, alerts and quick actions.
- **launchd services.** See and manage them from the hub.
- **Native notifications** when the connection drops or a high or critical
  alert fires.
- **Update notice.** The menu shows when a newer signed release is out. The app
  checks once a day and never downloads anything itself. Turn it off in
  Settings > Advanced.

## Install

1. Download `labtether-agent-macos-universal.tar.gz` from
   [Releases](https://github.com/labtether/labtether-mac/releases/latest).
2. Open it and drag **LabTether Agent.app** to Applications.
3. Launch it. The menu bar icon walks you through connecting to your hub.

You need macOS 13 (Ventura) or newer, a running hub, and an enrollment token
from the hub (**Add Device**). The app is signed and notarized by Apple. To
check the download yourself first, see
[docs/verify-download.md](docs/verify-download.md).

## Uninstall

1. In the menu, choose **Reset & Uninstall...**. It stops the agent, removes
   the hub's SSH key line the agent added to `~/.ssh/authorized_keys`, deletes
   settings, credentials and history, and quits.
2. Delete **LabTether Agent.app** from Applications.
3. Remove the device in the hub.

The agent core in 1.7.0 cannot remove that SSH key line. With 1.7.0, delete
the hub's key from `~/.ssh/authorized_keys` by hand.

## Troubleshooting

- **No menu bar icon.** In System Settings > General > Login Items, allow
  LabTether Agent.
- **Can't connect.** Check that the hub URL opens from this Mac and that the
  enrollment token is still valid.
- **Changed the hub URL.** A token works only with the hub that issued it. The
  app removes the old hub's token on the next start and asks for an enrollment
  token from the new hub.
- **High CPU.** Open Console.app, filter for LabTether Agent and
  [open an issue](https://github.com/labtether/labtether-mac/issues) with what
  you see.

## How it works

The app wraps the same Go agent core used on Linux in a native Swift app. It
keeps one encrypted WebSocket connection open to your hub. The hub uses that
connection to read metrics, open terminal and desktop sessions, and run
actions.

## Build from source

You need stable Xcode 27 and a sibling checkout of
[labtether-agent](https://github.com/labtether/labtether-agent).

```bash
git clone https://github.com/labtether/labtether-agent ../labtether-agent
./scripts/build-app.sh --configuration release
```

The app lands in `build/LabTether Agent.app`. Toolchain and CI details are in
[docs/building.md](docs/building.md).

## Contributing

If you work with an AI coding agent, point it at [AGENTS.md](AGENTS.md) first.
Signing, notarization and publishing are in [docs/releasing.md](docs/releasing.md).
Changes are in [CHANGELOG.md](CHANGELOG.md).

## Help

- [Docs](https://labtether.com/docs) and [GitHub Discussions](https://github.com/labtether/labtether/discussions)
- Security issues: report privately as described in [SECURITY.md](SECURITY.md)
- Related: [LabTether hub](https://github.com/labtether/labtether),
  [Linux agent](https://github.com/labtether/labtether-agent),
  [Windows app](https://github.com/labtether/labtether-win)

## License

Source available, all rights reserved. Copyright 2026 LabTether. You may view
and study this code, but you may not copy, modify, distribute or use it without
written permission. See [LICENSE](LICENSE).
