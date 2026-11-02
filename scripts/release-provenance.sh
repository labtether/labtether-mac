#!/usr/bin/env bash

# Writes release-provenance.json for the signed app. On macOS 27.2,
# `plutil -insert` into a JSON file fails with "Conversion to OpenStep format
# is not supported", so the keys go into an XML plist that is then converted.
# verify-release-archive.sh reads each key back with `plutil -extract`.
write_release_provenance() {
  local output="$1"
  local tag="$2"
  local wrapper_commit="$3"
  local agent_commit="$4"
  local work_dir="$5"
  local plist="${work_dir}/release-provenance.plist"

  plutil -create xml1 "${plist}" \
    && plutil -insert tag -string "${tag}" "${plist}" \
    && plutil -insert wrapper_commit -string "${wrapper_commit}" "${plist}" \
    && plutil -insert agent_commit -string "${agent_commit}" "${plist}" \
    && plutil -convert json -o "${output}" "${plist}" \
    && rm -f "${plist}"
}
