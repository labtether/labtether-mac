# Check a download before you install it

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

| Command | What it checks |
|---|---|
| `shasum` | The archive matches the published checksum |
| `stapler` | Apple's notarization ticket is attached |
| `codesign` | The app and everything inside it is signed and unchanged |
| `spctl` | Gatekeeper will let the app run |

If every command passes, drag **LabTether Agent.app** to Applications.
