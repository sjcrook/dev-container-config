#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSWERS_FILE="$1"
BLOCKED_HOSTS_JSON="${2:-[]}"

# jq always prints one array element per line. runArgs is a flat flag/value
# list (--cap-add, CHOWN, --cap-add, SETUID, ...), so pair those lines back up
# for readability -- this is the only array formatted this way; every other
# array (extensions, blockedRegistryHosts, etc.) stays one-per-line.
jq --indent 4 --argjson blockedHosts "${BLOCKED_HOSTS_JSON}" -f "${SCRIPT_DIR}/render-devcontainer.jq" "${ANSWERS_FILE}" | awk '
  /^    "runArgs": \[$/ { print; in_runargs=1; pending=""; next }
  in_runargs && /^    \],?$/ {
    if (pending != "") print "        " pending
    print; in_runargs=0; next
  }
  in_runargs {
    line=$0
    sub(/^[ \t]+/, "", line)
    if (pending == "") { pending = line } else { print "        " pending " " line; pending="" }
    next
  }
  { print }
'
