# Check a download before you install it

## Checksum

Download `labtether-agent-macos-universal.dmg` and its `.sha256` file from
[Releases](https://github.com/labtether/labtether-mac/releases/latest). In
Terminal, in the download folder:

```bash
shasum -a 256 -c labtether-agent-macos-universal.dmg.sha256
```

The archive `labtether-agent-macos-universal.tar.gz` has its own `.sha256`
file and is checked the same way. A release without a disk image, such as
2.0.0, has only the archive.

## Signature and notarization

The release notes say whether a release is signed and notarized by Apple.
Release 2.0.0 is not, so it has nothing more to check.

For a signed release, check the disk image, then the app inside it:

```bash
xcrun stapler validate labtether-agent-macos-universal.dmg
spctl --assess --type open --context context:primary-signature --verbose=4 labtether-agent-macos-universal.dmg
hdiutil attach -readonly -nobrowse labtether-agent-macos-universal.dmg
codesign --verify --deep --strict --verbose=2 "/Volumes/LabTether Agent/LabTether Agent.app"
codesign -dv --verbose=2 "/Volumes/LabTether Agent/LabTether Agent.app" 2>&1 | grep -E '^(Authority=Developer ID Application|TeamIdentifier)'
spctl --assess --type execute --verbose=4 "/Volumes/LabTether Agent/LabTether Agent.app"
hdiutil detach "/Volumes/LabTether Agent"
```

| Command | What it checks |
|---|---|
| `stapler` | Apple's notarization ticket is attached to the disk image |
| `spctl`, first | Gatekeeper accepts the disk image |
| `codesign --verify` | The app and everything inside it is signed and unchanged |
| `codesign -dv` | The signer is `Developer ID Application: Watari Labs Pty Ltd (D2WZW3YTL6)` and `TeamIdentifier=D2WZW3YTL6` |
| `spctl`, second | Gatekeeper will let the app run |

If every command passes, open the disk image and drag **LabTether Agent** to
**Applications**.
