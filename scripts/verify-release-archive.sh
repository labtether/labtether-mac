#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
# shellcheck source=scripts/release-signing.sh
source "${SCRIPT_DIR}/release-signing.sh"
ARCHIVE=""
CHECKSUM=""
DMG=""
DMG_CHECKSUM=""
TAG=""
WRAPPER_COMMIT=""
AGENT_COMMIT=""
VALIDATE_RUN_ARGS=()
TEMP_BASE=""
WORK_DIR=""

cleanup() {
  if [[ -n "${WORK_DIR}" && -d "${WORK_DIR}" && ! -L "${WORK_DIR}" ]]; then
    chmod -R u+w "${WORK_DIR}" >/dev/null 2>&1 || true
    rm -rf -- "${WORK_DIR}"
  fi
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

fail() {
  printf 'release archive verification failed: %s\n' "$1" >&2
  exit 1
}

usage() {
  printf '%s\n' \
    'Usage: scripts/verify-release-archive.sh --archive PATH --checksum PATH' \
    '       --dmg PATH --dmg-checksum PATH' \
    '       --tag vX.Y.Z --wrapper-commit SHA --agent-commit SHA [--no-run]' \
    '--no-run checks the files without starting the bundled agent.' >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive) ARCHIVE="${2:?--archive requires a value}"; shift 2 ;;
    --checksum) CHECKSUM="${2:?--checksum requires a value}"; shift 2 ;;
    --dmg) DMG="${2:?--dmg requires a value}"; shift 2 ;;
    --dmg-checksum) DMG_CHECKSUM="${2:?--dmg-checksum requires a value}"; shift 2 ;;
    --tag) TAG="${2:?--tag requires a value}"; shift 2 ;;
    --wrapper-commit) WRAPPER_COMMIT="${2:?--wrapper-commit requires a value}"; shift 2 ;;
    --agent-commit) AGENT_COMMIT="${2:?--agent-commit requires a value}"; shift 2 ;;
    --no-run) VALIDATE_RUN_ARGS=(--no-run); shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

