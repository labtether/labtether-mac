#!/usr/bin/env bash
set -euo pipefail

# Checks the release disk image against an app that was already verified:
# checksum, image integrity, exactly the app and an Applications shortcut
# inside, and the app's files byte for byte. --require-notarized also checks
# the image's own Developer ID signature, stapled ticket and Gatekeeper result.

DMG_NAME="labtether-agent-macos-universal.dmg"
CHECKSUM_NAME="${DMG_NAME}.sha256"
APP_NAME="LabTether Agent.app"
DMG=""
CHECKSUM=""
APP_PATH=""
REQUIRE_NOTARIZED=false
WORK_DIR=""
MOUNT_POINT=""
ATTACHED_DEVICE=""

cleanup() {
  if [[ -n "${ATTACHED_DEVICE}" ]]; then
    hdiutil detach -quiet "${ATTACHED_DEVICE}" >/dev/null 2>&1 \
      || hdiutil detach -quiet -force "${ATTACHED_DEVICE}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${WORK_DIR}" && -d "${WORK_DIR}" && ! -L "${WORK_DIR}" ]]; then
    rm -rf -- "${WORK_DIR}"
  fi
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

fail() {
  printf 'release disk image verification failed: %s\n' "$1" >&2
  exit 1
}

usage() {
  printf '%s\n' \
    'Usage: scripts/verify-release-dmg.sh --dmg PATH --checksum PATH' \
    '       --app "PATH/LabTether Agent.app" [--require-notarized]' >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dmg) DMG="${2:?--dmg requires a value}"; shift 2 ;;
    --checksum) CHECKSUM="${2:?--checksum requires a value}"; shift 2 ;;
    --app) APP_PATH="${2:?--app requires a value}"; shift 2 ;;
    --require-notarized) REQUIRE_NOTARIZED=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

[[ -n "${DMG}" && -f "${DMG}" && ! -L "${DMG}" ]] || fail "disk image must be a non-symlink regular file"
[[ -n "${CHECKSUM}" && -f "${CHECKSUM}" && ! -L "${CHECKSUM}" ]] || fail "checksum must be a non-symlink regular file"
[[ -n "${APP_PATH}" && -d "${APP_PATH}" && ! -L "${APP_PATH}" ]] || fail "the verified app must be a non-symlink application bundle"
[[ "$(basename "${DMG}")" == "${DMG_NAME}" ]] || fail "unexpected disk image filename"
[[ "$(basename "${CHECKSUM}")" == "${CHECKSUM_NAME}" ]] || fail "unexpected checksum filename"
[[ "$(basename "${APP_PATH}")" == "${APP_NAME}" ]] || fail "unexpected app name"

line_count="$(wc -l < "${CHECKSUM}" | tr -d ' ')"
[[ "${line_count}" == "1" ]] || fail "checksum must contain exactly one line"
LC_ALL=C grep -Eq '^[0-9a-f]{64}  labtether-agent-macos-universal\.dmg$' "${CHECKSUM}" \
  || fail "checksum line must use the exact lowercase digest and disk image basename format"
checksum_hash="$(awk 'NR == 1 { print $1 }' "${CHECKSUM}")"
actual_hash="$(shasum -a 256 "${DMG}" | awk '{ print $1 }')"
[[ "${actual_hash}" == "${checksum_hash}" ]] || fail "disk image checksum mismatch"

hdiutil verify -quiet "${DMG}" >/dev/null 2>&1 || fail "disk image did not pass hdiutil verify"

TEMP_BASE="$(cd "${TMPDIR:-/tmp}" && pwd -P)" || fail "temporary directory is unavailable"
WORK_DIR="$(mktemp -d "${TEMP_BASE%/}/labtether-dmg-verify.XXXXXX")"
chmod 700 "${WORK_DIR}"
# macOS picks the mount point (under /Volumes, hidden from Finder). A mount
# point of our own fails when the temporary directory is on a volume that
# ignores ownership, such as an external drive.
ATTACH_PLIST="${WORK_DIR}/attach.plist"
hdiutil attach -plist -readonly -nobrowse -noautoopen "${DMG}" >"${ATTACH_PLIST}" 2>/dev/null \
  || fail "disk image could not be mounted read-only"
