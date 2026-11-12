# Releasing the macOS agent

LabTether macOS releases are signed and notarized only on an authorized local
Mac. GitHub Actions verifies tagged source and builds an unsigned universal app,
but it does not receive signing certificates, private keys, notary credentials,
signed archives, or permission to publish a release.

The release is intentionally split into three independently confirmed commands:

1. `release-local.sh` tests two clean, identically tagged checkouts, builds,
   signs, notarizes, staples, packages, re-extracts, and verifies the app. It
   then puts the stapled app in a disk image, and signs, notarizes, staples
   and verifies that image too.
2. `publish-local-release.sh --confirm-draft` re-verifies the exact local bytes
   and remote tags, creates a draft containing exactly the archive, the disk
   image and their checksums, verifies their GitHub names, sizes, uploaded
   states, and SHA-256 digests, then exits while the release is still a draft.
3. After independent inspection, a separate
   `publish-local-release.sh --confirm-publish` invocation repeats every local
   check, freshly verifies the existing GitHub draft, and only then publishes.

Neither script imports certificate files. The signing identity and the
notarytool credential profile must already exist in the local Keychain. All
intermediate files live in a mode-0700 temporary directory outside both source
repositories and are deleted on every exit. The only retained files are the
final archive, the disk image and their checksums in an explicitly selected
external output directory.

## One-time local setup

Import the Developer ID Application identity into the authorized Mac's login
Keychain using Apple's local tools. Do not copy credentials into either source
repository or any build directory.

Store and validate the notarization credential through notarytool's interactive
Keychain prompt:

```bash
xcrun notarytool store-credentials LabTetherRelease --validate
```

Do not put the identity selector, profile selector, passwords, private keys, or
credential files in shell scripts, environment files, CI variables, logs, or
release notes.

## Prepare verified release bytes

Merge the intended changes first. Create the same semantic version tag in both
the `labtether-mac` and `labtether-agent` repositories. Both checkouts must be
clean and their `HEAD` commits must exactly equal that local tag.

Create an empty output directory outside both repositories:

```bash
release_output="$(mktemp -d "${TMPDIR:-/tmp}/labtether-release-output.XXXXXX")"
chmod 700 "${release_output}"
```

An offline dry run checks the tag, source, and output boundaries without
reading the Keychain, building, accessing the network, or changing anything:

```bash
./scripts/release-local.sh \
  --tag vX.Y.Z \
  --build-number BUILD_NUMBER \
  --agent-repo /absolute/path/to/labtether-agent \
  --output-dir "${release_output}" \
  --dry-run
```

For the real preparation, pass the exact tag a second time as the explicit
notarization confirmation. The script always reads both selectors silently
from the controlling terminal; it deliberately has no selector command-line
options that could leak through shell history or the process list. It disables
shell tracing before handling inputs and clears both selectors on exit:

```bash
./scripts/release-local.sh \
  --tag vX.Y.Z \
  --build-number BUILD_NUMBER \
  --agent-repo /absolute/path/to/labtether-agent \
  --output-dir "${release_output}" \
  --confirm-notarize vX.Y.Z
```

Success leaves exactly these four files in the external directory:

- `labtether-agent-macos-universal.tar.gz`
- `labtether-agent-macos-universal.tar.gz.sha256`
- `labtether-agent-macos-universal.dmg`
- `labtether-agent-macos-universal.dmg.sha256`

The disk image is what people download: it holds the app and a shortcut to
Applications. The archive keeps its name because the Hub's agent list and
older links use it.

The app contains signed provenance for the exact wrapper tag/commit and bundled
agent commit. Preparation fails unless the archive checksum, two architectures,
Developer ID signature, hardened runtime, secure timestamp, stapled ticket, and
Gatekeeper assessment all pass again after extracting the final archive. The
disk image must then hold that same app byte for byte and carry its own
Developer ID signature, stapled ticket and Gatekeeper result.

The disk image steps that need the Developer ID identity and Apple's notary
service (sign, submit, staple, Gatekeeper) have not run yet: no release has
been signed since the disk image was added. Building the image and checking
its contents run in CI and were run on a Mac without signing.

## Publish the exact verified bytes

Push both matching tags, allow the read-only source verification workflow to
pass, and review the four local files. Draft creation requires its own exact-tag
confirmation:

```bash
./scripts/publish-local-release.sh \
  --tag vX.Y.Z \
  --agent-repo /absolute/path/to/labtether-agent \
  --release-dir "${release_output}" \
  --confirm-draft vX.Y.Z
```

The command exits after proving the release is still a draft and that all four
GitHub assets exactly match the verified local names, sizes, uploaded states,
and SHA-256 digests. Inspect the draft independently. Then use a new invocation:

```bash
./scripts/publish-local-release.sh \
  --tag vX.Y.Z \
  --agent-repo /absolute/path/to/labtether-agent \
  --release-dir "${release_output}" \
  --confirm-publish vX.Y.Z
```

The publisher refuses a dirty checkout, missing or mismatched remote tag, any
extra release-directory entry, any symlink, a malformed checksum, failed
signing/notarization/Gatekeeper validation, or anything other than the four
expected uploaded assets. Draft creation refuses an existing release;
publication requires an existing exact draft. The two confirmations are
mutually exclusive, so one invocation cannot both create and publish a release.
If draft creation or inspection stops partway through, an unpublished draft may
remain for manual inspection; the script never publishes an unverified draft.

## Disk image without signing

`scripts/build-dmg.sh` builds the disk image from an app and signs nothing.
`scripts/verify-release-dmg.sh` checks an image against that app: checksum,
image integrity, exactly the app and the Applications shortcut inside, and
the app's files byte for byte. `--require-notarized` adds the signature,
ticket and Gatekeeper checks; a release that ships unsigned leaves it out.

## Release boundary

The tag-triggered GitHub workflow is only a reproducible source gate. It must
remain read-only and must never sign, notarize, attest, upload artifacts, or
create a GitHub release. `scripts/test-release-policy.sh` enforces this boundary
in normal CI and tag verification.
