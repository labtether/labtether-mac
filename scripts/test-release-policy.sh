#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
WORKFLOW="${REPO_ROOT}/.github/workflows/release.yml"
LOCAL_PREPARE="${SCRIPT_DIR}/release-local.sh"
LOCAL_PUBLISH="${SCRIPT_DIR}/publish-local-release.sh"
LOCAL_VERIFY="${SCRIPT_DIR}/verify-release-archive.sh"
LOCAL_READBACK="${SCRIPT_DIR}/release-readback-common.sh"
LOCAL_PROVENANCE="${SCRIPT_DIR}/release-provenance.sh"
LOCAL_BUILD_DMG="${SCRIPT_DIR}/build-dmg.sh"
LOCAL_VERIFY_DMG="${SCRIPT_DIR}/verify-release-dmg.sh"
PREPARE_UNSIGNED="${SCRIPT_DIR}/prepare-unsigned-release.sh"
SIGNING_COMMON="${SCRIPT_DIR}/release-signing.sh"
CI_SIGN="${SCRIPT_DIR}/sign-release-ci.sh"
SIGNED_WORKFLOW="${REPO_ROOT}/.github/workflows/signed-release.yml"

fail() {
  printf 'release policy check failed: %s\n' "$1" >&2
  exit 1
}

for script_path in "${LOCAL_PREPARE}" "${LOCAL_PUBLISH}" "${LOCAL_VERIFY}" "${LOCAL_READBACK}" "${LOCAL_PROVENANCE}" "${LOCAL_BUILD_DMG}" "${LOCAL_VERIFY_DMG}" "${PREPARE_UNSIGNED}" "${SIGNING_COMMON}" "${CI_SIGN}" "${BASH_SOURCE[0]}"; do
  bash -n "${script_path}" || fail "a release script has invalid shell syntax"
done

# A traced invocation must stop tracing before handling private signing inputs.
# Use a synthetic argument and --help so no credential, build or signing runs.
trace_fixture="synthetic-private-selector-for-trace-check"
for traced_script in "${LOCAL_PREPARE}" "${CI_SIGN}"; do
  trace_output="$(bash -x "${traced_script}" --tag "${trace_fixture}" --help 2>&1)" \
    || fail "traced help invocation failed"
  if [[ "${trace_output}" == *"${trace_fixture}"* ]]; then
    fail "a signing script leaks arguments through shell tracing"
  fi
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
  "${LOCAL_PREPARE}" "${LOCAL_PUBLISH}" "${LOCAL_VERIFY}" "${LOCAL_BUILD_DMG}" "${LOCAL_VERIFY_DMG}" \
  "${PREPARE_UNSIGNED}" "${SIGNING_COMMON}"; then
  fail "local release scripts contain forbidden certificate ingestion or hosted-secret behavior"
fi

for required_unsigned_text in 'go test ./...' 'go test -race ./...' 'go vet ./...' \
  'swift test --scratch-path' 'write_release_provenance' 'repo_has_forbidden_release_input' \
  '--no-sign'; do
  grep -Fq -- "${required_unsigned_text}" "${PREPARE_UNSIGNED}" \
    || fail "unsigned preparation is missing a required release gate"
done
for required_signing_text in 'notarytool submit' 'stapler staple' 'stapler validate' 'spctl --assess' \
  'build-dmg.sh' '--options runtime' 'mv -n --'; do
  grep -Fq -- "${required_signing_text}" "${SIGNING_COMMON}" \
    || fail "shared signing steps are missing a required release gate"
done
for signer_script in "${LOCAL_PREPARE}" "${CI_SIGN}"; do
  for required_signer_text in 'sign_and_package_release' 'verify-release-archive.sh' '--dmg-checksum' \
    'check_app_release_record' 'place_release_assets' 'RELEASE_TEAM_ID'; do
    grep -Fq -- "${required_signer_text}" "${signer_script}" \
      || fail "a signing script is missing a required release gate"
  done
done
grep -Fq 'prepare-unsigned-release.sh' "${LOCAL_PREPARE}" \
  || fail "local preparation must use the shared unsigned build"
grep -Fq 'repo_has_forbidden_release_input' "${LOCAL_PREPARE}" \
  || fail "local preparation must reject tracked symlinks and certificate/key files"

# Releases are signed by one Apple team only: Watari Labs Pty Ltd.
grep -Eq '^RELEASE_TEAM_ID="D2WZW3YTL6"$' "${SIGNING_COMMON}" \
  || fail "the release team must be pinned to D2WZW3YTL6"
# shellcheck disable=SC2016
grep -Fq '[[ "${APP_TEAM_ID}" == "${RELEASE_TEAM_ID}" ]]' "${LOCAL_VERIFY}" \
  || fail "release verification must require the pinned team"

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
  '.size == $want.size' \
  '.digest == $want.digest'; do
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

# The archive check must hand the same verified app to the disk image check.
grep -Fq 'verify-release-dmg.sh' "${LOCAL_VERIFY}" \
  || fail "release verification must check the disk image against the verified app"
