#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"

TAG=""
AGENT_REPO_INPUT=""
RELEASE_DIR_INPUT=""
REPOSITORY="labtether/labtether-mac"
CONFIRM_PUBLISH=""
DRY_RUN=false

DRAFT_MAY_EXIST=false
PUBLISH_COMPLETE=false
ARCHIVE_NAME="labtether-agent-macos-universal.tar.gz"
CHECKSUM_NAME="${ARCHIVE_NAME}.sha256"

cleanup() {
  if [[ "${DRAFT_MAY_EXIST}" == "true" && "${PUBLISH_COMPLETE}" != "true" ]]; then
    printf 'Publication stopped before completion; an unpublished draft may require manual inspection.\n' >&2
  fi
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

fail() {
  printf 'local release publication failed: %s\n' "$1" >&2
  exit 1
}

usage() {
  printf '%s\n' \
    'Usage: scripts/publish-local-release.sh --tag vX.Y.Z --agent-repo PATH' \
    '       --release-dir PATH --confirm-publish vX.Y.Z' \
    '       [--repository OWNER/REPO] [--dry-run]' >&2
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

remote_tag_commit() {
  local repository="$1"
  local remote_output
  local direct_commit
  local peeled_commit
  remote_output="$(
    git ls-remote --tags "https://github.com/${repository}.git" \
      "refs/tags/${TAG}" "refs/tags/${TAG}^{}" 2>/dev/null
  )" || return 1
  direct_commit="$(printf '%s\n' "${remote_output}" | awk -v ref="refs/tags/${TAG}" '$2 == ref { print $1 }')"
  peeled_commit="$(printf '%s\n' "${remote_output}" | awk -v ref="refs/tags/${TAG}^{}" '$2 == ref { print $1 }')"
  if [[ "${peeled_commit}" =~ ^[0-9a-f]{40}$ ]]; then
    printf '%s\n' "${peeled_commit}"
  elif [[ "${direct_commit}" =~ ^[0-9a-f]{40}$ ]]; then
    printf '%s\n' "${direct_commit}"
  else
    return 1
  fi
}

release_summary() {
  gh release view "${TAG}" \
    --repo "${REPOSITORY}" \
    --json isDraft,assets \
    --jq '[.isDraft, (.assets | length), ([.assets[].name] | sort | join(","))] | @tsv' \
    2>/dev/null
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) TAG="${2:?--tag requires a value}"; shift 2 ;;
    --agent-repo) AGENT_REPO_INPUT="${2:?--agent-repo requires a value}"; shift 2 ;;
    --release-dir) RELEASE_DIR_INPUT="${2:?--release-dir requires a value}"; shift 2 ;;
    --repository) REPOSITORY="${2:?--repository requires a value}"; shift 2 ;;
    --confirm-publish) CONFIRM_PUBLISH="${2:?--confirm-publish requires a value}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

