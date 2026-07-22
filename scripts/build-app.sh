#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
AGENT_REPO="${LABTETHER_AGENT_REPO:-$(cd "${REPO_ROOT}/.." && pwd)/labtether-agent}"
CONFIGURATION="release"
OUTPUT_DIR="${REPO_ROOT}/build"
ADHOC_SIGN=true
ARCHS=()

usage() {
  cat <<'USAGE'
Usage: scripts/build-app.sh [options]

Build a real LabTether Agent.app containing the Swift menu-bar host, its
SwiftPM resources, and the Go child agent from the sibling labtether-agent repo.

Options:
  --configuration debug|release  Swift build configuration (default: release)
  --arch arm64|x86_64            Target one architecture; may be repeated
  --universal                    Build arm64 + x86_64 universal app
  --output-dir PATH              Parent directory for LabTether Agent.app
  --no-sign                      Skip local ad-hoc signing
  -h, --help                     Show this help

Environment:
  LABTETHER_AGENT_REPO           Path to the labtether-agent checkout
  LABTETHER_AGENT_VERSION        Version embedded in the Go child
  LABTETHER_APP_VERSION          CFBundleShortVersionString override
  LABTETHER_APP_BUILD_NUMBER     CFBundleVersion override
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration)
      CONFIGURATION="${2:?--configuration requires a value}"
      shift 2
      ;;
    --arch)
      ARCHS+=("${2:?--arch requires a value}")
      shift 2
      ;;
    --universal)
      ARCHS=(arm64 x86_64)
      shift
      ;;
    --output-dir)
      OUTPUT_DIR="${2:?--output-dir requires a value}"
      shift 2
      ;;
    --no-sign)
      ADHOC_SIGN=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "${CONFIGURATION}" in
  debug|release) ;;
  *)
    echo "configuration must be debug or release" >&2
    exit 2
    ;;
esac

if [[ ${#ARCHS[@]} -eq 0 ]]; then
  case "$(uname -m)" in
    arm64|x86_64) ARCHS=("$(uname -m)") ;;
    *)
      echo "unsupported host architecture: $(uname -m)" >&2
      exit 1
      ;;
  esac
fi

for arch in "${ARCHS[@]}"; do
  case "${arch}" in
    arm64|x86_64) ;;
    *)
      echo "unsupported architecture: ${arch}" >&2
      exit 2
      ;;
  esac
done

for command_name in go swift plutil ditto codesign; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "missing required command: ${command_name}" >&2
    exit 1
  }
