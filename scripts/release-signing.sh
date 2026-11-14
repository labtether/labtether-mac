#!/usr/bin/env bash

# Shared signing and packaging steps for macOS releases. Sourced by
# release-local.sh (login Keychain identity, notarytool profile) and
# sign-release-ci.sh (temporary keychain, App Store Connect API key), and by
# verify-release-archive.sh for the team pin and the archive entry check.
# The caller defines fail().

# The one Apple team that may sign LabTether macOS releases: Watari Labs Pty Ltd.
# shellcheck disable=SC2034 # read by the scripts that source this file
RELEASE_TEAM_ID="D2WZW3YTL6"

ARCHIVE_NAME="labtether-agent-macos-universal.tar.gz"
CHECKSUM_NAME="${ARCHIVE_NAME}.sha256"
DMG_NAME="labtether-agent-macos-universal.dmg"
DMG_CHECKSUM_NAME="${DMG_NAME}.sha256"
RELEASE_ASSET_NAMES=("${ARCHIVE_NAME}" "${CHECKSUM_NAME}" "${DMG_NAME}" "${DMG_CHECKSUM_NAME}")
MOVED_OUTPUTS=()

# Fails unless the gzip tar archive holds only "LabTether Agent.app" made of
# regular files and directories, with no unsafe or duplicate paths.
check_app_archive_entries() {
  local archive="$1"
  local work_dir="$2"
  local entry_list="${work_dir}/entries.txt"
  local detail_list="${work_dir}/entry-details.txt"
  local entry
  tar -tzf "${archive}" >"${entry_list}" || fail "archive could not be listed"
  tar -tvzf "${archive}" >"${detail_list}" || fail "archive could not be listed"
  [[ -s "${entry_list}" ]] || fail "archive is empty"
  if [[ -n "$(LC_ALL=C sort "${entry_list}" | uniq -d)" ]]; then
    fail "archive contains duplicate entries"
  fi
  while IFS= read -r entry; do
    [[ -n "${entry}" ]] || fail "archive contains an empty entry"
    case "${entry}" in
      /*|../*|*/../*|*/..) fail "archive contains an unsafe path" ;;
    esac
    case "${entry}" in
      "LabTether Agent.app"|"LabTether Agent.app/"|"LabTether Agent.app/"*) ;;
      *) fail "archive contains an unexpected top-level entry" ;;
    esac
  done <"${entry_list}"
  if awk 'substr($1, 1, 1) != "d" && substr($1, 1, 1) != "-" { found=1 } END { exit(found ? 0 : 1) }' "${detail_list}"; then
    fail "archive contains a link or special-file entry"
  fi
  if grep -Eq ' -> | link to ' "${detail_list}"; then
    fail "archive contains a symlink or hard link"
  fi
}

# Extracts a checked app archive into an empty directory and fails when the
# result holds anything but one regular app bundle without links.
extract_app_archive() {
  local archive="$1"
  local destination="$2"
  local app="${destination}/LabTether Agent.app"
  tar -xzf "${archive}" -C "${destination}" || fail "archive could not be extracted"
  [[ -d "${app}" && ! -L "${app}" ]] || fail "archive did not produce one regular app bundle"
  if find "${app}" -type l -print -quit | grep -q .; then
    fail "extracted app contains a symlink"
  fi
  if find "${app}" -type f -links +1 -print -quit | grep -q .; then
    fail "extracted app contains a hard-linked file"
  fi
}

# Fails unless the app's release record names the expected tag and commits.
check_app_release_record() {
  local app="$1"
  local tag="$2"
  local wrapper_commit="$3"
  local agent_commit="$4"
  local record="${app}/Contents/Resources/release-provenance.json"
  [[ -f "${record}" && ! -L "${record}" ]] || fail "the app's release record is missing"
  [[ "$(plutil -extract tag raw "${record}")" == "${tag}" ]] || fail "release record tag mismatch"
  [[ "$(plutil -extract wrapper_commit raw "${record}")" == "${wrapper_commit}" ]] || fail "release record wrapper commit mismatch"
  [[ "$(plutil -extract agent_commit raw "${record}")" == "${agent_commit}" ]] || fail "release record agent commit mismatch"
  [[ "$(plutil -extract CFBundleShortVersionString raw "${app}/Contents/Info.plist")" == "${tag#v}" ]] \
    || fail "app version does not match tag"
}

codesign_release_item() {
  codesign --force --timestamp --sign "${SIGNING_IDENTITY}" \
    ${CODESIGN_KEYCHAIN_ARGS[@]+"${CODESIGN_KEYCHAIN_ARGS[@]}"} "$@" >/dev/null 2>&1
}

# Submits one file, waits, and prints Apple's status word.
notarize_release_item() {
  local item="$1"
  local result="$2"
  if ! xcrun notarytool submit "${item}" \
    ${NOTARY_AUTH_ARGS[@]+"${NOTARY_AUTH_ARGS[@]}"} \
    --wait --output-format json >"${result}" 2>/dev/null; then
    printf 'submission failed\n'
    return 0
  fi
  plutil -extract status raw "${result}" 2>/dev/null || printf 'no result\n'
}

