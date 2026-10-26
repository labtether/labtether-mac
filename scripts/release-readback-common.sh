#!/usr/bin/env bash

set -Eeuo pipefail

# GitHub's releases/tags/{tag} endpoint returns only published releases, so a
# draft can only be found by listing every release (drafts are listed for
# users with push access). Prints a JSON array of releases with the exact tag.
github_releases_with_tag() {
  local repository="$1"
  local tag="$2"
  local pages
  pages="$(gh api --paginate --slurp "repos/${repository}/releases?per_page=100")" || return 1
  jq -c --arg tag "${tag}" \
    'if type == "array" and all(.[]; type == "array")
     then [.[][] | select(.tag_name == $tag)]
     else error("unexpected GitHub release list response") end' \
    <<<"${pages}"
}

# Prints the one release object for the tag, draft or published. Fails when
# the tag has no release or more than one (for example a duplicate draft).
github_release_by_tag() {
  local repository="$1"
  local tag="$2"
  local matches
  local match_count
  matches="$(github_releases_with_tag "${repository}" "${tag}")" || return 1
  match_count="$(jq -r 'length' <<<"${matches}")" || return 1
  if [[ "${match_count}" != "1" ]]; then
    printf 'expected exactly one GitHub release for %s, found %s\n' "${tag}" "${match_count}" >&2
    return 1
  fi
  jq -c '.[0]' <<<"${matches}"
}

validate_github_release_asset_readback() {
  local release_json="$1"
  local expected_draft="$2"
  local archive_hash="$3"
  local checksum_hash="$4"
  local archive_size="$5"
  local checksum_size="$6"
  jq -e \
    --arg tag "${TAG}" \
    --arg archive "${ARCHIVE_NAME}" \
    --arg checksum "${CHECKSUM_NAME}" \
    --arg archive_digest "sha256:${archive_hash}" \
    --arg checksum_digest "sha256:${checksum_hash}" \
    --argjson expected_draft "${expected_draft}" \
    --argjson archive_size "${archive_size}" \
    --argjson checksum_size "${checksum_size}" \
    '.draft == $expected_draft and
     .tag_name == $tag and
     (.assets | length) == 2 and
     ([.assets[].name] | sort) == ([$archive, $checksum] | sort) and
     any(.assets[]; .name == $archive and .state == "uploaded" and .size == $archive_size and .digest == $archive_digest) and
     any(.assets[]; .name == $checksum and .state == "uploaded" and .size == $checksum_size and .digest == $checksum_digest)' \
    <<<"${release_json}" >/dev/null
}
