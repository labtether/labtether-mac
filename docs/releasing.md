# Releasing the macOS agent

macOS releases are signed by **Developer ID Application: Watari Labs Pty Ltd
(D2WZW3YTL6)** and notarized by Apple. The hand-started GitHub workflow
[`signed-release.yml`](../.github/workflows/signed-release.yml) does the work
and stops at a draft release. A maintainer inspects the draft and publishes it.
The release scripts refuse any other Apple team (`RELEASE_TEAM_ID` in
[`scripts/release-signing.sh`](../scripts/release-signing.sh)).

| Job | Secrets | What it does |
|---|---|---|
| `build` | none | Runs the Swift and Go tests, builds the unsigned universal app with its release record (`scripts/prepare-unsigned-release.sh`) |
| `sign` | the five below, through the `mac-release-signing` environment | Signs the app, has Apple notarize it, staples the ticket, builds the disk image, signs and notarizes that too, then checks all four files (`scripts/sign-release-ci.sh`) |
| `draft` | none, `contents: write` only | Re-checks the four files and the tags, then creates a draft with exactly those files (`scripts/publish-local-release.sh --confirm-draft`) |

The release files:

- `labtether-agent-macos-universal.dmg` and `.dmg.sha256`, the download people use
- `labtether-agent-macos-universal.tar.gz` and `.tar.gz.sha256`, the name the
  Hub's agent list and older links use

## One-time setup

The `mac-release-signing` environment admits the `main` branch only. It holds
five secrets. Set each from a file or a hidden prompt, so no value lands in
shell history or on screen:

| Secret | Value |
|---|---|
| `MAC_SIGNING_P12_BASE64` | The Developer ID Application identity, exported from Keychain Access as a `.p12` with a password, in base64 |
| `MAC_SIGNING_P12_PASSWORD` | That export password |
| `MAC_NOTARY_KEY` | An App Store Connect team API key (`.p8`) with the Developer role, used only for notarization |
| `MAC_NOTARY_KEY_ID` | That key's ID |
| `MAC_NOTARY_ISSUER_ID` | The issuer ID shown above the key list |

```bash
base64 -i /path/to/developer-id.p12 | gh secret set MAC_SIGNING_P12_BASE64 --env mac-release-signing --repo labtether/labtether-mac
```

```bash
gh secret set MAC_SIGNING_P12_PASSWORD --env mac-release-signing --repo labtether/labtether-mac
```

```bash
gh secret set MAC_NOTARY_KEY --env mac-release-signing --repo labtether/labtether-mac < /path/to/AuthKey_KEYID.p8
```

```bash
gh secret set MAC_NOTARY_KEY_ID --env mac-release-signing --repo labtether/labtether-mac
```

```bash
gh secret set MAC_NOTARY_ISSUER_ID --env mac-release-signing --repo labtether/labtether-mac
```

Delete the exported `.p12` after the upload. Keep the `.p8` in the local
signing folder; Apple offers it for download once.

The current identity chains to Apple's first Developer ID intermediate, which
expires on 1 February 2027, so the identity expires then too. Releases signed
before that date keep working. For later releases, create a new Developer ID
Application certificate in the Apple Developer account and replace the two
`MAC_SIGNING_P12_*` secrets. The signer already trusts the G2 intermediate the
new certificate chains to.

## Proof run

A proof run signs and notarizes the current `main` and keeps nothing: no
artifact, no release. Use it after changing the secrets or the release scripts.

```bash
gh workflow run signed-release.yml --repo labtether/labtether-mac --ref main -f mode=proof -f tag=v2.0.1 -f confirm=v2.0.1
```

`tag` only stamps the version in proof mode.

## Release run

1. Push the same tag to `labtether-mac` and `labtether-agent` (the
   prerequisites stage of `scripts/release-all.sh` in the workspace does this).
2. Start the workflow with the tag, typed twice:

   ```bash
   gh workflow run signed-release.yml --repo labtether/labtether-mac --ref main -f mode=release -f tag=vX.Y.Z -f confirm=vX.Y.Z
   ```

3. The draft job ends with exactly four files whose GitHub names, sizes and
   SHA-256 digests match the checked files. Replace the draft's placeholder
   notes with the CHANGELOG section, check the files, then publish it on
   GitHub.

The workflow refuses a run started from any branch but `main`, a tag that is
not `vX.Y.Z`, or a confirmation that does not repeat the tag.

## Local fallback

A Mac with the identity in its login Keychain and a notarytool profile can
make the same four files without GitHub:

```bash
xcrun notarytool store-credentials LabTetherRelease --validate
```

```bash
./scripts/release-local.sh --tag vX.Y.Z --build-number BUILD_NUMBER --agent-repo /absolute/path/to/labtether-agent --output-dir /absolute/path/to/empty-dir --confirm-notarize vX.Y.Z
```

Use the workflow's build number, 10000 × major + 100 × minor + patch (20001
for 2.0.1). It asks for the identity name and the profile name without echoing them,
runs the same tests and build as the `build` job, and signs with the same
steps as the `sign` job. It runs the full test suites, so use a lab Mac for
it. Publish its output with `scripts/publish-local-release.sh`, first with
`--confirm-draft vX.Y.Z`, then, in a new invocation after inspecting the
draft, `--confirm-publish vX.Y.Z`.

## Not proven yet

No release has been signed by the workflow yet. The first proof run is the
first real test of the keychain import, notarization with the API key,
stapling and Gatekeeper checks on a GitHub-hosted Mac.
