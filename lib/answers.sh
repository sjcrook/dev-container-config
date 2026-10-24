#!/usr/bin/env bash
# Loads answers from a file, or collects them interactively -- both paths
# converge on the same schemaVersion:2 JSON shape consumed by the renderers.
set -euo pipefail

answers_load_from_file() {
  local path="$1"
  if [ ! -f "${path}" ]; then
    echo "Answers file not found: ${path}" >&2
    exit 1
  fi
  printf '%s' "${path}"
}

answers_validate_schema() {
  local path="$1" version
  version="$(jq -r '.schemaVersion // empty' "${path}")"
  if [ -z "${version}" ]; then
    echo "Answers file is missing required field: schemaVersion" >&2
    exit 1
  fi
  if [ "${version}" != "2" ]; then
    echo "Unsupported schemaVersion: ${version} (this generator supports: 2)" >&2
    exit 1
  fi
}

# Prompts on the host terminal, writes a temp answers.json file, prints its path.
answers_collect_interactive() {
  local tmp
  tmp="$(mktemp -t devcontainer-answers.XXXXXX)"

  local name remote_user want_node node_version want_java java_version
  local add_mount host_path container_path readonly mount_directories mount_index target_default
  local want_pnpm_enforce pnpm_npmrc_path blocked_hosts_raw blocked_hosts_is_file extra_hosts_raw
  local post_create java_source_paths extensions_raw files_raw remote_env_raw

  read -r -p "Project name [DevContainer]: " name
  name="${name:-DevContainer}"

  read -r -p "Remote user [vscode]: " remote_user
  remote_user="${remote_user:-vscode}"

  read -r -p "Install Node.js? [y/N]: " want_node
  node_version=""
  if [[ "${want_node}" =~ ^[Yy] ]]; then
    read -r -p "  Node version [22]: " node_version
    node_version="${node_version:-22}"
  fi

  read -r -p "Install Java? [y/N]: " want_java
  java_version=""
  if [[ "${want_java}" =~ ^[Yy] ]]; then
    read -r -p "  Java version [17]: " java_version
    java_version="${java_version:-17}"
  fi

  mount_directories="[]"
  mount_index=0
  read -r -p "Add a bind mount? [y/N]: " add_mount
  while [[ "${add_mount}" =~ ^[Yy] ]]; do
    host_path=""
    while [ -z "${host_path}" ]; do
      if [ "${mount_index}" -eq 0 ]; then
        read -r -p "  Host path relative to the workspace [data]: " host_path
        host_path="${host_path:-data}"
      else
        read -r -p "  Host path relative to the workspace (required): " host_path
      fi
      if [ -z "${host_path}" ]; then
        echo "Host path cannot be blank." >&2
      elif [[ "${host_path}" = /* ]]; then
        echo "Host path must be relative to the workspace." >&2
        host_path=""
      fi
    done

    target_default=""
    if [ "${mount_index}" -eq 0 ]; then
      target_default=" [/workspace/data]"
    fi
    container_path=""
    while [ -z "${container_path}" ]; do
      read -r -p "  Container path (absolute)${target_default}: " container_path
      if [ -z "${container_path}" ] && [ "${mount_index}" -eq 0 ]; then
        container_path="/workspace/data"
      elif [[ "${container_path}" != /* ]]; then
        echo "Container path must be absolute." >&2
        container_path=""
      fi
    done

    read -r -p "  Mount read-only? [Y/n]: " readonly
    if [[ "${readonly}" =~ ^[Nn] ]]; then
      readonly="false"
    else
      readonly="true"
    fi
    mount_directories="$(jq -cn \
      --argjson mounts "${mount_directories}" \
      --arg source "${host_path}" \
      --arg target "${container_path}" \
      --argjson readonly "${readonly}" \
      '$mounts + [{source: $source, target: $target, readonly: $readonly}]')"
    mount_index=$((mount_index + 1))
    read -r -p "Add another bind mount? [y/N]: " add_mount
  done

  want_pnpm_enforce=""
  pnpm_npmrc_path=""
  if [[ "${want_node}" =~ ^[Yy] ]]; then
    read -r -p "Enforce pnpm over npm (installs age-eligible npm 11 + pnpm 12 and blocks npm install)? [y/N]: " want_pnpm_enforce
    if [[ "${want_pnpm_enforce}" =~ ^[Yy] ]]; then
      read -r -p "  Path to your project's .npmrc (registry + optional min-release-age): " pnpm_npmrc_path
    fi
  fi
  read -r -p "Hosts to null-route: comma-separated hostnames, or a path to a file (e.g. external/dev-container-config/examples/blockedRegistryHosts.txt), blank to skip: " blocked_hosts_raw
  blocked_hosts_is_file="false"
  if [ -n "${blocked_hosts_raw}" ] && [ -f "${blocked_hosts_raw}" ]; then
    blocked_hosts_is_file="true"
    blocked_hosts_raw="$(cd "$(dirname "${blocked_hosts_raw}")" && pwd)/$(basename "${blocked_hosts_raw}")"
  fi
  read -r -p "Extra --add-host entries, comma-separated host:value pairs (blank to skip): " extra_hosts_raw
  read -r -p "Additional files to copy into the image, comma-separated sourcePath:targetPath[:x] entries (x = make executable; blank to skip): " files_raw
  read -r -p "postCreateCommand (blank to skip): " post_create
  read -r -p "java.project.sourcePaths, comma-separated (blank to skip): " java_source_paths
  read -r -p "Extra VS Code extensions, comma-separated (blank to skip): " extensions_raw
  read -r -p "remoteEnv entries, comma-separated KEY=VALUE pairs e.g. PATH=\${containerEnv:PATH}:/some/dir (blank to skip): " remote_env_raw

  jq -n \
    --arg name "${name}" \
    --arg remoteUser "${remote_user}" \
    --arg cwd "$(pwd)" \
    --arg nodeVersion "${node_version}" \
    --arg javaVersion "${java_version}" \
    --argjson mountDirectories "${mount_directories}" \
    --arg wantPnpmEnforce "${want_pnpm_enforce}" \
    --arg pnpmNpmrcPath "${pnpm_npmrc_path}" \
    --arg blockedHostsRaw "${blocked_hosts_raw}" \
    --arg blockedHostsIsFile "${blocked_hosts_is_file}" \
    --arg extraHostsRaw "${extra_hosts_raw}" \
    --arg filesRaw "${files_raw}" \
    --arg postCreate "${post_create}" \
    --arg javaSourcePathsRaw "${java_source_paths}" \
    --arg extensionsRaw "${extensions_raw}" \
    --arg remoteEnvRaw "${remote_env_raw}" \
    -f "$(dirname "${BASH_SOURCE[0]}")/answers-interactive.jq" \
    >"${tmp}"

  printf '%s' "${tmp}"
}
