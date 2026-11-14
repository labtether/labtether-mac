#!/usr/bin/env bash

set +x
set -Eeuo pipefail

# Tests the two release checkouts, builds the unsigned universal app with its
# release record, and writes it as one archive for the signing step. Needs no
# signing material. Used by release-local.sh and by the build job of
# .github/workflows/signed-release.yml.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
# shellcheck source=scripts/release-provenance.sh
source "${SCRIPT_DIR}/release-provenance.sh"
# shellcheck source=scripts/release-source-policy.sh
source "${SCRIPT_DIR}/release-source-policy.sh"

UNSIGNED_NAME="labtether-agent-macos-unsigned-app.tar.gz"
TAG=""
BUILD_NUMBER=""
AGENT_REPO_INPUT=""
OUTPUT_DIR_INPUT=""
UNTAGGED_PROOF=false
TEMP_ROOT=""

cleanup() {
  if [[ -n "${TEMP_ROOT}" && -d "${TEMP_ROOT}" && ! -L "${TEMP_ROOT}" ]]; then
    chmod -R u+w "${TEMP_ROOT}" >/dev/null 2>&1 || true
    rm -rf -- "${TEMP_ROOT}"
  fi
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

fail() {
  printf 'unsigned release preparation failed: %s\n' "$1" >&2
  exit 1
}

usage() {
  printf '%s\n' \
    'Usage: scripts/prepare-unsigned-release.sh --tag vX.Y.Z --build-number N' \
    '       --agent-repo PATH --output-dir PATH [--untagged-proof]' \
    '' \
    "Writes ${UNSIGNED_NAME} to the empty output directory." \
    '--untagged-proof builds the checked-out commits without requiring the tag,' \
    'for a signing proof run that publishes nothing.' >&2
}

path_is_within() {
  case "$1/" in
    "${2%/}/"*) return 0 ;;
    *) return 1 ;;
  esac
}

repo_is_clean() {
  [[ -z "$(GIT_OPTIONAL_LOCKS=0 git -C "$1" status --porcelain=v1 --untracked-files=all)" ]]
}

repo_tagged_head() {
  local head_commit tag_commit
  head_commit="$(git -C "$1" rev-parse HEAD 2>/dev/null)" || return 1
  tag_commit="$(git -C "$1" rev-parse --verify "refs/tags/${TAG}^{commit}" 2>/dev/null)" || return 1
  [[ "${head_commit}" == "${tag_commit}" ]]
}

check_sources() {
  repo_is_clean "${REPO_ROOT}" || fail "wrapper repository must be clean, including untracked files"
  repo_is_clean "${AGENT_REPO}" || fail "agent repository must be clean, including untracked files"
  if [[ "${UNTAGGED_PROOF}" != "true" ]]; then
    repo_tagged_head "${REPO_ROOT}" || fail "wrapper HEAD must exactly match the requested local tag"
    repo_tagged_head "${AGENT_REPO}" || fail "agent HEAD must exactly match the requested local tag"
  fi
  [[ "$(git -C "${REPO_ROOT}" rev-parse HEAD)" == "${WRAPPER_COMMIT}" ]] || fail "wrapper source moved"
  [[ "$(git -C "${AGENT_REPO}" rev-parse HEAD)" == "${AGENT_COMMIT}" ]] || fail "agent source moved"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) TAG="${2:?--tag requires a value}"; shift 2 ;;
    --build-number) BUILD_NUMBER="${2:?--build-number requires a value}"; shift 2 ;;
    --agent-repo) AGENT_REPO_INPUT="${2:?--agent-repo requires a value}"; shift 2 ;;
    --output-dir) OUTPUT_DIR_INPUT="${2:?--output-dir requires a value}"; shift 2 ;;
    --untagged-proof) UNTAGGED_PROOF=true; shift ;;
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
if find "${OUTPUT_DIR}" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
  fail "output directory must be empty"
