#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/toolchains.sh
source "${SCRIPT_DIR}/toolchains.sh"

ANSWERS_FILE="$1"

REMOTE_USER="$(jq -r '.remoteUser // "vscode"' "${ANSWERS_FILE}")"
NODE_VERSION="$(jq -r '.dockerfileBuild.toolchains.node.version // empty' "${ANSWERS_FILE}")"
JAVA_VERSION="$(jq -r '.dockerfileBuild.toolchains.java.version // empty' "${ANSWERS_FILE}")"
PNPM_NPMRC_PATH="$(jq -r '.dockerfileBuild.toolchains.pnpm.npmrcPath // empty' "${ANSWERS_FILE}")"
NPM_VERSION="$(jq -r '.dockerfileBuild.toolchains.pnpm.npmVersion // "11"' "${ANSWERS_FILE}")"
PNPM_VERSION="$(jq -r '.dockerfileBuild.toolchains.pnpm.version // "12"' "${ANSWERS_FILE}")"

if [ -n "${PNPM_NPMRC_PATH}" ] && [ -z "${NODE_VERSION}" ]; then
  echo "ERROR: dockerfileBuild.toolchains.pnpm requires dockerfileBuild.toolchains.node to be set" >&2
  exit 1
fi

cat <<EOF

# Base image standardized across all projects generated from this submodule.
# All tool installs and root-only hardening run here at \`docker build\` time
# while the build step still runs as root. This cannot be done via sudo in
# postCreateCommand: devcontainer.json's runArgs sets --security-opt
# no-new-privileges, which blocks privilege escalation once the container starts.
FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04
EOF

if [ -n "${NODE_VERSION}" ]; then
  toolchain_node_dockerfile "${NODE_VERSION}"
fi

if [ -n "${JAVA_VERSION}" ]; then
  toolchain_java_dockerfile "${JAVA_VERSION}"
fi

if [ -n "${PNPM_NPMRC_PATH}" ]; then
  if ! [[ "${REMOTE_USER}" =~ ^[a-z_][a-z0-9_-]*$ ]] ||
     ! [[ "${NPM_VERSION}" =~ ^[0-9]+(\.[0-9]+\.[0-9]+)?$ ]] ||
     ! [[ "${PNPM_VERSION}" =~ ^12(\.[0-9]+\.[0-9]+)?$ ]]; then
    echo "ERROR: pnpm requires a valid remoteUser, npm major/exact version, and pnpm 12 major/exact version" >&2
    exit 1
  fi
  if [ "${REMOTE_USER}" = "root" ]; then
    echo "ERROR: pnpm runtime configuration requires a non-root remoteUser" >&2
    exit 1
  fi
  toolchain_pnpm_dockerfile "${REMOTE_USER}" "${NPM_VERSION}" "${PNPM_VERSION}"
fi

APT_PACKAGES=()
while IFS= read -r pkg; do
  [ -n "${pkg}" ] && APT_PACKAGES+=("${pkg}")
done < <(jq -r '.dockerfileBuild.aptPackages // [] | .[]' "${ANSWERS_FILE}")

if [ "${#APT_PACKAGES[@]}" -gt 0 ]; then
  printf '\n# -- Additional apt packages --------------------------------------------------\nRUN apt-get update \\\n'
  last_index=$(( ${#APT_PACKAGES[@]} - 1 ))
  for i in "${!APT_PACKAGES[@]}"; do
    if [ "${i}" -lt "${last_index}" ]; then
      printf '    && apt-get install -y %s \\\n' "${APT_PACKAGES[$i]}"
    else
      printf '    && apt-get install -y %s\n' "${APT_PACKAGES[$i]}"
    fi
  done
fi

FILE_ENTRIES=()
while IFS= read -r line; do
  [ -n "${line}" ] && FILE_ENTRIES+=("${line}")
done < <(jq -c '.dockerfileBuild.files // [] | .[]' "${ANSWERS_FILE}")

if [ "${#FILE_ENTRIES[@]}" -gt 0 ]; then
  printf '\n# -- Project-supplied files (copied by files.sh into the build context) -------\n'
  for entry in "${FILE_ENTRIES[@]}"; do
    src="$(printf '%s' "${entry}" | jq -r '.sourcePath')"
    target="$(printf '%s' "${entry}" | jq -r '.targetPath')"
    executable="$(printf '%s' "${entry}" | jq -r '.executable // false')"
    base="$(basename "${src}")"
    printf 'COPY %s %s\n' "${base}" "${target}"
    if [ "${executable}" = "true" ]; then
      printf 'RUN chmod +x %s\n' "${target}"
    fi
  done
fi

cat <<EOF

# -- Security hardening (must run as root at build time) -----------------------
# Cannot be done via sudo in postCreateCommand -- see note above.
RUN passwd -l root \\
    && (deluser ${REMOTE_USER} sudo 2>/dev/null || true)
EOF