[[ "${TAG}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "tag must be vX.Y.Z"
[[ "${WRAPPER_COMMIT}" =~ ^[0-9a-f]{40}$ ]] || fail "wrapper commit must be a full lowercase SHA"
[[ "${AGENT_COMMIT}" =~ ^[0-9a-f]{40}$ ]] || fail "agent commit must be a full lowercase SHA"
[[ -n "${ARCHIVE}" && -f "${ARCHIVE}" && ! -L "${ARCHIVE}" ]] || fail "archive must be a non-symlink regular file"
[[ -n "${CHECKSUM}" && -f "${CHECKSUM}" && ! -L "${CHECKSUM}" ]] || fail "checksum must be a non-symlink regular file"
[[ "$(basename "${ARCHIVE}")" == "labtether-agent-macos-universal.tar.gz" ]] || fail "unexpected archive filename"
[[ "$(basename "${CHECKSUM}")" == "labtether-agent-macos-universal.tar.gz.sha256" ]] || fail "unexpected checksum filename"
[[ -n "${DMG}" && -f "${DMG}" && ! -L "${DMG}" ]] || fail "disk image must be a non-symlink regular file"
[[ -n "${DMG_CHECKSUM}" && -f "${DMG_CHECKSUM}" && ! -L "${DMG_CHECKSUM}" ]] || fail "disk image checksum must be a non-symlink regular file"

line_count="$(wc -l < "${CHECKSUM}" | tr -d ' ')"
[[ "${line_count}" == "1" ]] || fail "checksum must contain exactly one line"
LC_ALL=C grep -Eq '^[0-9a-f]{64}  labtether-agent-macos-universal\.tar\.gz$' "${CHECKSUM}" \
  || fail "checksum line must use the exact lowercase digest and archive basename format"
checksum_hash="$(awk 'NR == 1 { print $1 }' "${CHECKSUM}")"
checksum_name="$(awk 'NR == 1 { print $2 }' "${CHECKSUM}")"
checksum_name="${checksum_name#\*}"
[[ "${checksum_hash}" =~ ^[0-9a-f]{64}$ ]] || fail "checksum digest must be lowercase SHA-256"
[[ "${checksum_name}" == "labtether-agent-macos-universal.tar.gz" ]] || fail "checksum must name only the release archive basename"
actual_hash="$(shasum -a 256 "${ARCHIVE}" | awk '{ print $1 }')"
[[ "${actual_hash}" == "${checksum_hash}" ]] || fail "archive checksum mismatch"

TEMP_BASE="$(cd "${TMPDIR:-/tmp}" && pwd -P)" || fail "temporary directory is unavailable"
case "${TEMP_BASE}/" in
  "${REPO_ROOT%/}/"*) fail "temporary verification files must stay outside the source repository" ;;
esac
WORK_DIR="$(mktemp -d "${TEMP_BASE%/}/labtether-mac-verify.XXXXXX")"
chmod 700 "${WORK_DIR}"
mkdir -m 700 "${WORK_DIR}/list" "${WORK_DIR}/extract"
check_app_archive_entries "${ARCHIVE}" "${WORK_DIR}/list"
extract_app_archive "${ARCHIVE}" "${WORK_DIR}/extract"
APP_PATH="${WORK_DIR}/extract/LabTether Agent.app"
check_app_release_record "${APP_PATH}" "${TAG}" "${WRAPPER_COMMIT}" "${AGENT_COMMIT}"

"${SCRIPT_DIR}/validate-app.sh" \
  "${APP_PATH}" \
  --architectures arm64,x86_64 \
  --agent-version "${TAG}" \
  --require-signature ${VALIDATE_RUN_ARGS[@]+"${VALIDATE_RUN_ARGS[@]}"} >/dev/null 2>&1 \
  || fail "strict app validation failed"

APP_SIGNATURE_DETAILS="$(codesign -dvvv "${APP_PATH}" 2>&1)" \
  || fail "app signature metadata could not be read"
HOST_SIGNATURE_DETAILS="$(codesign -dvvv "${APP_PATH}/Contents/MacOS/LabTetherAgent" 2>&1)" \
  || fail "host signature metadata could not be read"
CHILD_SIGNATURE_DETAILS="$(codesign -dvvv "${APP_PATH}/Contents/Resources/labtether-agent" 2>&1)" \
  || fail "child signature metadata could not be read"

for signature_details in "${APP_SIGNATURE_DETAILS}" "${HOST_SIGNATURE_DETAILS}" "${CHILD_SIGNATURE_DETAILS}"; do
  printf '%s\n' "${signature_details}" | grep -q '^Authority=Developer ID Application:' \
    || fail "release code is not Developer ID Application signed"
  printf '%s\n' "${signature_details}" | grep -q 'flags=.*runtime' \
    || fail "hardened runtime is missing from release code"
  printf '%s\n' "${signature_details}" | grep -q '^Timestamp=' \
    || fail "secure signing timestamp is missing from release code"
done

APP_TEAM_ID="$(printf '%s\n' "${APP_SIGNATURE_DETAILS}" | awk -F= '/^TeamIdentifier=/{ print $2; exit }')"
HOST_TEAM_ID="$(printf '%s\n' "${HOST_SIGNATURE_DETAILS}" | awk -F= '/^TeamIdentifier=/{ print $2; exit }')"
CHILD_TEAM_ID="$(printf '%s\n' "${CHILD_SIGNATURE_DETAILS}" | awk -F= '/^TeamIdentifier=/{ print $2; exit }')"
[[ "${APP_TEAM_ID}" == "${RELEASE_TEAM_ID}" ]] \
  || fail "release code is not signed by the Watari Labs team ${RELEASE_TEAM_ID}"
[[ "${APP_TEAM_ID}" == "${HOST_TEAM_ID}" && "${APP_TEAM_ID}" == "${CHILD_TEAM_ID}" ]] \
  || fail "app, host, and child Team Identifiers do not match"

APP_DEVELOPER_AUTHORITY="$(printf '%s\n' "${APP_SIGNATURE_DETAILS}" | awk '/^Authority=Developer ID Application:/{ sub(/^Authority=/, ""); print; exit }')"
HOST_DEVELOPER_AUTHORITY="$(printf '%s\n' "${HOST_SIGNATURE_DETAILS}" | awk '/^Authority=Developer ID Application:/{ sub(/^Authority=/, ""); print; exit }')"
CHILD_DEVELOPER_AUTHORITY="$(printf '%s\n' "${CHILD_SIGNATURE_DETAILS}" | awk '/^Authority=Developer ID Application:/{ sub(/^Authority=/, ""); print; exit }')"
[[ -n "${APP_DEVELOPER_AUTHORITY}" ]] || fail "Developer ID Application authority is missing"
[[ "${APP_DEVELOPER_AUTHORITY}" == "${HOST_DEVELOPER_AUTHORITY}" \
  && "${APP_DEVELOPER_AUTHORITY}" == "${CHILD_DEVELOPER_AUTHORITY}" ]] \
  || fail "app, host, and child Developer ID authorities do not match"
[[ "${APP_DEVELOPER_AUTHORITY}" == *"(${APP_TEAM_ID})" ]] \
  || fail "Developer ID authority does not end with the verified Team Identifier"
unset APP_SIGNATURE_DETAILS HOST_SIGNATURE_DETAILS CHILD_SIGNATURE_DETAILS
unset APP_TEAM_ID HOST_TEAM_ID CHILD_TEAM_ID
unset APP_DEVELOPER_AUTHORITY HOST_DEVELOPER_AUTHORITY CHILD_DEVELOPER_AUTHORITY

xcrun stapler validate "${APP_PATH}" >/dev/null 2>&1 || fail "stapled notarization ticket is missing or invalid"
spctl --assess --type execute --verbose=4 "${APP_PATH}" >/dev/null 2>&1 || fail "Gatekeeper assessment failed"

# The disk image must hold this same verified app and carry its own
# Developer ID signature and stapled ticket.
"${SCRIPT_DIR}/verify-release-dmg.sh" \
  --dmg "${DMG}" \
  --checksum "${DMG_CHECKSUM}" \
  --app "${APP_PATH}" \
  --require-notarized >/dev/null || fail "release disk image verification failed"

printf 'Verified notarized LabTether macOS release archive and disk image for %s.\n' "${TAG}"