[[ "${TAG}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "tag must be vX.Y.Z"
[[ "${REPOSITORY}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail "repository must be OWNER/REPO"
[[ -n "${AGENT_REPO_INPUT}" && -d "${AGENT_REPO_INPUT}" && ! -L "${AGENT_REPO_INPUT}" ]] \
  || fail "agent repository must be a non-symlink directory"
[[ -n "${RELEASE_DIR_INPUT}" && -d "${RELEASE_DIR_INPUT}" && ! -L "${RELEASE_DIR_INPUT}" ]] \
  || fail "release directory must be a non-symlink directory"

AGENT_REPO="$(cd "${AGENT_REPO_INPUT}" && pwd -P)"
RELEASE_DIR="$(cd "${RELEASE_DIR_INPUT}" && pwd -P)"
[[ "$(git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]] \
  || fail "wrapper source is not a Git worktree"
[[ "$(git -C "${AGENT_REPO}" rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]] \
  || fail "agent source is not a Git worktree"
if path_is_within "${RELEASE_DIR}" "${REPO_ROOT}" || path_is_within "${RELEASE_DIR}" "${AGENT_REPO}"; then
  fail "release directory must be outside both source repositories"
fi
[[ -r "${RELEASE_DIR}" && -x "${RELEASE_DIR}" ]] || fail "release directory must be readable"

shopt -s nullglob dotglob
release_entries=("${RELEASE_DIR}"/*)
shopt -u nullglob dotglob
[[ ${#release_entries[@]} -eq 2 ]] || fail "release directory must contain exactly two entries"

ARCHIVE_PATH="${RELEASE_DIR}/${ARCHIVE_NAME}"
CHECKSUM_PATH="${RELEASE_DIR}/${CHECKSUM_NAME}"
[[ -f "${ARCHIVE_PATH}" && ! -L "${ARCHIVE_PATH}" ]] || fail "release archive must be a non-symlink regular file"
[[ -f "${CHECKSUM_PATH}" && ! -L "${CHECKSUM_PATH}" ]] || fail "release checksum must be a non-symlink regular file"
for release_entry in "${release_entries[@]}"; do
  case "$(basename "${release_entry}")" in
    "${ARCHIVE_NAME}"|"${CHECKSUM_NAME}") ;;
    *) fail "release directory contains an unexpected entry" ;;
  esac
done

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
  printf 'Dry run passed local tag, source, and two-file release-directory checks for %s; no network or publication action was taken.\n' "${TAG}"
  exit 0
fi

[[ "${CONFIRM_PUBLISH}" == "${TAG}" ]] \
  || fail "--confirm-publish must exactly match the release tag"
for command_name in gh git; do
  command -v "${command_name}" >/dev/null 2>&1 || fail "a required local publication command is unavailable"
done

TEMP_BASE="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
if path_is_within "${TEMP_BASE}" "${REPO_ROOT}" || path_is_within "${TEMP_BASE}" "${AGENT_REPO}"; then
  fail "the temporary directory must be outside both source repositories"
fi

TMPDIR="${TEMP_BASE}" "${SCRIPT_DIR}/verify-release-archive.sh" \
  --archive "${ARCHIVE_PATH}" \
  --checksum "${CHECKSUM_PATH}" \
  --tag "${TAG}" \
  --wrapper-commit "${WRAPPER_COMMIT}" \
  --agent-commit "${AGENT_COMMIT}"

if ! gh auth status --hostname github.com >/dev/null 2>&1; then
  fail "the local GitHub CLI is not authenticated"
fi
remote_wrapper_commit="$(remote_tag_commit "${REPOSITORY}")" \
  || fail "the requested wrapper tag is not available from the publication repository"
remote_agent_commit="$(remote_tag_commit "labtether/labtether-agent")" \
  || fail "the requested agent tag is not available from the agent repository"
[[ "${remote_wrapper_commit}" == "${WRAPPER_COMMIT}" ]] \
  || fail "the remote wrapper tag does not match the verified local commit"
[[ "${remote_agent_commit}" == "${AGENT_COMMIT}" ]] \
  || fail "the remote agent tag does not match the verified local commit"

if gh release view "${TAG}" --repo "${REPOSITORY}" >/dev/null 2>&1; then
  fail "a release already exists for the requested tag"
fi
if ! gh api "repos/${REPOSITORY}" >/dev/null 2>&1; then
  fail "the publication repository could not be verified"
fi

DRAFT_MAY_EXIST=true
if ! gh release create "${TAG}" \
  "${ARCHIVE_PATH}" \
  "${CHECKSUM_PATH}" \
  --repo "${REPOSITORY}" \
  --draft \
  --verify-tag \
  --title "LabTether Mac Agent ${TAG#v}" \
  --notes 'Signed and notarized universal macOS agent. Verify the companion SHA-256 file before installation.' \
  >/dev/null 2>&1; then
  fail "creating the two-asset draft release failed"
fi

draft_summary="$(release_summary)" || fail "the draft release could not be inspected; it was not published"
IFS=$'\t' read -r draft_flag draft_asset_count draft_asset_names <<<"${draft_summary}"
expected_asset_names="${ARCHIVE_NAME},${CHECKSUM_NAME}"
[[ "${draft_flag}" == "true" ]] || fail "the newly created release is not a draft"
[[ "${draft_asset_count}" == "2" ]] || fail "the draft does not contain exactly two uploaded assets"
[[ "${draft_asset_names}" == "${expected_asset_names}" ]] \
  || fail "the draft asset allowlist does not match the two verified files"

if ! gh release edit "${TAG}" --repo "${REPOSITORY}" --draft=false >/dev/null 2>&1; then
  fail "the verified draft could not be published"
fi
published_summary="$(release_summary)" || fail "the published release could not be inspected"
IFS=$'\t' read -r published_flag published_asset_count published_asset_names <<<"${published_summary}"
[[ "${published_flag}" == "false" ]] || fail "the release still reports draft state"
[[ "${published_asset_count}" == "2" ]] || fail "the published release does not contain exactly two uploaded assets"
[[ "${published_asset_names}" == "${expected_asset_names}" ]] \
  || fail "the published release asset allowlist changed unexpectedly"
PUBLISH_COMPLETE=true

printf 'Published the verified two-asset local macOS release for %s.\n' "${TAG}"
