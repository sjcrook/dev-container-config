#!/usr/bin/env bash
# Resolves the merged blockedRegistryHosts list: any inline array in the
# answers file, plus the contents of blockedRegistryHostsFile (if set),
# deduped. Keeps the actual hostnames out of the generator's own code so no
# list is hardcoded here -- see examples/blockedRegistryHosts.txt.
set -euo pipefail

blocked_hosts_resolve() {
  local answers_file="$1" submodule_root="$2"
  local answers_dir file_ref resolved file_hosts_json inline_json
  answers_dir="$(cd "$(dirname "${answers_file}")" && pwd)"

  inline_json="$(jq -c '.blockedRegistryHosts // []' "${answers_file}")"

  file_ref="$(jq -r '.blockedRegistryHostsFile // empty' "${answers_file}")"
  file_hosts_json="[]"
  if [ -n "${file_ref}" ]; then
    resolved="$(resolve_submodule_path "${file_ref}" "${answers_dir}" "${submodule_root}")"
    if [ ! -f "${resolved}" ]; then
      echo "ERROR: blockedRegistryHostsFile not found: ${resolved}" >&2
      exit 1
    fi
    file_hosts_json="$(grep -v '^[[:space:]]*#' "${resolved}" | grep -v '^[[:space:]]*$' | jq -R -s 'split("\n") | map(gsub("^\\s+|\\s+$";"")) | map(select(length > 0))')"
  fi

  jq -c -n --argjson a "${inline_json}" --argjson b "${file_hosts_json}" '($a + $b) | unique'
}
