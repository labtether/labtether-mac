#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
WORKFLOW="${REPO_ROOT}/.github/workflows/release.yml"
LOCAL_PREPARE="${SCRIPT_DIR}/release-local.sh"
LOCAL_PUBLISH="${SCRIPT_DIR}/publish-local-release.sh"
LOCAL_VERIFY="${SCRIPT_DIR}/verify-release-archive.sh"
LOCAL_READBACK="${SCRIPT_DIR}/release-readback-common.sh"

fail() {
  printf 'release policy check failed: %s\n' "$1" >&2
  exit 1
}

for script_path in "${LOCAL_PREPARE}" "${LOCAL_PUBLISH}" "${LOCAL_VERIFY}" "${LOCAL_READBACK}" "${BASH_SOURCE[0]}"; do
  bash -n "${script_path}" || fail "a release script has invalid shell syntax"
done

grep -Eq '^[[:space:]]+contents:[[:space:]]+read[[:space:]]*$' "${WORKFLOW}" \
  || fail "tag verification workflow must have read-only contents permission"
[[ "$(grep -Ec '^[[:space:]]+fetch-depth:[[:space:]]+0[[:space:]]*$' "${WORKFLOW}")" == "2" ]] \
  || fail "both release source checkouts must fetch tags explicitly"
# These are literal workflow commands, not shell expansions in this policy test.
# shellcheck disable=SC2016
for required_tag_check in \
  'test "$(git rev-parse HEAD)" = ' \
  'git rev-list -n 1 "refs/tags/${GITHUB_REF_NAME}"' \
  'test "$(git -C agent-core rev-parse HEAD)" = ' \
  'git -C agent-core rev-list -n 1 "refs/tags/${GITHUB_REF_NAME}"'; do
  grep -Fq "${required_tag_check}" "${WORKFLOW}" \
    || fail "tag verification must compare each checkout to the triggering tag commit"
done
if grep -Fq 'git describe --tags --exact-match' "${WORKFLOW}"; then
  fail "tag verification must not use ambiguous describe output when tags share a commit"
fi
# The fixed policy text intentionally contains a literal command substitution.
# shellcheck disable=SC2016
grep -Fq 'test "$(git status --porcelain=v1 --untracked-files=all)" = "?? agent-core/"' "${WORKFLOW}" \
  || fail "tag verification must reject every unexpected wrapper checkout change"
if grep -Eiq 'secrets\.|contents:[[:space:]]*write|id-token:|attestations:|artifact-metadata:|actions/upload-artifact|action-gh-release|actions/attest|notarytool|stapler|gh[[:space:]]+release|base64|security[[:space:]]+import|codesign' "${WORKFLOW}"; then
  fail "tag verification workflow contains signing, publishing, upload, or secret-bearing behavior"
fi

if grep -Eiq 'secrets\.|base64|security[[:space:]]+(import|create-keychain|delete-keychain)' \
  "${LOCAL_PREPARE}" "${LOCAL_PUBLISH}" "${LOCAL_VERIFY}"; then
  fail "local release scripts contain forbidden certificate ingestion or hosted-secret behavior"
fi

for required_prepare_text in \
  'go test ./...' \
  'go test -race ./...' \
  'go vet ./...' \
  'swift test --scratch-path' \
  'release-provenance.json' \
  'notarytool submit' \
  'stapler staple' \
  'spctl --assess' \
  'verify-release-archive.sh' \
  'repo_has_forbidden_release_input' \
  'mv -n --'; do
  grep -Fq "${required_prepare_text}" "${LOCAL_PREPARE}" \
    || fail "local preparation is missing a required release gate"
done

if grep -Eq -- '--signing-identity|--notary-profile' "${LOCAL_PREPARE}"; then
  fail "real-run signing and notary selectors must be read silently instead of passed in process arguments"
fi

