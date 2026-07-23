#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
ARCHIVE=""
CHECKSUM=""
TAG=""
WRAPPER_COMMIT=""
AGENT_COMMIT=""
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
    '       --tag vX.Y.Z --wrapper-commit SHA --agent-commit SHA' >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --archive) ARCHIVE="${2:?--archive requires a value}"; shift 2 ;;
    --checksum) CHECKSUM="${2:?--checksum requires a value}"; shift 2 ;;
    --tag) TAG="${2:?--tag requires a value}"; shift 2 ;;
    --wrapper-commit) WRAPPER_COMMIT="${2:?--wrapper-commit requires a value}"; shift 2 ;;
    --agent-commit) AGENT_COMMIT="${2:?--agent-commit requires a value}"; shift 2 ;;
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
ENTRY_LIST="${WORK_DIR}/entries.txt"
DETAIL_LIST="${WORK_DIR}/entry-details.txt"
tar -tzf "${ARCHIVE}" > "${ENTRY_LIST}"
tar -tvzf "${ARCHIVE}" > "${DETAIL_LIST}"
[[ -s "${ENTRY_LIST}" ]] || fail "archive is empty"
if [[ -n "$(LC_ALL=C sort "${ENTRY_LIST}" | uniq -d)" ]]; then
  fail "archive contains duplicate entries"
fi

while IFS= read -r entry; do
  [[ -n "${entry}" ]] || fail "archive contains an empty entry"
  case "${entry}" in
    /*|../*|*/../*|*/..) fail "archive contains an unsafe path" ;;
  esac
  case "${entry}" in
    "LabTether Agent.app"|"LabTether Agent.app/"|"LabTether Agent.app/"*) ;;
    *) fail "archive contains an unexpected top-level entry" ;;
  esac
done < "${ENTRY_LIST}"

if awk 'substr($1, 1, 1) != "d" && substr($1, 1, 1) != "-" { found=1 } END { exit(found ? 0 : 1) }' "${DETAIL_LIST}"; then
  fail "archive contains a link or special-file entry"
fi
if grep -Eq ' -> | link to ' "${DETAIL_LIST}"; then
  fail "archive contains a symlink or hard link"
fi

EXTRACT_DIR="${WORK_DIR}/extract"
mkdir -m 700 "${EXTRACT_DIR}"
tar -xzf "${ARCHIVE}" -C "${EXTRACT_DIR}"
APP_PATH="${EXTRACT_DIR}/LabTether Agent.app"
[[ -d "${APP_PATH}" && ! -L "${APP_PATH}" ]] || fail "archive did not produce one regular app bundle"
if find "${APP_PATH}" -type l -print -quit | grep -q .; then
  fail "extracted app contains a symlink"
fi
if find "${APP_PATH}" -type f -links +1 -print -quit | grep -q .; then
  fail "extracted app contains a hard-linked file"
fi

PROVENANCE="${APP_PATH}/Contents/Resources/release-provenance.json"
[[ -f "${PROVENANCE}" && ! -L "${PROVENANCE}" ]] || fail "signed release provenance is missing"
[[ "$(plutil -extract tag raw "${PROVENANCE}")" == "${TAG}" ]] || fail "release provenance tag mismatch"
[[ "$(plutil -extract wrapper_commit raw "${PROVENANCE}")" == "${WRAPPER_COMMIT}" ]] || fail "release provenance wrapper commit mismatch"
[[ "$(plutil -extract agent_commit raw "${PROVENANCE}")" == "${AGENT_COMMIT}" ]] || fail "release provenance agent commit mismatch"
[[ "$(plutil -extract CFBundleShortVersionString raw "${APP_PATH}/Contents/Info.plist")" == "${TAG#v}" ]] || fail "app version does not match tag"

"${SCRIPT_DIR}/validate-app.sh" \
  "${APP_PATH}" \
  --architectures arm64,x86_64 \
  --agent-version "${TAG}" \
  --require-signature >/dev/null 2>&1 || fail "strict app validation failed"

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
[[ "${APP_TEAM_ID}" =~ ^[A-Z0-9]{10}$ ]] || fail "app Team Identifier is not a 10-character Apple team ID"
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

printf 'Verified notarized LabTether macOS release archive for %s.\n' "${TAG}"
