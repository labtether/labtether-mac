#!/usr/bin/env bash

set -Eeuo pipefail

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
