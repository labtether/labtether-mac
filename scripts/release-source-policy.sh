#!/usr/bin/env bash

# Permit only the exact shared instruction link, in both the index and checkout.
canonical_guide_link_is_safe() {
  local repo="$1" index_entry="$2"
  local link_hash target_entry target_header target_mode target_hash target_stage local_hash
  link_hash="$(printf 'AGENTS.md' | git -C "${repo}" hash-object --stdin)" || return 1
  [[ "${index_entry}" == "120000 ${link_hash} 0"$'\t'"CLAUDE.md" ]] || return 1
  [[ -L "${repo}/CLAUDE.md" ]] || return 1
  [[ "$(readlink "${repo}/CLAUDE.md"; printf '.')" == $'AGENTS.md\n.' ]] || return 1
  [[ -f "${repo}/AGENTS.md" && ! -L "${repo}/AGENTS.md" ]] || return 1
  target_entry="$(git -C "${repo}" ls-files -s -- AGENTS.md)" || return 1
  [[ "${target_entry#*$'\t'}" == "AGENTS.md" ]] || return 1
  target_header="${target_entry%%$'\t'*}"
  read -r target_mode target_hash target_stage <<< "${target_header}"
  [[ "${target_mode}" == 100644 || "${target_mode}" == 100755 ]] || return 1
  [[ "${target_stage}" == 0 ]] || return 1
  # Let Git normalize checkout line endings before comparing the regular target.
  local_hash="$(git -C "${repo}" hash-object --path=AGENTS.md -- AGENTS.md)" || return 1
  [[ "${local_hash}" == "${target_hash}" ]]
}

repo_has_forbidden_release_input() {
  local repo="$1" index_entry mode tracked_path lowercase_path
  while IFS= read -r -d '' index_entry; do
    [[ "${index_entry}" != "LABTETHER_GIT_LS_FILES_FAILED" ]] || return 0
    mode="${index_entry%% *}"
    tracked_path="${index_entry#*$'\t'}"
    case "${mode}" in
      100644|100755) ;;
      120000) canonical_guide_link_is_safe "${repo}" "${index_entry}" || return 0 ;;
      *) return 0 ;;
    esac
    lowercase_path="$(printf '%s' "${tracked_path}" | tr '[:upper:]' '[:lower:]')"
    case "${lowercase_path}" in
      *.p12|*.pfx|*.p8|*.pem|*.key|*.cer|*.crt|*.der|*.jks|*.keystore|*.keychain|*.keychain-db|*.mobileprovision|*.provisionprofile)
        return 0
        ;;
    esac
  done < <(git -C "${repo}" ls-files -s -z || printf 'LABTETHER_GIT_LS_FILES_FAILED\0')
  return 1
}
