#!/usr/bin/env bash
set -Eeuo pipefail

# Builds the disk image people download: LabTether Agent.app beside a shortcut
# to /Applications. It copies the app as it is and signs nothing. The release
# script signs and notarizes the image afterwards.

APP_NAME="LabTether Agent.app"
VOLUME_NAME="LabTether Agent"
APP_PATH=""
OUTPUT_PATH=""
WORK_DIR=""

cleanup() {
  if [[ -n "${WORK_DIR}" && -d "${WORK_DIR}" && ! -L "${WORK_DIR}" ]]; then
    rm -rf -- "${WORK_DIR}"
  fi
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

fail() {
  printf 'disk image build failed: %s\n' "$1" >&2
  exit 1
}

usage() {
  printf '%s\n' \
    'Usage: scripts/build-dmg.sh --app "PATH/LabTether Agent.app" --output PATH.dmg' \
    '' \
    'The output file must not exist yet. Its folder must exist.' >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP_PATH="${2:?--app requires a value}"; shift 2 ;;
    --output) OUTPUT_PATH="${2:?--output requires a value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

[[ -n "${APP_PATH}" && -d "${APP_PATH}" && ! -L "${APP_PATH}" ]] \
  || fail "the app must be a non-symlink application bundle"
[[ "$(basename "${APP_PATH}")" == "${APP_NAME}" ]] || fail "the app must be named ${APP_NAME}"
[[ "${OUTPUT_PATH}" == *.dmg ]] || fail "the output path must end in .dmg"
[[ ! -e "${OUTPUT_PATH}" && ! -L "${OUTPUT_PATH}" ]] || fail "the output file already exists"
OUTPUT_DIR="$(cd "$(dirname "${OUTPUT_PATH}")" 2>/dev/null && pwd -P)" \
  || fail "the output folder does not exist"
OUTPUT_PATH="${OUTPUT_DIR}/$(basename "${OUTPUT_PATH}")"
for command_name in ditto hdiutil; do
  command -v "${command_name}" >/dev/null 2>&1 || fail "missing required command: ${command_name}"
done

TEMP_BASE="$(cd "${TMPDIR:-/tmp}" && pwd -P)" || fail "temporary directory is unavailable"
WORK_DIR="$(mktemp -d "${TEMP_BASE%/}/labtether-dmg.XXXXXX")"
chmod 700 "${WORK_DIR}"
STAGE_DIR="${WORK_DIR}/stage"
IMAGE_PATH="${WORK_DIR}/image.dmg"
mkdir "${STAGE_DIR}"
ditto "${APP_PATH}" "${STAGE_DIR}/${APP_NAME}"
ln -s /Applications "${STAGE_DIR}/Applications"

# hdiutil sometimes answers "Resource busy" on a loaded host, so the image is
# tried up to three times. Every other step runs once.
attempt=1
until hdiutil create -quiet \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${STAGE_DIR}" \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  "${IMAGE_PATH}"; do
  (( attempt < 3 )) || fail "hdiutil could not create the disk image"
  attempt=$((attempt + 1))
  rm -f -- "${IMAGE_PATH}"
  sleep 2
done
hdiutil verify -quiet "${IMAGE_PATH}" || fail "the new disk image did not pass hdiutil verify"

mv -n -- "${IMAGE_PATH}" "${OUTPUT_PATH}"
[[ ! -e "${IMAGE_PATH}" && -f "${OUTPUT_PATH}" && ! -L "${OUTPUT_PATH}" ]] \
  || fail "the disk image could not be placed without overwriting"
chmod 0644 "${OUTPUT_PATH}"
printf 'Built %s\n' "${OUTPUT_PATH}"