for required_publish_text in \
  'verify-release-archive.sh' \
  '--confirm-draft' \
  '--confirm-publish' \
  'draft creation and publication require separate invocations' \
  'validate_github_release_asset_readback' \
  'gh release create' \
  '--draft' \
  '--verify-tag' \
  'gh release edit'; do
  grep -Fq -- "${required_publish_text}" "${LOCAL_PUBLISH}" \
    || fail "local publication is missing a required two-phase safety gate"
done
# These are literal jq expressions in the shared readback helper, not shell variables.
# shellcheck disable=SC2016
for required_readback_text in \
  '.state == "uploaded"' \
  '.digest == $archive_digest' \
  '.digest == $checksum_digest'; do
  grep -Fq -- "${required_readback_text}" "${LOCAL_READBACK}" \
    || fail "GitHub readback helper is missing a required asset check"
done
grep -Fq 'repo_has_forbidden_release_input' "${LOCAL_PUBLISH}" \
  || fail "local publication must reject tracked symlinks and certificate/key files"
grep -Fq "source \"\${SCRIPT_DIR}/release-readback-common.sh\"" "${LOCAL_PUBLISH}" \
  || fail "local publication must use the tested GitHub readback helper"
draft_create_line="$(grep -n 'gh release create ' "${LOCAL_PUBLISH}" | cut -d: -f1)"
draft_exit_line="$(grep -n '^  exit 0$' "${LOCAL_PUBLISH}" | tail -n 1 | cut -d: -f1)"
publish_line="$(grep -n 'gh release edit ' "${LOCAL_PUBLISH}" | cut -d: -f1)"
[[ -n "${draft_create_line}" && -n "${draft_exit_line}" && -n "${publish_line}" ]] \
  || fail "local publication is missing a draft/publication boundary"
(( draft_create_line < draft_exit_line && draft_exit_line < publish_line )) \
  || fail "local publication can reach publication without exiting after draft creation"

TAG="v1.2.3"
ARCHIVE_NAME="labtether-agent-macos-universal.tar.gz"
CHECKSUM_NAME="${ARCHIVE_NAME}.sha256"
# shellcheck source=scripts/release-readback-common.sh
source "${LOCAL_READBACK}"
archive_hash="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
checksum_hash="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
release_json="$(jq -n \
  --arg tag "${TAG}" --arg archive "${ARCHIVE_NAME}" --arg checksum "${CHECKSUM_NAME}" \
  --arg archive_digest "sha256:${archive_hash}" --arg checksum_digest "sha256:${checksum_hash}" \
  '{draft: true, tag_name: $tag, assets: [
    {name: $archive, state: "uploaded", size: 1000, digest: $archive_digest},
    {name: $checksum, state: "uploaded", size: 94, digest: $checksum_digest}
  ]}')"
validate_github_release_asset_readback "${release_json}" true "${archive_hash}" "${checksum_hash}" 1000 94 \
  || fail "GitHub readback fixture rejected the valid draft"
published_json="$(jq '.draft = false' <<<"${release_json}")"
validate_github_release_asset_readback "${published_json}" false "${archive_hash}" "${checksum_hash}" 1000 94 \
  || fail "GitHub readback fixture rejected the valid published release"
if validate_github_release_asset_readback "$(jq '.assets[0].digest = null' <<<"${release_json}")" true "${archive_hash}" "${checksum_hash}" 1000 94; then
  fail "GitHub readback fixture accepted a missing archive digest"
fi
if validate_github_release_asset_readback "$(jq '.assets[1].state = "new"' <<<"${release_json}")" true "${archive_hash}" "${checksum_hash}" 1000 94; then
  fail "GitHub readback fixture accepted a non-uploaded checksum asset"
fi
if validate_github_release_asset_readback "$(jq '.assets += [{name: "extra", state: "uploaded", size: 1, digest: "sha256:cccc"}]' <<<"${release_json}")" true "${archive_hash}" "${checksum_hash}" 1000 94; then
  fail "GitHub readback fixture accepted an unexpected extra asset"
fi

printf 'Release isolation policy passed.\n'
