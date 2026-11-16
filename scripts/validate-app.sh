#!/usr/bin/env bash
set -Eeuo pipefail

APP_PATH="${1:-}"
shift || true
ARCHITECTURES=""
AGENT_VERSION=""
REQUIRE_SIGNATURE=false
RUN_CHILD=true
EDITION="developer-id"
STORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/packaging/app-store"

usage() {
  echo "Usage: scripts/validate-app.sh <LabTether Agent.app> [--edition developer-id|store] [--architectures arm64,x86_64] [--agent-version VERSION] [--require-signature] [--no-run]" >&2
  echo "--no-run checks the files without starting the bundled agent; use it wherever a secret is present." >&2
  echo "--edition store: the Mac App Store edition (agent in Contents/MacOS, sandbox entitlements)." >&2
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
    --no-run)
      RUN_CHILD=false
      shift
      ;;
    --edition)
      EDITION="${2:?--edition requires a value}"
      shift 2
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
case "${EDITION}" in
  developer-id) ;;
  store) CHILD_BINARY="${APP_PATH}/Contents/MacOS/labtether-agent" ;;
  *) usage; exit 2 ;;
esac
RESOURCE_BUNDLE="${APP_PATH}/Contents/Resources/LabTetherAgent_LabTetherAgent.bundle"
APP_ICON="${APP_PATH}/Contents/Resources/AppIcon.icns"

plutil -lint "${INFO_PLIST}" >/dev/null
BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw "${INFO_PLIST}")"
if [[ "${EDITION}" == store ]]; then
  # A QA copy may carry its own identifier under com.labtether.agent.
  [[ "${BUNDLE_ID}" == "com.labtether.agent" || "${BUNDLE_ID}" == com.labtether.agent.* ]] || {
    echo "unexpected CFBundleIdentifier" >&2
    exit 1
  }
  [[ -n "$(plutil -extract LSApplicationCategoryType raw "${INFO_PLIST}" 2>/dev/null)" ]] || {
    echo "missing LSApplicationCategoryType" >&2
    exit 1
  }
  [[ ! -e "${APP_PATH}/Contents/Resources/labtether-agent" ]] || {
    echo "the Store edition must not carry an agent in Contents/Resources" >&2
    exit 1
  }
elif [[ "${BUNDLE_ID}" != "com.labtether.agent" ]]; then
  echo "unexpected CFBundleIdentifier" >&2
  exit 1
fi
[[ "$(plutil -extract CFBundleExecutable raw "${INFO_PLIST}")" == "LabTetherAgent" ]] || {
  echo "unexpected CFBundleExecutable" >&2
  exit 1
}
[[ -n "$(plutil -extract NSLocalNetworkUsageDescription raw "${INFO_PLIST}" 2>/dev/null)" ]] || {
  echo "missing NSLocalNetworkUsageDescription" >&2
  exit 1
}
[[ -x "${HOST_BINARY}" ]] || { echo "missing executable Swift host" >&2; exit 1; }
[[ -x "${CHILD_BINARY}" ]] || { echo "missing executable child agent" >&2; exit 1; }
[[ -d "${RESOURCE_BUNDLE}" ]] || { echo "missing SwiftPM resource bundle" >&2; exit 1; }
[[ -f "${APP_ICON}" ]] || { echo "missing application icon" >&2; exit 1; }

# A sandboxed helper signed with com.apple.security.inherit stops at once
# when no sandboxed app started it, so the Store edition's agent is not run
# here; build-app.sh checks its version before signing.
if [[ "${RUN_CHILD}" == "true" && "${EDITION}" != store ]]; then
  # An empty environment, so the child never sees a caller's token or key.
  help_output="$(env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin "${CHILD_BINARY}" help 2>&1)"
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

# The Store edition's entitlements are exactly the files in packaging/app-store.
if [[ "${REQUIRE_SIGNATURE}" == "true" && "${EDITION}" == store ]]; then
  check_entitlements() { # signed-path expected-file
    local signed expected
    signed="$(codesign -d --entitlements - --xml "$1" 2>/dev/null | plutil -convert xml1 -o - -)"
    expected="$(plutil -convert xml1 -o - "$2")"
    [[ "${signed}" == "${expected}" ]] || {
      echo "entitlements of $1 differ from $2" >&2
      exit 1
    }
  }
  check_entitlements "${APP_PATH}" "${STORE_DIR}/LabTetherAgent.entitlements"
  check_entitlements "${CHILD_BINARY}" "${STORE_DIR}/labtether-agent.entitlements"
fi

printf 'Validated %s\n' "${APP_PATH}"
