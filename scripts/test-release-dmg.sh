#!/usr/bin/env bash
set -Eeuo pipefail

# Builds a disk image from a small stand-in app and checks that the release
# disk image check accepts it, and refuses one whose app differs from the
# verified app or whose checksum is wrong. Signs nothing.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
DMG_NAME="labtether-agent-macos-universal.dmg"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/labtether-dmg-check.XXXXXX")"
trap 'rm -rf -- "${WORK_DIR}"' EXIT

fail() {
  printf 'release disk image check failed: %s\n' "$1" >&2
  exit 1
}

app="${WORK_DIR}/app/LabTether Agent.app"
mkdir -p "${app}/Contents/MacOS" "${WORK_DIR}/out"
printf 'stand-in host\n' >"${app}/Contents/MacOS/LabTetherAgent"
dmg="${WORK_DIR}/out/${DMG_NAME}"
"${SCRIPT_DIR}/build-dmg.sh" --app "${app}" --output "${dmg}" >/dev/null \
  || fail "the disk image could not be built"
if "${SCRIPT_DIR}/build-dmg.sh" --app "${app}" --output "${dmg}" >/dev/null 2>&1; then
  fail "the builder overwrote an existing disk image"
fi
(cd "${WORK_DIR}/out" && shasum -a 256 "${DMG_NAME}" >"${DMG_NAME}.sha256")
"${SCRIPT_DIR}/verify-release-dmg.sh" --dmg "${dmg}" --checksum "${dmg}.sha256" --app "${app}" >/dev/null \
  || fail "the disk image check refused a matching image"
# The refusal must come from the image's own signature check, not from an
# earlier step, so the message is checked too.
if notarized_output="$("${SCRIPT_DIR}/verify-release-dmg.sh" --dmg "${dmg}" --checksum "${dmg}.sha256" \
  --app "${app}" --require-notarized 2>&1)"; then
  fail "the disk image check accepted an unsigned image as notarized"
fi
[[ "${notarized_output}" == *"disk image signature metadata could not be read"* ]] \
  || fail "the unsigned image was refused before its own signature check"
if hdiutil info | grep -Fq "${dmg}"; then
  fail "the disk image check left the image attached"
fi

printf 'changed host\n' >"${app}/Contents/MacOS/LabTetherAgent"
if "${SCRIPT_DIR}/verify-release-dmg.sh" --dmg "${dmg}" --checksum "${dmg}.sha256" --app "${app}" >/dev/null 2>&1; then
  fail "the disk image check accepted an app that differs from the verified app"
fi
printf 'stand-in host\n' >"${app}/Contents/MacOS/LabTetherAgent"
printf '%064d  %s\n' 0 "${DMG_NAME}" >"${dmg}.sha256"
if "${SCRIPT_DIR}/verify-release-dmg.sh" --dmg "${dmg}" --checksum "${dmg}.sha256" --app "${app}" >/dev/null 2>&1; then
  fail "the disk image check accepted a wrong checksum"
fi

printf 'Release disk image check passed.\n'
