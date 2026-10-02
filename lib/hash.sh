#!/usr/bin/env bash
# Content-hash tracking so regeneration can tell "untouched since last
# generation" (safe to overwrite) apart from "hand-edited" (needs a manual
# merge) without requiring the user to remember which files are generated.
set -euo pipefail

_hash_sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    sha256sum | awk '{print $1}'
  fi
}

# hash_write_generated <target_path> <comment_char> <source_label> <body> <force:0|1>
hash_write_generated() {
  local target="$1" comment="$2" source_label="$3" body="$4" force="${5:-0}"
  local new_hash
  new_hash="$(printf '%s' "${body}" | _hash_sha256)"

  if [ -f "${target}" ] && [ "${force}" != "1" ]; then
    local existing_declared existing_body existing_actual
    existing_declared="$(sed -n '2p' "${target}" | sed -n 's/.*content-hash: \([a-f0-9]*\).*/\1/p')"
    existing_body="$(tail -n +3 "${target}")"
    existing_actual="$(printf '%s' "${existing_body}" | _hash_sha256)"
    if [ -n "${existing_declared}" ] && [ "${existing_declared}" != "${existing_actual}" ]; then
      local newfile="${target}.new"
      {
        printf '%s GENERATED FILE -- do not hand-edit. Source: %s\n' "${comment}" "${source_label}"
        printf '%s generator: dev-container-config  schemaVersion: 1  content-hash: %s\n' "${comment}" "${new_hash}"
        printf '%s' "${body}"
      } >"${newfile}"
      echo "WARNING: ${target} was hand-edited since it was last generated." >&2
      echo "         New output written to ${newfile} -- merge manually, then remove the .new file." >&2
      return 0
    fi
  fi

  {
    printf '%s GENERATED FILE -- do not hand-edit. Source: %s\n' "${comment}" "${source_label}"
    printf '%s generator: dev-container-config  schemaVersion: 1  content-hash: %s\n' "${comment}" "${new_hash}"
    printf '%s' "${body}"
  } >"${target}"
  echo "Wrote ${target}"
}
