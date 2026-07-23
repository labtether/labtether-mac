#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"

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
ARCHIVE_OUTPUT_MOVED=false
CHECKSUM_OUTPUT_MOVED=false
RELEASE_COMPLETE=false
ARCHIVE_NAME="labtether-agent-macos-universal.tar.gz"
CHECKSUM_NAME="${ARCHIVE_NAME}.sha256"

cleanup() {
  if [[ "${RELEASE_COMPLETE}" != "true" && -n "${OUTPUT_DIR}" \
    && -d "${OUTPUT_DIR}" && ! -L "${OUTPUT_DIR}" ]]; then
    if [[ "${ARCHIVE_OUTPUT_MOVED}" == "true" ]]; then
      rm -f -- "${OUTPUT_DIR}/${ARCHIVE_NAME}"
    fi
    if [[ "${CHECKSUM_OUTPUT_MOVED}" == "true" ]]; then
      rm -f -- "${OUTPUT_DIR}/${CHECKSUM_NAME}"
    fi
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

repo_has_forbidden_release_input() {
  local repo="$1"
  local tracked_path
  local lowercase_path
  if git -C "${repo}" ls-files -s \
    | awk '$1 == "120000" { found=1 } END { exit(found ? 0 : 1) }'; then
    return 0
  fi
  while IFS= read -r -d '' tracked_path; do
    lowercase_path="$(printf '%s' "${tracked_path}" | tr '[:upper:]' '[:lower:]')"
    case "${lowercase_path}" in
      *.p12|*.pfx|*.p8|*.pem|*.key|*.cer|*.crt|*.der|*.jks|*.keystore|*.keychain|*.keychain-db|*.mobileprovision|*.provisionprofile)
        return 0
        ;;
    esac
  done < <(git -C "${repo}" ls-files -z)
  return 1
}

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
  "Developer ID Application: "*) ;;
  *) fail "the signing selector must choose a Developer ID Application identity" ;;
esac
[[ "${NOTARY_PROFILE}" =~ ^[A-Za-z0-9._-]+$ ]] \
  || fail "the notary profile selector contains unsupported characters"

for command_name in codesign ditto find git go lipo plutil security shasum spctl swift tar xattr xcrun; do
  command -v "${command_name}" >/dev/null 2>&1 || fail "a required local release command is unavailable"
done

TEMP_BASE="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
if path_is_within "${TEMP_BASE}" "${REPO_ROOT}" || path_is_within "${TEMP_BASE}" "${AGENT_REPO}"; then
  fail "the temporary directory must be outside both source repositories"
fi
TEMP_ROOT="$(mktemp -d "${TEMP_BASE%/}/labtether-mac-release.XXXXXX")"
chmod 700 "${TEMP_ROOT}"
SWIFT_TEST_SCRATCH="${TEMP_ROOT}/swift-test"
SWIFT_BUILD_SCRATCH="${TEMP_ROOT}/swift-release"
STAGE_DIR="${TEMP_ROOT}/stage"
NOTARY_DIR="${TEMP_ROOT}/notary"
mkdir -m 700 "${SWIFT_TEST_SCRATCH}" "${SWIFT_BUILD_SCRATCH}" "${STAGE_DIR}" "${NOTARY_DIR}"

printf 'Running pinned source gates for %s.\n' "${TAG}"
(
  cd "${REPO_ROOT}"
  swift test --scratch-path "${SWIFT_TEST_SCRATCH}"
)
(
  cd "${AGENT_REPO}"
  go test ./...
  go test -race ./...
  go vet ./...
)
repo_is_clean "${REPO_ROOT}" || fail "wrapper source changed during release gates"
repo_is_clean "${AGENT_REPO}" || fail "agent source changed during release gates"
repo_tagged_head "${REPO_ROOT}" || fail "wrapper tag moved during release gates"
repo_tagged_head "${AGENT_REPO}" || fail "agent tag moved during release gates"

LABTETHER_AGENT_REPO="${AGENT_REPO}" \
LABTETHER_AGENT_VERSION="${TAG}" \
LABTETHER_APP_VERSION="${TAG#v}" \
LABTETHER_APP_BUILD_NUMBER="${BUILD_NUMBER}" \
LABTETHER_SWIFT_SCRATCH_PATH="${SWIFT_BUILD_SCRATCH}" \
  "${SCRIPT_DIR}/build-app.sh" \
    --configuration release \
    --universal \
    --output-dir "${STAGE_DIR}" \
    --no-sign

APP_PATH="${STAGE_DIR}/LabTether Agent.app"
CHILD_PATH="${APP_PATH}/Contents/Resources/labtether-agent"
HOST_PATH="${APP_PATH}/Contents/MacOS/LabTetherAgent"
PROVENANCE_PATH="${APP_PATH}/Contents/Resources/release-provenance.json"
[[ -d "${APP_PATH}" && ! -L "${APP_PATH}" ]] || fail "build did not produce a regular app bundle"

plutil -create json "${PROVENANCE_PATH}"
plutil -insert tag -string "${TAG}" "${PROVENANCE_PATH}"
plutil -insert wrapper_commit -string "${WRAPPER_COMMIT}" "${PROVENANCE_PATH}"
plutil -insert agent_commit -string "${AGENT_COMMIT}" "${PROVENANCE_PATH}"
chmod 0644 "${PROVENANCE_PATH}"
xattr -cr "${APP_PATH}"

identity_count="$(
  security find-identity -v -p codesigning 2>/dev/null \
    | awk -v identity="${SIGNING_IDENTITY}" 'index($0, "\"" identity "\"") > 0 { count++ } END { print count + 0 }'
)"
[[ "${identity_count}" == "1" ]] || fail "the local signing selector must match exactly one valid identity"