# The first entry is the whole attached disk; ejecting it on exit also covers
# an image that attached without a mount point.
ATTACHED_DEVICE="$(plutil -extract system-entities.0.dev-entry raw -o - "${ATTACH_PLIST}" 2>/dev/null || true)"
[[ "${ATTACHED_DEVICE}" == /dev/disk* ]] || { ATTACHED_DEVICE=""; fail "the attached disk image reported no device"; }
for entity_index in 0 1 2 3 4 5 6 7; do
  MOUNT_POINT="$(plutil -extract "system-entities.${entity_index}.mount-point" raw -o - "${ATTACH_PLIST}" 2>/dev/null || true)"
  [[ -z "${MOUNT_POINT}" ]] || break
done
[[ -n "${MOUNT_POINT}" && -d "${MOUNT_POINT}" ]] || fail "the mounted disk image has no mount point"

# macOS adds its own bookkeeping folder to an image built from a folder.
# Anything else beside the app and the shortcut is refused.
while IFS= read -r entry; do
  case "${entry}" in
    "${APP_NAME}"|Applications|.fseventsd) ;;
    *) fail "disk image contains an unexpected entry" ;;
  esac
done < <(ls -A "${MOUNT_POINT}")

MOUNTED_APP="${MOUNT_POINT}/${APP_NAME}"
[[ -d "${MOUNTED_APP}" && ! -L "${MOUNTED_APP}" ]] || fail "disk image does not hold a regular app bundle"
[[ -L "${MOUNT_POINT}/Applications" && "$(readlink "${MOUNT_POINT}/Applications")" == "/Applications" ]] \
  || fail "disk image does not hold a shortcut to /Applications"
if find "${MOUNTED_APP}" -type l -print -quit | grep -q .; then
  fail "the app in the disk image contains a symlink"
fi
diff -r "${APP_PATH}" "${MOUNTED_APP}" >/dev/null 2>&1 \
  || fail "the app in the disk image differs from the verified app"

if [[ "${REQUIRE_NOTARIZED}" == "true" ]]; then
  DMG_SIGNATURE_DETAILS="$(codesign -dvvv "${DMG}" 2>&1)" \
    || fail "disk image signature metadata could not be read"
  APP_SIGNATURE_DETAILS="$(codesign -dvvv "${APP_PATH}" 2>&1)" \
    || fail "app signature metadata could not be read"
  printf '%s\n' "${DMG_SIGNATURE_DETAILS}" | grep -q '^Authority=Developer ID Application:' \
    || fail "disk image is not Developer ID Application signed"
  printf '%s\n' "${DMG_SIGNATURE_DETAILS}" | grep -q '^Timestamp=' \
    || fail "secure signing timestamp is missing from the disk image"
  APP_TEAM_ID="$(printf '%s\n' "${APP_SIGNATURE_DETAILS}" | awk -F= '/^TeamIdentifier=/{ print $2; exit }')"
  DMG_TEAM_ID="$(printf '%s\n' "${DMG_SIGNATURE_DETAILS}" | awk -F= '/^TeamIdentifier=/{ print $2; exit }')"
  [[ "${APP_TEAM_ID}" =~ ^[A-Z0-9]{10}$ && "${APP_TEAM_ID}" == "${DMG_TEAM_ID}" ]] \
    || fail "disk image and app Team Identifiers do not match"
  unset APP_SIGNATURE_DETAILS DMG_SIGNATURE_DETAILS APP_TEAM_ID DMG_TEAM_ID
  codesign --verify --strict --verbose=2 "${DMG}" >/dev/null 2>&1 \
    || fail "disk image signature did not pass strict verification"
  # Byte-equal files can still differ in mode bits or attributes.
  codesign --verify --deep --strict "${MOUNTED_APP}" >/dev/null 2>&1 \
    || fail "the app in the disk image did not pass strict signature verification"
  xcrun stapler validate "${DMG}" >/dev/null 2>&1 \
    || fail "stapled notarization ticket is missing or invalid on the disk image"
  spctl --assess --type open --context context:primary-signature --verbose=4 "${DMG}" >/dev/null 2>&1 \
    || fail "Gatekeeper assessment of the disk image failed"
  printf 'Verified notarized LabTether macOS disk image.\n'
else
  printf 'Verified LabTether macOS disk image contents. Signing and notarization were not checked.\n'
fi
