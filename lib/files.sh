#!/usr/bin/env bash
# Copies answers.files[] entries into the generated output directory.
#
# sourcePath resolution:
#   ./foo or ../foo  -> relative to the answers file's own directory
#                       (a file the consuming project supplies itself)
#   anything else    -> relative to this submodule's root
#                       (a built-in template, e.g. templates/npm-guard.sh)
set -euo pipefail

# resolve_submodule_path <path> <answers_dir> <submodule_root>
#   /foo             -> used as-is (already absolute)
#   ./foo or ../foo  -> relative to answers_dir
#   anything else    -> relative to submodule_root
resolve_submodule_path() {
  local path="$1" answers_dir="$2" submodule_root="$3"
  case "${path}" in
    /*) printf '%s' "${path}" ;;
    ./*|../*) printf '%s/%s' "${answers_dir}" "${path}" ;;
    *) printf '%s/%s' "${submodule_root}" "${path}" ;;
  esac
}

files_copy_all() {
  local answers_file="$1" submodule_root="$2" out_dir="$3"
  local answers_dir
  answers_dir="$(cd "$(dirname "${answers_file}")" && pwd)"

  local entries=()
  while IFS= read -r line; do
    [ -n "${line}" ] && entries+=("${line}")
  done < <(jq -c '.files // [] | .[]' "${answers_file}")

  local entry src base resolved
  for entry in "${entries[@]}"; do
    src="$(printf '%s' "${entry}" | jq -r '.sourcePath')"
    base="$(basename "${src}")"
    resolved="$(resolve_submodule_path "${src}" "${answers_dir}" "${submodule_root}")"
    if [ ! -f "${resolved}" ]; then
      echo "ERROR: files[] sourcePath not found: ${resolved}" >&2
      exit 1
    fi
    cp -f "${resolved}" "${out_dir}/${base}"
    echo "Copied ${resolved} -> ${out_dir}/${base}"
  done
}