grep -Fq -- '--require-notarized' "${LOCAL_VERIFY}" \
  || fail "release verification must require a notarized disk image"

# The hosted signer: started by hand from main, secrets only in the sign job
# through the protected environment, write access only in the draft job.
if ! grep -Eq '^on:$' "${SIGNED_WORKFLOW}" || ! grep -Eq '^  workflow_dispatch:$' "${SIGNED_WORKFLOW}"; then
  fail "the signed workflow must start by hand"
fi
if grep -Eq '^  (push|pull_request|pull_request_target|schedule|workflow_run|repository_dispatch):' "${SIGNED_WORKFLOW}"; then
  fail "the signed workflow must not start on any event but workflow_dispatch"
fi
# shellcheck disable=SC2016 # a literal workflow line
grep -Fq '[[ "$GITHUB_REF" == "refs/heads/main" ]]' "${SIGNED_WORKFLOW}" \
  || fail "the signed workflow must refuse refs other than main"
sign_job_line="$(grep -n '^  sign:$' "${SIGNED_WORKFLOW}" | cut -d: -f1)"
draft_job_line="$(grep -n '^  draft:$' "${SIGNED_WORKFLOW}" | cut -d: -f1)"
[[ -n "${sign_job_line}" && -n "${draft_job_line}" ]] || fail "the signed workflow must have sign and draft jobs"
while IFS=: read -r line_number line_text; do
  (( line_number > sign_job_line && line_number < draft_job_line )) \
    || fail "a secret is used outside the sign job"
  [[ "${line_text}" =~ secrets\.MAC_(SIGNING_P12_BASE64|SIGNING_P12_PASSWORD|NOTARY_KEY|NOTARY_KEY_ID|NOTARY_ISSUER_ID)\ \}\}$ ]] \
    || fail "the sign job reads an unexpected secret"
done < <(grep -n 'secrets\.' "${SIGNED_WORKFLOW}")
[[ "$(grep -c '^    environment: mac-release-signing$' "${SIGNED_WORKFLOW}")" == "1" ]] \
  || fail "only the sign job may use the signing environment"
environment_line="$(grep -n '^    environment: mac-release-signing$' "${SIGNED_WORKFLOW}" | cut -d: -f1)"
(( environment_line > sign_job_line && environment_line < draft_job_line )) \
  || fail "the signing environment belongs to the sign job"
write_lines="$(grep -n 'contents: write' "${SIGNED_WORKFLOW}" | cut -d: -f1)"
if [[ "$(grep -c . <<<"${write_lines}")" != "1" ]] || (( write_lines < draft_job_line )); then
  fail "only the draft job may write to the repository"
fi
if grep -Eq 'id-token:|gh[[:space:]]+release[[:space:]]+edit|--confirm-publish|action-gh-release' "${SIGNED_WORKFLOW}"; then
  fail "the signed workflow must stop at a draft"
fi
grep -Fq 'scripts/sign-release-ci.sh' "${SIGNED_WORKFLOW}" || fail "the sign job must use sign-release-ci.sh"
grep -Fq -- '--confirm-draft' "${SIGNED_WORKFLOW}" || fail "the draft job must use the draft confirmation"
if grep -Eq 'secrets\.' "${CI_SIGN}"; then
  fail "the hosted signer must get secrets from its environment only"
fi
for required_ci_text in 'delete-keychain' 'GITHUB_ACTIONS' 'DeveloperIDCA.cer' 'DeveloperIDG2CA.cer'; do
  grep -Fq -- "${required_ci_text}" "${CI_SIGN}" || fail "the hosted signer is missing a required safety step"
done

TAG="v1.2.3"
ARCHIVE_NAME="labtether-agent-macos-universal.tar.gz"
CHECKSUM_NAME="${ARCHIVE_NAME}.sha256"
DMG_NAME="labtether-agent-macos-universal.dmg"
DMG_CHECKSUM_NAME="${DMG_NAME}.sha256"
# shellcheck source=scripts/release-readback-common.sh
source "${LOCAL_READBACK}"
asset_dir="$(mktemp -d "${TMPDIR:-/tmp}/labtether-readback-check.XXXXXX")"
printf 'archive\n' >"${asset_dir}/${ARCHIVE_NAME}"
printf 'archive checksum\n' >"${asset_dir}/${CHECKSUM_NAME}"
printf 'disk image\n' >"${asset_dir}/${DMG_NAME}"
printf 'disk image checksum\n' >"${asset_dir}/${DMG_CHECKSUM_NAME}"
expected_assets="$(release_asset_expectations \
  "${asset_dir}/${ARCHIVE_NAME}" "${asset_dir}/${CHECKSUM_NAME}" \
  "${asset_dir}/${DMG_NAME}" "${asset_dir}/${DMG_CHECKSUM_NAME}")" \
  || fail "local release assets could not be measured"
rm -rf "${asset_dir}"
[[ "$(jq -r 'length' <<<"${expected_assets}")" == "4" ]] || fail "expected four measured release assets"
release_json="$(jq -n --arg tag "${TAG}" --argjson expected "${expected_assets}" \
  '{draft: true, tag_name: $tag, assets: [$expected[] | . + {state: "uploaded"}]}')"
