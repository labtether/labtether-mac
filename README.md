# LabTether Mac Agent

The macOS menu bar agent for [LabTether](https://github.com/labtether/labtether).

## Requirements

- Xcode with Swift 5.9+
- macOS 13+ deployment target

## Build

The Mac agent bundles the Go `labtether-agent` binary. The build downloads it from the main repo's GitHub Releases based on the version pinned in `AGENT_VERSION`.

### Swift only (development)

```bash
swift build
```

## Test

```bash
swift test
```
