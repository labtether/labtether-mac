#!/usr/bin/env bash

set +x
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
# shellcheck source=scripts/release-signing.sh
source "${SCRIPT_DIR}/release-signing.sh"

TAG=""
BUILD_NUMBER=""
AGENT_REPO_INPUT=""
OUTPUT_DIR_INPUT=""
SIGNING_IDENTITY=""
NOTARY_PROFILE=""
CONFIRM_NOTARIZE=""
DRY_RUN=false

TEMP_BASE=""
TEMP_ROOT=""
OUTPUT_DIR=""
RELEASE_COMPLETE=false
CODESIGN_KEYCHAIN_ARGS=()
NOTARY_AUTH_ARGS=()

cleanup() {
  unset SIGNING_IDENTITY NOTARY_PROFILE
  if [[ "${RELEASE_COMPLETE}" != "true" && -n "${OUTPUT_DIR}" \
    && -d "${OUTPUT_DIR}" && ! -L "${OUTPUT_DIR}" ]]; then
    remove_placed_release_assets "${OUTPUT_DIR}"
  fi
  if [[ -n "${TEMP_ROOT}" && -n "${TEMP_BASE}" \
    && "${TEMP_ROOT}" == "${TEMP_BASE%/}/labtether-mac-release."* \
    && -d "${TEMP_ROOT}" && ! -L "${TEMP_ROOT}" ]]; then
    chmod -R u+w "${TEMP_ROOT}" >/dev/null 2>&1 || true
    rm -rf -- "${TEMP_ROOT}"
  fi
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

fail() {
  printf 'local release preparation failed: %s\n' "$1" >&2
  exit 1
}

usage() {
  printf '%s\n' \
    'Usage: scripts/release-local.sh --tag vX.Y.Z --build-number N' \
    '       --agent-repo PATH --output-dir PATH --confirm-notarize vX.Y.Z' \
    '       [--dry-run]' \
    '' \
    'The output directory must already exist, be empty, and be outside both repositories.' \
    'The script always reads signing and notary selectors silently from the controlling terminal.' >&2
}

path_is_within() {
  local candidate="$1"
  local parent="$2"
  case "${candidate}/" in
    "${parent%/}/"*) return 0 ;;
    *) return 1 ;;
  esac
}

repo_is_clean() {
  local repo="$1"
  [[ -z "$(GIT_OPTIONAL_LOCKS=0 git -C "${repo}" status --porcelain=v1 --untracked-files=all)" ]]
}

repo_tagged_head() {
  local repo="$1"
  local head_commit
  local tag_commit
  head_commit="$(git -C "${repo}" rev-parse HEAD 2>/dev/null)" || return 1
  tag_commit="$(git -C "${repo}" rev-parse --verify "refs/tags/${TAG}^{commit}" 2>/dev/null)" || return 1
  [[ "${head_commit}" == "${tag_commit}" ]]
}

# shellcheck source=scripts/release-source-policy.sh
source "${SCRIPT_DIR}/release-source-policy.sh"

silent_prompt() {
  local prompt="$1"
  local variable_name="$2"
  local value=""
  printf '%s' "${prompt}" >/dev/tty
  IFS= read -r -s value </dev/tty || fail "could not read a required local selector"
  printf '\n' >/dev/tty
  printf -v "${variable_name}" '%s' "${value}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) TAG="${2:?--tag requires a value}"; shift 2 ;;
    --build-number) BUILD_NUMBER="${2:?--build-number requires a value}"; shift 2 ;;
    --agent-repo) AGENT_REPO_INPUT="${2:?--agent-repo requires a value}"; shift 2 ;;
    --output-dir) OUTPUT_DIR_INPUT="${2:?--output-dir requires a value}"; shift 2 ;;
    --confirm-notarize) CONFIRM_NOTARIZE="${2:?--confirm-notarize requires a value}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