validate_github_release_asset_readback "${release_json}" true "${expected_assets}" \
  || fail "GitHub readback fixture rejected the valid draft"
published_json="$(jq '.draft = false' <<<"${release_json}")"
validate_github_release_asset_readback "${published_json}" false "${expected_assets}" \
  || fail "GitHub readback fixture rejected the valid published release"
if validate_github_release_asset_readback "$(jq '.assets[0].digest = null' <<<"${release_json}")" true "${expected_assets}"; then
  fail "GitHub readback fixture accepted a missing archive digest"
fi
if validate_github_release_asset_readback "$(jq '.assets[1].state = "new"' <<<"${release_json}")" true "${expected_assets}"; then
  fail "GitHub readback fixture accepted a non-uploaded checksum asset"
fi
if validate_github_release_asset_readback "$(jq '.assets[2].size += 1' <<<"${release_json}")" true "${expected_assets}"; then
  fail "GitHub readback fixture accepted a disk image of another size"
fi
if validate_github_release_asset_readback "$(jq '.assets += [{name: "extra", state: "uploaded", size: 1, digest: "sha256:cccc"}]' <<<"${release_json}")" true "${expected_assets}"; then
  fail "GitHub readback fixture accepted an unexpected extra asset"
fi
if validate_github_release_asset_readback "$(jq --arg dmg "${DMG_NAME}" '.assets |= map(select(.name != $dmg))' <<<"${release_json}")" true "${expected_assets}"; then
  fail "GitHub readback fixture accepted a release without the disk image"
fi
if validate_github_release_asset_readback "${release_json}" true '[]'; then
  fail "GitHub readback fixture accepted an empty expectation"
fi

# GitHub's releases/tags endpoint omits drafts, so publication must look the
# release up from the full paginated list and accept exactly one match.
if grep -Fq 'releases/tags/' "${LOCAL_PUBLISH}"; then
  fail "local publication must not read releases through the published-only tags endpoint"
fi
gh() {
  [[ "$*" == "api --paginate --slurp repos/labtether/labtether-mac/releases?per_page=100" ]] || return 97
  printf '%s\n' "${GH_RELEASE_PAGES}"
}
other_json="$(jq '.tag_name = "v1.2.2" | .draft = false' <<<"${release_json}")"
GH_RELEASE_PAGES="$(jq -cn --argjson other "${other_json}" --argjson draft "${release_json}" '[[$other], [$other, $draft]]')"
found_json="$(github_release_by_tag labtether/labtether-mac "${TAG}")" \
  || fail "release lookup missed a draft on a later page"
validate_github_release_asset_readback "${found_json}" true "${expected_assets}" \
  || fail "release lookup did not return the draft release object"
GH_RELEASE_PAGES="$(jq -cn --argjson other "${other_json}" '[[$other], []]')"
if github_release_by_tag labtether/labtether-mac "${TAG}" >/dev/null 2>&1; then
  fail "release lookup accepted a tag without a release"
fi
GH_RELEASE_PAGES="$(jq -cn --argjson draft "${release_json}" --argjson published "${published_json}" '[[$draft], [$published]]')"
if github_release_by_tag labtether/labtether-mac "${TAG}" >/dev/null 2>&1; then
  fail "release lookup accepted more than one release for a tag"
fi
GH_RELEASE_PAGES='{"message":"Not Found"}'
if github_release_by_tag labtether/labtether-mac "${TAG}" >/dev/null 2>&1; then
  fail "release lookup accepted an unexpected GitHub response"
fi
unset -f gh

# The v1.7.1 signed path stopped here on macOS 27.2: plutil could not insert
# keys into a JSON file. Write provenance on this host and read it back the
# way verify-release-archive.sh does.
# shellcheck source=scripts/release-provenance.sh
source "${LOCAL_PROVENANCE}"
provenance_dir="$(mktemp -d "${TMPDIR:-/tmp}/labtether-provenance-check.XXXXXX")"
provenance_wrapper="1111111111111111111111111111111111111111"
provenance_agent="2222222222222222222222222222222222222222"
write_release_provenance "${provenance_dir}/release-provenance.json" "${TAG}" \
  "${provenance_wrapper}" "${provenance_agent}" "${provenance_dir}" \
  || fail "release provenance could not be written on this host"
[[ "$(plutil -extract tag raw "${provenance_dir}/release-provenance.json")" == "${TAG}" \
  && "$(plutil -extract wrapper_commit raw "${provenance_dir}/release-provenance.json")" == "${provenance_wrapper}" \
  && "$(plutil -extract agent_commit raw "${provenance_dir}/release-provenance.json")" == "${provenance_agent}" ]] \
  || fail "release provenance did not read back"
rm -rf "${provenance_dir}"

bash "${SCRIPT_DIR}/test-release-source-policy.sh"
bash "${SCRIPT_DIR}/test-release-dmg.sh"

printf 'Release isolation policy passed.\n'