done
if [[ ${#ARCHS[@]} -gt 1 ]]; then
  command -v lipo >/dev/null 2>&1 || {
    echo "missing required command: lipo" >&2
    exit 1
  }
fi

if [[ ! -f "${AGENT_REPO}/go.mod" || ! -d "${AGENT_REPO}/cmd/labtether-agent" ]]; then
  echo "labtether-agent checkout not found at ${AGENT_REPO}" >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"
OUTPUT_DIR="$(cd "${OUTPUT_DIR}" && pwd)"
APP_PATH="${OUTPUT_DIR}/LabTether Agent.app"
TEMP_DIR="${OUTPUT_DIR}/.labtether-app-build"
rm -rf "${APP_PATH}" "${TEMP_DIR}"
mkdir -p "${TEMP_DIR}" "${APP_PATH}/Contents/MacOS" "${APP_PATH}/Contents/Resources"

cleanup() {
  rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

AGENT_VERSION="${LABTETHER_AGENT_VERSION:-$(git -C "${AGENT_REPO}" describe --tags --always --dirty 2>/dev/null || printf dev)}"
APP_VERSION="${LABTETHER_APP_VERSION:-$(plutil -extract CFBundleShortVersionString raw "${REPO_ROOT}/Sources/LabTetherAgent/Resources/Info.plist")}"
APP_BUILD_NUMBER="${LABTETHER_APP_BUILD_NUMBER:-$(plutil -extract CFBundleVersion raw "${REPO_ROOT}/Sources/LabTetherAgent/Resources/Info.plist")}"

SWIFT_ARGS=(build -c "${CONFIGURATION}")
for arch in "${ARCHS[@]}"; do
  SWIFT_ARGS+=(--arch "${arch}")
done
(cd "${REPO_ROOT}" && swift "${SWIFT_ARGS[@]}")
SWIFT_BIN_DIR="$(cd "${REPO_ROOT}" && swift "${SWIFT_ARGS[@]}" --show-bin-path)"
SWIFT_HOST="${SWIFT_BIN_DIR}/LabTetherAgent"
RESOURCE_BUNDLE="${SWIFT_BIN_DIR}/LabTetherAgent_LabTetherAgent.bundle"

if [[ ! -x "${SWIFT_HOST}" ]]; then
  echo "Swift host binary missing: ${SWIFT_HOST}" >&2
  exit 1
fi
if [[ ! -d "${RESOURCE_BUNDLE}" ]]; then
  echo "Swift resource bundle missing: ${RESOURCE_BUNDLE}" >&2
  exit 1
fi

GO_BINARIES=()
for arch in "${ARCHS[@]}"; do
  go_arch="${arch}"
  if [[ "${arch}" == "x86_64" ]]; then
    go_arch="amd64"
  fi
  output="${TEMP_DIR}/labtether-agent-${arch}"
  (
    cd "${AGENT_REPO}"
    CGO_ENABLED=0 GOOS=darwin GOARCH="${go_arch}" \
      go build -trimpath \
      -ldflags="-s -w -X main.version=${AGENT_VERSION}" \
      -o "${output}" ./cmd/labtether-agent
  )
  GO_BINARIES+=("${output}")
done

CHILD_PATH="${APP_PATH}/Contents/Resources/labtether-agent"
if [[ ${#GO_BINARIES[@]} -eq 1 ]]; then
  cp "${GO_BINARIES[0]}" "${CHILD_PATH}"
else
  lipo -create "${GO_BINARIES[@]}" -output "${CHILD_PATH}"
fi

cp "${SWIFT_HOST}" "${APP_PATH}/Contents/MacOS/LabTetherAgent"
ditto "${RESOURCE_BUNDLE}" "${APP_PATH}/Contents/Resources/LabTetherAgent_LabTetherAgent.bundle"
cp "${REPO_ROOT}/Sources/LabTetherAgent/Resources/Info.plist" "${APP_PATH}/Contents/Info.plist"
cp "${REPO_ROOT}/Sources/LabTetherAgent/Resources/AppIcon.icns" "${APP_PATH}/Contents/Resources/AppIcon.icns"
plutil -replace CFBundleShortVersionString -string "${APP_VERSION}" "${APP_PATH}/Contents/Info.plist"
plutil -replace CFBundleVersion -string "${APP_BUILD_NUMBER}" "${APP_PATH}/Contents/Info.plist"
printf 'APPL????' > "${APP_PATH}/Contents/PkgInfo"
chmod 0755 "${APP_PATH}/Contents/MacOS/LabTetherAgent" "${CHILD_PATH}"
xattr -cr "${APP_PATH}"

if [[ "${ADHOC_SIGN}" == "true" ]]; then
  codesign --force --options runtime --sign - "${CHILD_PATH}"
  codesign --force --options runtime --sign - "${APP_PATH}/Contents/MacOS/LabTetherAgent"
  codesign --force --sign - "${APP_PATH}"
fi

ARCH_LIST="$(IFS=,; printf '%s' "${ARCHS[*]}")"
VALIDATE_ARGS=(
  "${APP_PATH}"
  --architectures "${ARCH_LIST}"
  --agent-version "${AGENT_VERSION}"
)
if [[ "${ADHOC_SIGN}" == "true" ]]; then
  VALIDATE_ARGS+=(--require-signature)
fi
"${SCRIPT_DIR}/validate-app.sh" "${VALIDATE_ARGS[@]}"
printf 'Built %s\n' "${APP_PATH}"