[[ "${TAG}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "tag must be vX.Y.Z"
[[ "${BUILD_NUMBER}" =~ ^[1-9][0-9]*$ ]] || fail "build number must be a positive integer"
[[ -n "${AGENT_REPO_INPUT}" && -d "${AGENT_REPO_INPUT}" && ! -L "${AGENT_REPO_INPUT}" ]] \
  || fail "agent repository must be a non-symlink directory"
[[ -n "${OUTPUT_DIR_INPUT}" && -d "${OUTPUT_DIR_INPUT}" && ! -L "${OUTPUT_DIR_INPUT}" ]] \
  || fail "output directory must be an existing non-symlink directory"

AGENT_REPO="$(cd "${AGENT_REPO_INPUT}" && pwd -P)"
OUTPUT_DIR="$(cd "${OUTPUT_DIR_INPUT}" && pwd -P)"
[[ "$(git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]] \
  || fail "wrapper source is not a Git worktree"
[[ "$(git -C "${AGENT_REPO}" rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]] \
  || fail "agent source is not a Git worktree"

if path_is_within "${OUTPUT_DIR}" "${REPO_ROOT}" || path_is_within "${OUTPUT_DIR}" "${AGENT_REPO}"; then
  fail "output directory must be outside both source repositories"
fi
[[ -w "${OUTPUT_DIR}" && -x "${OUTPUT_DIR}" ]] || fail "output directory must be writable"
if find "${OUTPUT_DIR}" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
  fail "output directory must be empty"
fi
repo_is_clean "${REPO_ROOT}" || fail "wrapper repository must be clean, including untracked files"
repo_is_clean "${AGENT_REPO}" || fail "agent repository must be clean, including untracked files"
repo_tagged_head "${REPO_ROOT}" || fail "wrapper HEAD must exactly match the requested local tag"
repo_tagged_head "${AGENT_REPO}" || fail "agent HEAD must exactly match the requested local tag"
repo_has_forbidden_release_input "${REPO_ROOT}" \
  && fail "wrapper source contains a tracked symlink or certificate/key file"
repo_has_forbidden_release_input "${AGENT_REPO}" \
  && fail "agent source contains a tracked symlink or certificate/key file"

WRAPPER_COMMIT="$(git -C "${REPO_ROOT}" rev-parse HEAD)"
AGENT_COMMIT="$(git -C "${AGENT_REPO}" rev-parse HEAD)"
[[ "${WRAPPER_COMMIT}" =~ ^[0-9a-f]{40}$ && "${AGENT_COMMIT}" =~ ^[0-9a-f]{40}$ ]] \
  || fail "source commits must be full lowercase SHAs"

if [[ "${DRY_RUN}" == "true" ]]; then
  printf 'Dry run passed local tag, source, and output safety checks for %s; no build, signing, network, or publication action was taken.\n' "${TAG}"
  exit 0
fi

[[ "${CONFIRM_NOTARIZE}" == "${TAG}" ]] \
  || fail "--confirm-notarize must exactly match the release tag"
[[ -t 0 && -t 1 && -r /dev/tty && -w /dev/tty ]] \
  || fail "an interactive terminal is required for local signing and notarization"

silent_prompt 'Developer ID Application selector: ' SIGNING_IDENTITY
silent_prompt 'Notary Keychain profile: ' NOTARY_PROFILE
case "${SIGNING_IDENTITY}" in
  "Developer ID Application: "*" (${RELEASE_TEAM_ID})") ;;
  *) fail "the signing selector must choose a Developer ID Application identity of team ${RELEASE_TEAM_ID}" ;;
esac
[[ "${NOTARY_PROFILE}" =~ ^[A-Za-z0-9._-]+$ ]] \
  || fail "the notary profile selector contains unsupported characters"

for command_name in codesign ditto find git go hdiutil lipo plutil security shasum spctl swift tar xattr xcrun; do
  command -v "${command_name}" >/dev/null 2>&1 || fail "a required local release command is unavailable"
done
identity_count="$(
  security find-identity -v -p codesigning 2>/dev/null \
    | awk -v identity="${SIGNING_IDENTITY}" 'index($0, "\"" identity "\"") > 0 { count++ } END { print count + 0 }'
)"
[[ "${identity_count}" == "1" ]] || fail "the local signing selector must match exactly one valid identity"

TEMP_BASE="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
if path_is_within "${TEMP_BASE}" "${REPO_ROOT}" || path_is_within "${TEMP_BASE}" "${AGENT_REPO}"; then
  fail "the temporary directory must be outside both source repositories"
fi
TEMP_ROOT="$(mktemp -d "${TEMP_BASE%/}/labtether-mac-release.XXXXXX")"
chmod 700 "${TEMP_ROOT}"
STAGE_DIR="${TEMP_ROOT}/stage"
NOTARY_DIR="${TEMP_ROOT}/notary"
ASSET_DIR="${TEMP_ROOT}/assets"
mkdir -m 700 "${TEMP_ROOT}/unsigned" "${TEMP_ROOT}/list" "${STAGE_DIR}" "${NOTARY_DIR}" "${ASSET_DIR}"

# Tests, build and release record, the same step the GitHub build job runs.
TMPDIR="${TEMP_ROOT}" "${SCRIPT_DIR}/prepare-unsigned-release.sh" \
  --tag "${TAG}" --build-number "${BUILD_NUMBER}" \
  --agent-repo "${AGENT_REPO}" --output-dir "${TEMP_ROOT}/unsigned"
UNSIGNED_ARCHIVE="${TEMP_ROOT}/unsigned/labtether-agent-macos-unsigned-app.tar.gz"
check_app_archive_entries "${UNSIGNED_ARCHIVE}" "${TEMP_ROOT}/list"
extract_app_archive "${UNSIGNED_ARCHIVE}" "${STAGE_DIR}"
check_app_release_record "${STAGE_DIR}/LabTether Agent.app" "${TAG}" "${WRAPPER_COMMIT}" "${AGENT_COMMIT}"

NOTARY_AUTH_ARGS=(--keychain-profile "${NOTARY_PROFILE}")
sign_and_package_release
unset SIGNING_IDENTITY NOTARY_PROFILE
NOTARY_AUTH_ARGS=()

"${SCRIPT_DIR}/verify-release-archive.sh" \
  --archive "${ASSET_DIR}/${ARCHIVE_NAME}" \
  --checksum "${ASSET_DIR}/${CHECKSUM_NAME}" \
  --dmg "${ASSET_DIR}/${DMG_NAME}" \
  --dmg-checksum "${ASSET_DIR}/${DMG_CHECKSUM_NAME}" \
  --tag "${TAG}" \
  --wrapper-commit "${WRAPPER_COMMIT}" \
  --agent-commit "${AGENT_COMMIT}"

place_release_assets "${ASSET_DIR}" "${OUTPUT_DIR}"
RELEASE_COMPLETE=true

printf 'Prepared exactly four verified local release assets for %s. Nothing was published.\n' "${TAG}"