if ! codesign --force --options runtime --timestamp --sign "${SIGNING_IDENTITY}" "${CHILD_PATH}" >/dev/null 2>&1; then
  fail "signing the bundled agent failed"
fi
if ! codesign --force --options runtime --timestamp --sign "${SIGNING_IDENTITY}" "${HOST_PATH}" >/dev/null 2>&1; then
  fail "signing the native host failed"
fi
if ! codesign --force --options runtime --timestamp --sign "${SIGNING_IDENTITY}" "${APP_PATH}" >/dev/null 2>&1; then
  fail "signing the app bundle failed"
fi
unset SIGNING_IDENTITY
if ! "${SCRIPT_DIR}/validate-app.sh" \
  "${APP_PATH}" \
  --architectures arm64,x86_64 \
  --agent-version "${TAG}" \
  --require-signature >/dev/null 2>&1; then
  fail "strict signed app validation failed"
fi

NOTARY_ARCHIVE="${NOTARY_DIR}/submission.zip"
NOTARY_RESULT="${NOTARY_DIR}/result.json"
if ! ditto -c -k --keepParent "${APP_PATH}" "${NOTARY_ARCHIVE}" >/dev/null 2>&1; then
  fail "creating the local notarization submission failed"
fi
if ! xcrun notarytool submit "${NOTARY_ARCHIVE}" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --wait \
  --output-format json >"${NOTARY_RESULT}" 2>/dev/null; then
  fail "Apple notarization submission failed"
fi
unset NOTARY_PROFILE
notary_result_status="$(plutil -extract status raw "${NOTARY_RESULT}" 2>/dev/null || true)"
[[ "${notary_result_status}" == "Accepted" ]] || fail "Apple notarization did not return Accepted"

if ! xcrun stapler staple "${APP_PATH}" >/dev/null 2>&1; then
  fail "stapling the notarization ticket failed"
fi
if ! xcrun stapler validate "${APP_PATH}" >/dev/null 2>&1; then
  fail "the stapled notarization ticket did not validate"
fi
if ! codesign --verify --deep --strict --verbose=4 "${APP_PATH}" >/dev/null 2>&1; then
  fail "the final signed app did not pass strict verification"
fi
if ! spctl --assess --type execute --verbose=4 "${APP_PATH}" >/dev/null 2>&1; then
  fail "the final app did not pass Gatekeeper assessment"
fi

ARCHIVE_PATH="${TEMP_ROOT}/${ARCHIVE_NAME}"
CHECKSUM_PATH="${TEMP_ROOT}/${CHECKSUM_NAME}"
(
  cd "${STAGE_DIR}"
  COPYFILE_DISABLE=1 tar -czf "${ARCHIVE_PATH}" "LabTether Agent.app"
)
archive_hash="$(shasum -a 256 "${ARCHIVE_PATH}" | awk '{ print $1 }')"
[[ "${archive_hash}" =~ ^[0-9a-f]{64}$ ]] || fail "could not calculate the final archive checksum"
printf '%s  %s\n' "${archive_hash}" "${ARCHIVE_NAME}" >"${CHECKSUM_PATH}"
chmod 0600 "${ARCHIVE_PATH}" "${CHECKSUM_PATH}"

"${SCRIPT_DIR}/verify-release-archive.sh" \
  --archive "${ARCHIVE_PATH}" \
  --checksum "${CHECKSUM_PATH}" \
  --tag "${TAG}" \
  --wrapper-commit "${WRAPPER_COMMIT}" \
  --agent-commit "${AGENT_COMMIT}"

if find "${OUTPUT_DIR}" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
  fail "output directory changed before final placement"
fi
[[ ! -e "${OUTPUT_DIR}/${ARCHIVE_NAME}" && ! -L "${OUTPUT_DIR}/${ARCHIVE_NAME}" ]] \
  || fail "release archive destination already exists"
[[ ! -e "${OUTPUT_DIR}/${CHECKSUM_NAME}" && ! -L "${OUTPUT_DIR}/${CHECKSUM_NAME}" ]] \
  || fail "release checksum destination already exists"
mv -n -- "${ARCHIVE_PATH}" "${OUTPUT_DIR}/${ARCHIVE_NAME}"
[[ ! -e "${ARCHIVE_PATH}" && -f "${OUTPUT_DIR}/${ARCHIVE_NAME}" && ! -L "${OUTPUT_DIR}/${ARCHIVE_NAME}" ]] \
  || fail "release archive placement did not complete without overwrite"
ARCHIVE_OUTPUT_MOVED=true
mv -n -- "${CHECKSUM_PATH}" "${OUTPUT_DIR}/${CHECKSUM_NAME}"
[[ ! -e "${CHECKSUM_PATH}" && -f "${OUTPUT_DIR}/${CHECKSUM_NAME}" && ! -L "${OUTPUT_DIR}/${CHECKSUM_NAME}" ]] \
  || fail "release checksum placement did not complete without overwrite"
CHECKSUM_OUTPUT_MOVED=true
[[ "$(shasum -a 256 "${OUTPUT_DIR}/${ARCHIVE_NAME}" | awk '{ print $1 }')" == "${archive_hash}" ]] \
  || fail "placed release archive changed unexpectedly"
chmod 0644 "${OUTPUT_DIR}/${ARCHIVE_NAME}" "${OUTPUT_DIR}/${CHECKSUM_NAME}"
RELEASE_COMPLETE=true

printf 'Prepared exactly two verified local release assets for %s. Nothing was published.\n' "${TAG}"
