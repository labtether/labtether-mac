#!/usr/bin/env bash

set +x
set -Eeuo pipefail

# Signs, notarizes and checks the unsigned app from prepare-unsigned-release.sh
# on a GitHub-hosted Mac. Runs only in the sign job of
# .github/workflows/signed-release.yml, which passes these secrets from the
# mac-release-signing environment:
#   MAC_SIGNING_P12_BASE64    Developer ID Application identity (.p12), base64
#   MAC_SIGNING_P12_PASSWORD  its export password
#   MAC_NOTARY_KEY            App Store Connect API key (.p8 text)
#   MAC_NOTARY_KEY_ID         that key's ID
#   MAC_NOTARY_ISSUER_ID      its issuer ID
# The identity goes into a temporary keychain that is deleted on every exit,
# and it must belong to the Watari Labs team in release-signing.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
# shellcheck source=scripts/release-signing.sh
source "${SCRIPT_DIR}/release-signing.sh"

# Apple's public Developer ID intermediates, pinned by SHA-256 of the DER file.
# The current identity chains to the first; renewed identities chain to G2.
APPLE_INTERMEDIATES=(
  "DeveloperIDCA.cer 7afc9d01a62f03a2de9637936d4afe68090d2de18d03f29c88cfb0b1ba63587f"
  "DeveloperIDG2CA.cer f16cd3c54c7f83cea4bf1a3e6a0819c8aaa8e4a1528fd144715f350643d2df3a"
)

TAG=""
UNSIGNED_INPUT=""
AGENT_REPO_INPUT=""
OUTPUT_DIR_INPUT=""
CONFIRM_SIGN=""
UNTAGGED_PROOF=false
TEMP_ROOT=""
KEYCHAIN=""
OUTPUT_DIR=""
RELEASE_COMPLETE=false
ORIGINAL_KEYCHAINS=()
SIGNING_IDENTITY=""
CODESIGN_KEYCHAIN_ARGS=()
NOTARY_AUTH_ARGS=()

cleanup() {
  unset MAC_SIGNING_P12_BASE64 MAC_SIGNING_P12_PASSWORD MAC_NOTARY_KEY MAC_NOTARY_KEY_ID MAC_NOTARY_ISSUER_ID
  if [[ -n "${KEYCHAIN}" ]]; then
    if [[ ${#ORIGINAL_KEYCHAINS[@]} -gt 0 ]]; then
      security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" >/dev/null 2>&1 || true
    fi
    security delete-keychain "${KEYCHAIN}" >/dev/null 2>&1 || true
  fi
  if [[ "${RELEASE_COMPLETE}" != "true" && -n "${OUTPUT_DIR}" && -d "${OUTPUT_DIR}" ]]; then
    remove_placed_release_assets "${OUTPUT_DIR}"
  fi
  if [[ -n "${TEMP_ROOT}" && -d "${TEMP_ROOT}" && ! -L "${TEMP_ROOT}" ]]; then
    chmod -R u+w "${TEMP_ROOT}" >/dev/null 2>&1 || true
    rm -rf -- "${TEMP_ROOT}"
  fi
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

fail() {
  printf 'macOS release signing failed: %s\n' "$1" >&2
  exit 1
}

usage() {
  printf '%s\n' \
    'Usage: scripts/sign-release-ci.sh --tag vX.Y.Z --unsigned-app PATH' \
    '       --agent-repo PATH --output-dir PATH --confirm-sign vX.Y.Z [--untagged-proof]' >&2
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) TAG="${2:?--tag requires a value}"; shift 2 ;;
    --unsigned-app) UNSIGNED_INPUT="${2:?--unsigned-app requires a value}"; shift 2 ;;
    --agent-repo) AGENT_REPO_INPUT="${2:?--agent-repo requires a value}"; shift 2 ;;
    --output-dir) OUTPUT_DIR_INPUT="${2:?--output-dir requires a value}"; shift 2 ;;
    --confirm-sign) CONFIRM_SIGN="${2:?--confirm-sign requires a value}"; shift 2 ;;
    --untagged-proof) UNTAGGED_PROOF=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

