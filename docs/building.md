# Build from source

Use stable Xcode 27 for local builds. The macOS 13 deployment target and
Swift 5 language mode remain supported. Hosted CI uses the current stable
`macos-26` image (Xcode 26.6 / Swift 6.3.3) until Xcode 27 is available on
a stable runner image; no preview or larger paid runner is required.
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
runbook](releasing.md). Hosted CI verifies source tags but never receives
signing or notarization credentials and never publishes release bytes.

For most users, download the pre-built app from [Releases](https://github.com/labtether/labtether-mac/releases/latest) instead.
