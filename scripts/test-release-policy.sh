#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
WORKFLOW="${REPO_ROOT}/.github/workflows/release.yml"
LOCAL_PREPARE="${SCRIPT_DIR}/release-local.sh"
LOCAL_PUBLISH="${SCRIPT_DIR}/publish-local-release.sh"
LOCAL_VERIFY="${SCRIPT_DIR}/verify-release-archive.sh"

fail() {
  printf 'release policy check failed: %s\n' "$1" >&2
  exit 1
}

for script_path in "${LOCAL_PREPARE}" "${LOCAL_PUBLISH}" "${LOCAL_VERIFY}" "${BASH_SOURCE[0]}"; do
  bash -n "${script_path}" || fail "a release script has invalid shell syntax"
done

grep -Eq '^[[:space:]]+contents:[[:space:]]+read[[:space:]]*$' "${WORKFLOW}" \
  || fail "tag verification workflow must have read-only contents permission"
[[ "$(grep -Ec '^[[:space:]]+fetch-depth:[[:space:]]+0[[:space:]]*$' "${WORKFLOW}")" == "2" ]] \
  || fail "both release source checkouts must fetch tags explicitly"
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
  'gh release create' \
  '--draft' \
  '--verify-tag' \
  'gh release edit' \
  'draft_asset_count' \
  'published_asset_count'; do
  grep -Fq -- "${required_publish_text}" "${LOCAL_PUBLISH}" \
    || fail "local publication is missing a required two-phase safety gate"
done
grep -Fq 'repo_has_forbidden_release_input' "${LOCAL_PUBLISH}" \
  || fail "local publication must reject tracked symlinks and certificate/key files"

printf 'Release isolation policy passed.\n'