write_release_checksum() {
  local directory="$1"
  local name="$2"
  local hash
  hash="$(shasum -a 256 "${directory}/${name}" | awk '{ print $1 }')"
  [[ "${hash}" =~ ^[0-9a-f]{64}$ ]] || fail "could not calculate the checksum of ${name}"
  printf '%s  %s\n' "${hash}" "${name}" >"${directory}/${name}.sha256"
  chmod 0600 "${directory}/${name}" "${directory}/${name}.sha256"
}

# Signs the unsigned app in STAGE_DIR, notarizes and staples it, then writes
# the archive and the disk image (signed, notarized and stapled too) with
# their checksums to ASSET_DIR. Uses TAG, SCRIPT_DIR, NOTARY_DIR,
# SIGNING_IDENTITY, CODESIGN_KEYCHAIN_ARGS and NOTARY_AUTH_ARGS.
sign_and_package_release() {
  local app="${STAGE_DIR}/LabTether Agent.app"
  local apple_status
  xattr -cr "${app}"
  codesign_release_item --options runtime "${app}/Contents/Resources/labtether-agent" \
    || fail "signing the bundled agent failed"
  codesign_release_item --options runtime "${app}/Contents/MacOS/LabTetherAgent" \
    || fail "signing the native host failed"
  codesign_release_item --options runtime "${app}" || fail "signing the app bundle failed"
  "${SCRIPT_DIR}/validate-app.sh" "${app}" --architectures arm64,x86_64 \
    --agent-version "${TAG}" --require-signature >/dev/null 2>&1 \
    || fail "strict signed app validation failed"

  ditto -c -k --keepParent "${app}" "${NOTARY_DIR}/submission.zip" >/dev/null 2>&1 \
    || fail "creating the notarization submission failed"
  printf 'Waiting for Apple to notarize the app.\n'
  apple_status="$(notarize_release_item "${NOTARY_DIR}/submission.zip" "${NOTARY_DIR}/result.json")"
  [[ "${apple_status}" == "Accepted" ]] || fail "Apple notarization of the app: ${apple_status}"
  xcrun stapler staple "${app}" >/dev/null 2>&1 || fail "stapling the notarization ticket failed"
  xcrun stapler validate "${app}" >/dev/null 2>&1 || fail "the stapled notarization ticket did not validate"
  codesign --verify --deep --strict --verbose=4 "${app}" >/dev/null 2>&1 \
    || fail "the final signed app did not pass strict verification"
  spctl --assess --type execute --verbose=4 "${app}" >/dev/null 2>&1 \
    || fail "the final app did not pass Gatekeeper assessment"

  (cd "${STAGE_DIR}" && COPYFILE_DISABLE=1 tar -czf "${ASSET_DIR}/${ARCHIVE_NAME}" "LabTether Agent.app") \
    || fail "creating the release archive failed"
  write_release_checksum "${ASSET_DIR}" "${ARCHIVE_NAME}"

  # The disk image holds the stapled app. It gets its own Developer ID
  # signature, notarization and stapled ticket, so it opens without a warning.
  "${SCRIPT_DIR}/build-dmg.sh" --app "${app}" --output "${ASSET_DIR}/${DMG_NAME}" >/dev/null \
    || fail "building the disk image failed"
  codesign_release_item "${ASSET_DIR}/${DMG_NAME}" || fail "signing the disk image failed"
  printf 'Waiting for Apple to notarize the disk image.\n'
  apple_status="$(notarize_release_item "${ASSET_DIR}/${DMG_NAME}" "${NOTARY_DIR}/dmg-result.json")"
  [[ "${apple_status}" == "Accepted" ]] || fail "Apple notarization of the disk image: ${apple_status}"
  xcrun stapler staple "${ASSET_DIR}/${DMG_NAME}" >/dev/null 2>&1 \
    || fail "stapling the notarization ticket to the disk image failed"
  write_release_checksum "${ASSET_DIR}" "${DMG_NAME}"
}

# Moves the four verified assets into an empty output directory without
# overwriting anything, and checks the bytes did not change on the way.
place_release_assets() {
  local source_dir="$1"
  local output_dir="$2"
  local name
  local before
  if find "${output_dir}" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
    fail "output directory changed before final placement"
  fi
  for name in "${RELEASE_ASSET_NAMES[@]}"; do
    before="$(shasum -a 256 "${source_dir}/${name}" | awk '{ print $1 }')"
    [[ ! -e "${output_dir}/${name}" && ! -L "${output_dir}/${name}" ]] \
      || fail "a release asset destination already exists"
    mv -n -- "${source_dir}/${name}" "${output_dir}/${name}"
    [[ ! -e "${source_dir}/${name}" && -f "${output_dir}/${name}" && ! -L "${output_dir}/${name}" ]] \
      || fail "release asset placement did not complete without overwrite"
    MOVED_OUTPUTS+=("${name}")
    [[ "$(shasum -a 256 "${output_dir}/${name}" | awk '{ print $1 }')" == "${before}" ]] \
      || fail "a placed release asset changed unexpectedly"
    chmod 0644 "${output_dir}/${name}"
  done
}

# Removes assets this run already placed, after a failure.
remove_placed_release_assets() {
  local output_dir="$1"
  local name
  for name in ${MOVED_OUTPUTS[@]+"${MOVED_OUTPUTS[@]}"}; do
    rm -f -- "${output_dir}/${name}"
  done
}
