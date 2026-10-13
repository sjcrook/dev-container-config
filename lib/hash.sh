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

# hash_write_generated <out_target> <stage_target> <comment_char> <source_label> <body> <force:0|1>
#   out_target   -- the real (final) destination, only read here to detect hand-edits
#   stage_target -- where the freshly rendered body is written; caller moves it into
#                   place once every generation step has succeeded
hash_write_generated() {
  local out_target="$1" stage_target="$2" comment="$3" source_label="$4" body="$5" force="${6:-0}"
  local new_hash
  new_hash="$(printf '%s' "${body}" | _hash_sha256)"

  if [ -f "${out_target}" ] && [ "${force}" != "1" ]; then
    local existing_declared existing_body existing_actual
    existing_declared="$(sed -n '2p' "${out_target}" | sed -n 's/.*content-hash: \([a-f0-9]*\).*/\1/p')"
    existing_body="$(tail -n +3 "${out_target}")"
    existing_actual="$(printf '%s' "${existing_body}" | _hash_sha256)"
    if [ -n "${existing_declared}" ] && [ "${existing_declared}" != "${existing_actual}" ]; then
      local newfile="${out_target}.new"
      {
        printf '%s GENERATED FILE -- do not hand-edit. Source: %s\n' "${comment}" "${source_label}"
        printf '%s generator: dev-container-config  schemaVersion: 1  content-hash: %s\n' "${comment}" "${new_hash}"
        printf '%s' "${body}"
      } >"${newfile}"
      echo "WARNING: ${out_target} was hand-edited since it was last generated." >&2
      echo "         New output written to ${newfile} -- merge manually, then remove the .new file." >&2
      return 0
    fi
  fi

  {
    printf '%s GENERATED FILE -- do not hand-edit. Source: %s\n' "${comment}" "${source_label}"
    printf '%s generator: dev-container-config  schemaVersion: 1  content-hash: %s\n' "${comment}" "${new_hash}"
    printf '%s' "${body}"
  } >"${stage_target}"
}
