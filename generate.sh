#!/usr/bin/env bash
# Generates .devcontainer/devcontainer.json and .devcontainer/Dockerfile from
# an answers file (schemaVersion: 1), or from interactive prompts.
#
# Usage:
#   generate.sh --answers <file> [--out-dir <dir>] [--force]
#   generate.sh [--out-dir <dir>] [--force]      # interactive prompts
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/answers.sh
source "${SCRIPT_DIR}/lib/answers.sh"
# shellcheck source=lib/hash.sh
source "${SCRIPT_DIR}/lib/hash.sh"
# shellcheck source=lib/files.sh
source "${SCRIPT_DIR}/lib/files.sh"
# shellcheck source=lib/blocked-hosts.sh
source "${SCRIPT_DIR}/lib/blocked-hosts.sh"

OUT_DIR=".devcontainer"
ANSWERS_FILE=""
FORCE=0

usage() {
  cat <<'EOF'
Usage: generate.sh [--answers <file>] [--out-dir <dir>] [--force]

  --answers <file>  Load answers from a JSON file instead of prompting interactively.
  --out-dir <dir>   Directory to write devcontainer.json/Dockerfile into (default: .devcontainer).
  --force           Overwrite existing output files even if they were hand-edited.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --answers) ANSWERS_FILE="$2"; shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

mkdir -p "${OUT_DIR}"

if [ -n "${ANSWERS_FILE}" ]; then
  ANSWERS_JSON_FILE="$(answers_load_from_file "${ANSWERS_FILE}")"
  SOURCE_LABEL="${ANSWERS_FILE}"
  ANSWERS_OUT_NAME="$(basename "${ANSWERS_FILE}")"
else
  ANSWERS_JSON_FILE="$(answers_collect_interactive)"
  SOURCE_LABEL="<interactive>"
  ANSWERS_OUT_NAME="devcontainer.answers.json"
fi

answers_validate_schema "${ANSWERS_JSON_FILE}"

# Persist the answers (interactive or copied) alongside the generated output so
# future regenerations have a durable, reviewable source instead of a temp file.
ANSWERS_OUT="${OUT_DIR}/${ANSWERS_OUT_NAME}"
ANSWERS_OUT_ABS="$(cd "${OUT_DIR}" && pwd)/${ANSWERS_OUT_NAME}"
ANSWERS_SRC_ABS="$(cd "$(dirname "${ANSWERS_JSON_FILE}")" && pwd)/$(basename "${ANSWERS_JSON_FILE}")"
if [ "${ANSWERS_SRC_ABS}" != "${ANSWERS_OUT_ABS}" ]; then
  cp -f "${ANSWERS_JSON_FILE}" "${ANSWERS_OUT}"
  echo "Wrote ${ANSWERS_OUT}"
  SOURCE_LABEL="${ANSWERS_OUT}"
fi

BLOCKED_HOSTS_JSON="$(blocked_hosts_resolve "${ANSWERS_JSON_FILE}" "${SCRIPT_DIR}")"

DEVCONTAINER_BODY="$(bash "${SCRIPT_DIR}/lib/render-devcontainer.sh" "${ANSWERS_JSON_FILE}" "${BLOCKED_HOSTS_JSON}")"
DOCKERFILE_BODY="$(bash "${SCRIPT_DIR}/lib/render-dockerfile.sh" "${ANSWERS_JSON_FILE}")"

hash_write_generated "${OUT_DIR}/devcontainer.json" "//" "${SOURCE_LABEL}" "${DEVCONTAINER_BODY}" "${FORCE}"
hash_write_generated "${OUT_DIR}/Dockerfile" "#" "${SOURCE_LABEL}" "${DOCKERFILE_BODY}" "${FORCE}"

files_copy_all "${ANSWERS_JSON_FILE}" "${SCRIPT_DIR}" "${OUT_DIR}"

echo "Done. Review ${OUT_DIR}/devcontainer.json and ${OUT_DIR}/Dockerfile."
