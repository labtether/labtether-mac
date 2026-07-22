#!/usr/bin/env bash
set -Eeuo pipefail

APP_PATH="${1:-}"
shift || true
ARCHITECTURES=""
AGENT_VERSION=""
REQUIRE_SIGNATURE=false

usage() {
  echo "Usage: scripts/validate-app.sh <LabTether Agent.app> [--architectures arm64,x86_64] [--agent-version VERSION] [--require-signature]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --architectures)
      ARCHITECTURES="${2:?--architectures requires a value}"
      shift 2
      ;;
    --agent-version)
      AGENT_VERSION="${2:?--agent-version requires a value}"
      shift 2
      ;;
    --require-signature)
      REQUIRE_SIGNATURE=true
      shift
      ;;
    *)
      echo "unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "${APP_PATH}" || ! -d "${APP_PATH}" ]]; then
  usage
  exit 2
fi

INFO_PLIST="${APP_PATH}/Contents/Info.plist"
HOST_BINARY="${APP_PATH}/Contents/MacOS/LabTetherAgent"
CHILD_BINARY="${APP_PATH}/Contents/Resources/labtether-agent"
RESOURCE_BUNDLE="${APP_PATH}/Contents/Resources/LabTetherAgent_LabTetherAgent.bundle"
APP_ICON="${APP_PATH}/Contents/Resources/AppIcon.icns"

plutil -lint "${INFO_PLIST}" >/dev/null
[[ "$(plutil -extract CFBundleIdentifier raw "${INFO_PLIST}")" == "com.labtether.agent" ]] || {
  echo "unexpected CFBundleIdentifier" >&2
  exit 1
}
[[ "$(plutil -extract CFBundleExecutable raw "${INFO_PLIST}")" == "LabTetherAgent" ]] || {
  echo "unexpected CFBundleExecutable" >&2
  exit 1
}
[[ -x "${HOST_BINARY}" ]] || { echo "missing executable Swift host" >&2; exit 1; }
[[ -x "${CHILD_BINARY}" ]] || { echo "missing executable Go child agent" >&2; exit 1; }
[[ -d "${RESOURCE_BUNDLE}" ]] || { echo "missing SwiftPM resource bundle" >&2; exit 1; }
[[ -f "${APP_ICON}" ]] || { echo "missing application icon" >&2; exit 1; }

help_output="$("${CHILD_BINARY}" help 2>&1)"
[[ "${help_output}" == labtether-agent* ]] || {
  echo "bundled child agent did not return LabTether help" >&2
  exit 1
}
if [[ -n "${AGENT_VERSION}" ]]; then
  first_help_line="${help_output%%$'\n'*}"
  [[ "${first_help_line}" == "labtether-agent ${AGENT_VERSION}" ]] || {
    echo "bundled child version mismatch: expected ${AGENT_VERSION}, got ${first_help_line}" >&2
    exit 1
  }
fi

if [[ -n "${ARCHITECTURES}" ]]; then
  IFS=',' read -r -a expected_arches <<< "${ARCHITECTURES}"
  for arch in "${expected_arches[@]}"; do
    lipo "${HOST_BINARY}" -verify_arch "${arch}"
    lipo "${CHILD_BINARY}" -verify_arch "${arch}"
  done
fi

if [[ "${REQUIRE_SIGNATURE}" == "true" ]]; then
  codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
fi

printf 'Validated %s\n' "${APP_PATH}"
