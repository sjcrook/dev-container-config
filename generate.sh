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
INTERACTIVE=0

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

# Render everything into a staging directory first; nothing touches OUT_DIR
# until every step below has succeeded, so a failed run leaves it untouched.
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/devcontainer-config.XXXXXX")"
trap 'rm -rf "${STAGE_DIR}"' EXIT

if [ -n "${ANSWERS_FILE}" ]; then
  ANSWERS_JSON_FILE="$(answers_load_from_file "${ANSWERS_FILE}")"
  SOURCE_LABEL="${ANSWERS_FILE}"
  ANSWERS_OUT_NAME="$(basename "${ANSWERS_FILE}")"
else
  ANSWERS_JSON_FILE="$(answers_collect_interactive)"
  SOURCE_LABEL="<interactive>"
  ANSWERS_OUT_NAME="devcontainer.answers.json"
  INTERACTIVE=1
fi

answers_validate_schema "${ANSWERS_JSON_FILE}"

# Stage the answers (interactive or copied) alongside the generated output so
# future regenerations have a durable, reviewable source instead of a temp file.
# Skip the copy if --answers already points at that exact destination.
ANSWERS_SRC_ABS="$(cd "$(dirname "${ANSWERS_JSON_FILE}")" && pwd)/$(basename "${ANSWERS_JSON_FILE}")"
ANSWERS_OUT_ABS=""
[ -d "${OUT_DIR}" ] && ANSWERS_OUT_ABS="$(cd "${OUT_DIR}" && pwd)/${ANSWERS_OUT_NAME}"
if [ "${ANSWERS_SRC_ABS}" != "${ANSWERS_OUT_ABS}" ]; then
  cp -f "${ANSWERS_JSON_FILE}" "${STAGE_DIR}/${ANSWERS_OUT_NAME}"
  if [ "${INTERACTIVE}" = "1" ]; then
    normalize_absolute_path() {
      local path="$1" component
      local -a components=() normalized=()
      IFS='/' read -r -a components <<< "${path}"
      for component in "${components[@]}"; do
        case "${component}" in
          ""|.) ;;
          ..) [ "${#normalized[@]}" -gt 0 ] && unset 'normalized[${#normalized[@]}-1]' ;;
          *) normalized+=("${component}") ;;
        esac
      done
      local result=""
      for component in "${normalized[@]}"; do
        result="${result}/${component}"
      done
      printf '%s' "${result:-/}"
    }

    relative_path_from() {
      local target base component relative=""
      local -a target_components=() base_components=()
      target="$(normalize_absolute_path "$1")"
      base="$(normalize_absolute_path "$2")"
      IFS='/' read -r -a target_components <<< "${target#/}"
      IFS='/' read -r -a base_components <<< "${base#/}"

      local common=0
      while [ "${common}" -lt "${#target_components[@]}" ] &&
            [ "${common}" -lt "${#base_components[@]}" ] &&
            [ "${target_components[common]}" = "${base_components[common]}" ]; do
        common=$((common + 1))
      done
      local i
      for ((i = common; i < ${#base_components[@]}; i++)); do
        relative="../${relative}"
      done
      for ((i = common; i < ${#target_components[@]}; i++)); do
        relative="${relative}${target_components[i]}/"
      done
      relative="${relative%/}"
      printf '%s' "${relative:-.}"
    }

    answers_output_dir="${OUT_DIR}"
    case "${answers_output_dir}" in
      /*) ;;
      *) answers_output_dir="${PWD}/${answers_output_dir}" ;;
    esac

    pnpm_npmrc_path="$(jq -r '.toolchains.pnpm.npmrcPath // empty' "${ANSWERS_JSON_FILE}")"
    if [[ "${pnpm_npmrc_path}" = /* ]]; then
      pnpm_npmrc_path="$(relative_path_from "${pnpm_npmrc_path}" "${answers_output_dir}")"
    fi
    blocked_hosts_file="$(jq -r '.blockedRegistryHostsFile // empty' "${ANSWERS_JSON_FILE}")"
    if [[ "${blocked_hosts_file}" = /* ]]; then
      blocked_hosts_file="$(relative_path_from "${blocked_hosts_file}" "${answers_output_dir}")"
    fi
    jq \
      --arg npmrcPath "${pnpm_npmrc_path}" \
      --arg blockedHostsFile "${blocked_hosts_file}" \
      'if (.toolchains.pnpm.npmrcPath // "" | startswith("/")) then .toolchains.pnpm.npmrcPath = $npmrcPath else . end
       | if (.blockedRegistryHostsFile // "" | startswith("/")) then .blockedRegistryHostsFile = $blockedHostsFile else . end' \
      "${STAGE_DIR}/${ANSWERS_OUT_NAME}" >"${STAGE_DIR}/${ANSWERS_OUT_NAME}.tmp"
    mv -f "${STAGE_DIR}/${ANSWERS_OUT_NAME}.tmp" "${STAGE_DIR}/${ANSWERS_OUT_NAME}"
  fi
  SOURCE_LABEL="${OUT_DIR}/${ANSWERS_OUT_NAME}"
fi

BLOCKED_HOSTS_JSON="$(blocked_hosts_resolve "${ANSWERS_JSON_FILE}" "${SCRIPT_DIR}")"

DEVCONTAINER_BODY="$(bash "${SCRIPT_DIR}/lib/render-devcontainer.sh" "${ANSWERS_JSON_FILE}" "${BLOCKED_HOSTS_JSON}")"
DOCKERFILE_BODY="$(bash "${SCRIPT_DIR}/lib/render-dockerfile.sh" "${ANSWERS_JSON_FILE}")"

hash_write_generated "${OUT_DIR}/devcontainer.json" "${STAGE_DIR}/devcontainer.json" "//" "${SOURCE_LABEL}" "${DEVCONTAINER_BODY}" "${FORCE}"
hash_write_generated "${OUT_DIR}/Dockerfile" "${STAGE_DIR}/Dockerfile" "#" "${SOURCE_LABEL}" "${DOCKERFILE_BODY}" "${FORCE}"

files_copy_all "${ANSWERS_JSON_FILE}" "${SCRIPT_DIR}" "${STAGE_DIR}" >/dev/null
pnpm_copy_files "${ANSWERS_JSON_FILE}" "${SCRIPT_DIR}" "${STAGE_DIR}" >/dev/null

# Every step succeeded -- commit the staged files into OUT_DIR.
mkdir -p "${OUT_DIR}"
while IFS= read -r -d '' f; do
  name="$(basename "${f}")"
  cp -f "${f}" "${OUT_DIR}/${name}"
  echo "Wrote ${OUT_DIR}/${name}"
done < <(find "${STAGE_DIR}" -maxdepth 1 -type f -print0)

echo "Done. Review ${OUT_DIR}/devcontainer.json and ${OUT_DIR}/Dockerfile."