fi
WRAPPER_COMMIT="$(git -C "${REPO_ROOT}" rev-parse HEAD)"
AGENT_COMMIT="$(git -C "${AGENT_REPO}" rev-parse HEAD)"
[[ "${WRAPPER_COMMIT}" =~ ^[0-9a-f]{40}$ && "${AGENT_COMMIT}" =~ ^[0-9a-f]{40}$ ]] \
  || fail "source commits must be full lowercase SHAs"
check_sources
repo_has_forbidden_release_input "${REPO_ROOT}" \
  && fail "wrapper source contains a tracked symlink or certificate/key file"
repo_has_forbidden_release_input "${AGENT_REPO}" \
  && fail "agent source contains a tracked symlink or certificate/key file"

for command_name in git go lipo plutil swift tar xattr; do
  command -v "${command_name}" >/dev/null 2>&1 || fail "a required release build command is unavailable"
done
[[ "$(go version)" == "go version go1.27.3 "* ]] || fail "the Go release builder must be go1.27.3"

TEMP_BASE="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
if path_is_within "${TEMP_BASE}" "${REPO_ROOT}" || path_is_within "${TEMP_BASE}" "${AGENT_REPO}"; then
  fail "the temporary directory must be outside both source repositories"
fi
TEMP_ROOT="$(mktemp -d "${TEMP_BASE%/}/labtether-mac-prepare.XXXXXX")"
chmod 700 "${TEMP_ROOT}"
mkdir -m 700 "${TEMP_ROOT}/swift-test" "${TEMP_ROOT}/swift-release" "${TEMP_ROOT}/stage"

printf 'Running pinned source gates for %s.\n' "${TAG}"
(cd "${REPO_ROOT}" && swift test --scratch-path "${TEMP_ROOT}/swift-test")
(
  cd "${AGENT_REPO}"
  go test ./...
  go test -race ./...
  go vet ./...
)
check_sources

LABTETHER_AGENT_REPO="${AGENT_REPO}" \
LABTETHER_AGENT_VERSION="${TAG}" \
LABTETHER_APP_VERSION="${TAG#v}" \
LABTETHER_APP_BUILD_NUMBER="${BUILD_NUMBER}" \
LABTETHER_SWIFT_SCRATCH_PATH="${TEMP_ROOT}/swift-release" \
  "${SCRIPT_DIR}/build-app.sh" --configuration release --universal \
    --output-dir "${TEMP_ROOT}/stage" --no-sign
check_sources

APP_PATH="${TEMP_ROOT}/stage/LabTether Agent.app"
[[ -d "${APP_PATH}" && ! -L "${APP_PATH}" ]] || fail "build did not produce a regular app bundle"
RECORD_PATH="${APP_PATH}/Contents/Resources/release-provenance.json"
write_release_provenance "${RECORD_PATH}" "${TAG}" "${WRAPPER_COMMIT}" "${AGENT_COMMIT}" "${TEMP_ROOT}" \
  || fail "writing the release record failed"
chmod 0644 "${RECORD_PATH}"
xattr -cr "${APP_PATH}"

(cd "${TEMP_ROOT}/stage" && COPYFILE_DISABLE=1 tar -czf "${TEMP_ROOT}/${UNSIGNED_NAME}" "LabTether Agent.app") \
  || fail "writing the unsigned app archive failed"
mv -n -- "${TEMP_ROOT}/${UNSIGNED_NAME}" "${OUTPUT_DIR}/${UNSIGNED_NAME}"
[[ -f "${OUTPUT_DIR}/${UNSIGNED_NAME}" && ! -L "${OUTPUT_DIR}/${UNSIGNED_NAME}" ]] \
  || fail "placing the unsigned app archive failed"
printf 'Prepared the unsigned app for %s (wrapper %s, agent %s). Nothing was signed.\n' \
  "${TAG}" "${WRAPPER_COMMIT}" "${AGENT_COMMIT}"