[[ "${GITHUB_ACTIONS:-}" == "true" ]] || fail "this script runs only in GitHub Actions; use release-local.sh on a Mac"
[[ "${TAG}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "tag must be vX.Y.Z"
[[ "${CONFIRM_SIGN}" == "${TAG}" ]] || fail "--confirm-sign must exactly match the release tag"
[[ -n "${UNSIGNED_INPUT}" && -f "${UNSIGNED_INPUT}" && ! -L "${UNSIGNED_INPUT}" ]] \
  || fail "the unsigned app archive must be a regular file"
[[ -n "${AGENT_REPO_INPUT}" && -d "${AGENT_REPO_INPUT}" && ! -L "${AGENT_REPO_INPUT}" ]] \
  || fail "agent repository must be a non-symlink directory"
[[ -n "${OUTPUT_DIR_INPUT}" && -d "${OUTPUT_DIR_INPUT}" && ! -L "${OUTPUT_DIR_INPUT}" ]] \
  || fail "output directory must be an existing non-symlink directory"
AGENT_REPO="$(cd "${AGENT_REPO_INPUT}" && pwd -P)"
OUTPUT_DIR="$(cd "${OUTPUT_DIR_INPUT}" && pwd -P)"
if find "${OUTPUT_DIR}" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
  fail "output directory must be empty"
fi
for name in MAC_SIGNING_P12_BASE64 MAC_SIGNING_P12_PASSWORD MAC_NOTARY_KEY MAC_NOTARY_KEY_ID MAC_NOTARY_ISSUER_ID; do
  [[ -n "${!name:-}" ]] || fail "${name} is not set in the mac-release-signing environment"
done
[[ "${MAC_NOTARY_KEY_ID}" =~ ^[A-Z0-9]{10}$ ]] || fail "MAC_NOTARY_KEY_ID is not a 10-character key ID"
[[ "${MAC_NOTARY_ISSUER_ID}" =~ ^[0-9a-fA-F-]{36}$ ]] || fail "MAC_NOTARY_ISSUER_ID is not an issuer ID"

repo_is_clean "${REPO_ROOT}" || fail "wrapper repository must be clean"
repo_is_clean "${AGENT_REPO}" || fail "agent repository must be clean"
if [[ "${UNTAGGED_PROOF}" != "true" ]]; then
  repo_tagged_head "${REPO_ROOT}" || fail "wrapper HEAD must exactly match the release tag"
  repo_tagged_head "${AGENT_REPO}" || fail "agent HEAD must exactly match the release tag"
fi
WRAPPER_COMMIT="$(git -C "${REPO_ROOT}" rev-parse HEAD)"
AGENT_COMMIT="$(git -C "${AGENT_REPO}" rev-parse HEAD)"

TEMP_BASE="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
TEMP_ROOT="$(mktemp -d "${TEMP_BASE%/}/labtether-mac-sign.XXXXXX")"
chmod 700 "${TEMP_ROOT}"
STAGE_DIR="${TEMP_ROOT}/stage"
NOTARY_DIR="${TEMP_ROOT}/notary"
ASSET_DIR="${TEMP_ROOT}/assets"
mkdir -m 700 "${STAGE_DIR}" "${NOTARY_DIR}" "${ASSET_DIR}" "${TEMP_ROOT}/list" "${TEMP_ROOT}/ca"

check_app_archive_entries "${UNSIGNED_INPUT}" "${TEMP_ROOT}/list"
extract_app_archive "${UNSIGNED_INPUT}" "${STAGE_DIR}"
check_app_release_record "${STAGE_DIR}/LabTether Agent.app" "${TAG}" "${WRAPPER_COMMIT}" "${AGENT_COMMIT}"

# Temporary keychain with a random password, first in the user search list.
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line#\"}"
  line="${line%\"}"
  [[ -n "${line}" ]] && ORIGINAL_KEYCHAINS+=("${line}")
done < <(security list-keychains -d user)
KEYCHAIN="${TEMP_ROOT}/signing.keychain-db"
keychain_password="$(openssl rand -hex 32)"
security create-keychain -p "${keychain_password}" "${KEYCHAIN}" >/dev/null || fail "creating the temporary keychain failed"
security set-keychain-settings "${KEYCHAIN}" || fail "configuring the temporary keychain failed"
security unlock-keychain -p "${keychain_password}" "${KEYCHAIN}" || fail "unlocking the temporary keychain failed"
security list-keychains -d user -s "${KEYCHAIN}" ${ORIGINAL_KEYCHAINS[@]+"${ORIGINAL_KEYCHAINS[@]}"} \
  || fail "adding the temporary keychain to the search list failed"

for entry in "${APPLE_INTERMEDIATES[@]}"; do
  ca_name="${entry%% *}"
  ca_hash="${entry##* }"
  curl -fsSL --retry 3 --proto '=https' -o "${TEMP_ROOT}/ca/${ca_name}" \
    "https://www.apple.com/certificateauthority/${ca_name}" || fail "downloading ${ca_name} from Apple failed"
  [[ "$(shasum -a 256 "${TEMP_ROOT}/ca/${ca_name}" | awk '{ print $1 }')" == "${ca_hash}" ]] \
    || fail "${ca_name} from Apple does not match its pinned SHA-256"
  security import "${TEMP_ROOT}/ca/${ca_name}" -k "${KEYCHAIN}" >/dev/null || fail "importing ${ca_name} failed"
done

p12_path="${TEMP_ROOT}/identity.p12"
(umask 077 && printf '%s' "${MAC_SIGNING_P12_BASE64}" | tr -d '\r\n ' | base64 --decode >"${p12_path}") \
  || fail "MAC_SIGNING_P12_BASE64 is not valid base64"
security import "${p12_path}" -k "${KEYCHAIN}" -f pkcs12 -P "${MAC_SIGNING_P12_PASSWORD}" \
  -T /usr/bin/codesign >/dev/null 2>&1 || fail "importing the signing identity failed; check the .p12 and its password"
rm -f -- "${p12_path}"
unset MAC_SIGNING_P12_BASE64 MAC_SIGNING_P12_PASSWORD
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "${keychain_password}" "${KEYCHAIN}" >/dev/null 2>&1 \
  || fail "allowing codesign to use the signing key failed"
unset keychain_password

identities="$(security find-identity -v -p codesigning "${KEYCHAIN}" | awk '/^[[:space:]]*[0-9]+\)/')"
[[ "$(printf '%s\n' "${identities}" | grep -c .)" == "1" ]] \
  || fail "the .p12 must hold exactly one valid code signing identity"
identity_hash="$(printf '%s\n' "${identities}" | awk '{ print $2 }')"
identity_name="$(printf '%s\n' "${identities}" | sed -E 's/^[^"]*"(.*)"[^"]*$/\1/')"
[[ "${identity_hash}" =~ ^[0-9A-F]{40}$ ]] || fail "the signing identity hash could not be read"
[[ "${identity_name}" == "Developer ID Application: "*" (${RELEASE_TEAM_ID})" ]] \
  || fail "the signing identity is not a Developer ID Application identity of team ${RELEASE_TEAM_ID}"
printf 'Signing as %s.\n' "${identity_name}"
SIGNING_IDENTITY="${identity_hash}"
CODESIGN_KEYCHAIN_ARGS=(--keychain "${KEYCHAIN}")

notary_key_path="${TEMP_ROOT}/notary-key.p8"
(umask 077 && printf '%s\n' "${MAC_NOTARY_KEY}" >"${notary_key_path}")
NOTARY_AUTH_ARGS=(--key "${notary_key_path}" --key-id "${MAC_NOTARY_KEY_ID}" --issuer "${MAC_NOTARY_ISSUER_ID}")
unset MAC_NOTARY_KEY

sign_and_package_release
rm -f -- "${notary_key_path}"
NOTARY_AUTH_ARGS=()

"${SCRIPT_DIR}/verify-release-archive.sh" \
  --archive "${ASSET_DIR}/${ARCHIVE_NAME}" \
  --checksum "${ASSET_DIR}/${CHECKSUM_NAME}" \
  --dmg "${ASSET_DIR}/${DMG_NAME}" \
  --dmg-checksum "${ASSET_DIR}/${DMG_CHECKSUM_NAME}" \
  --tag "${TAG}" \
  --wrapper-commit "${WRAPPER_COMMIT}" \
  --agent-commit "${AGENT_COMMIT}"

place_release_assets "${ASSET_DIR}" "${OUTPUT_DIR}"
RELEASE_COMPLETE=true
printf 'Signed, notarized and checked the four macOS release assets for %s. Nothing was published.\n' "${TAG}"
