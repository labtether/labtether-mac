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

# Prints the JSON list of {name, size, digest} that GitHub must report for
# the given local release files.
release_asset_expectations() {
  local path
  local size
  local hash
  local entries='[]'
  for path in "$@"; do
    size="$(stat -f '%z' -- "${path}")" || return 1
    hash="$(shasum -a 256 -- "${path}" | awk '{ print tolower($1) }')" || return 1
    [[ "${hash}" =~ ^[0-9a-f]{64}$ ]] || return 1
    entries="$(jq -c \
      --arg name "$(basename "${path}")" \
      --argjson size "${size}" \
      --arg digest "sha256:${hash}" \
      '. + [{name: $name, size: $size, digest: $digest}]' <<<"${entries}")" || return 1
  done
  printf '%s\n' "${entries}"
}

# True when the release is in the expected draft state and holds exactly the
# expected assets, each uploaded with the expected size and SHA-256 digest.
validate_github_release_asset_readback() {
  local release_json="$1"
  local expected_draft="$2"
  local expected_assets="$3"
  jq -e \
    --arg tag "${TAG}" \
    --argjson expected_draft "${expected_draft}" \
    --argjson expected "${expected_assets}" \
    '. as $release |
     .draft == $expected_draft and
     .tag_name == $tag and
     ($expected | length) > 0 and
     (.assets | length) == ($expected | length) and
     ([.assets[].name] | sort) == ([$expected[].name] | sort) and
     all($expected[]; . as $want |
       any($release.assets[];
         .name == $want.name and .state == "uploaded" and .size == $want.size and .digest == $want.digest))' \
    <<<"${release_json}" >/dev/null
}
