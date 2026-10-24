#!/usr/bin/env bash
# Tests for lib/answers-interactive.jq -- the interactive-prompt -> answers.json shape.

# Fills in blank defaults for every arg the filter expects; override via env
# vars before calling (e.g. NODE_VERSION=22 _run_interactive_jq).
_run_interactive_jq() {
  jq -n -f "${REPO_ROOT}/lib/answers-interactive.jq" \
    --arg name "${NAME:-x}" \
    --arg remoteUser "${REMOTE_USER:-vscode}" \
    --arg cwd "${CWD:-/cwd}" \
    --arg nodeVersion "${NODE_VERSION:-}" \
    --arg javaVersion "${JAVA_VERSION:-}" \
    --argjson mountDirectories "${MOUNT_DIRECTORIES:-[]}" \
    --arg wantPnpmEnforce "${WANT_PNPM_ENFORCE:-n}" \
    --arg pnpmNpmrcPath "${PNPM_NPMRC_PATH:-}" \
    --arg blockedHostsRaw "${BLOCKED_HOSTS_RAW:-}" \
    --arg blockedHostsIsFile "${BLOCKED_HOSTS_IS_FILE:-false}" \
    --arg extraHostsRaw "${EXTRA_HOSTS_RAW:-}" \
    --arg filesRaw "${FILES_RAW:-}" \
    --arg postCreate "${POST_CREATE:-}" \
    --arg javaSourcePathsRaw "${JAVA_SRC_RAW:-}" \
    --arg extensionsRaw "${EXTENSIONS_RAW:-}" \
    --arg remoteEnvRaw "${REMOTE_ENV_RAW:-}"
}

test_mount_directories_are_included_in_answers() {
  local out
  out="$(MOUNT_DIRECTORIES='[{"source":"data","target":"/workspace/data","readonly":true},{"source":"../shared","target":"/workspace/shared","readonly":false}]' _run_interactive_jq)"
  assert_equal "2" "$(printf '%s' "${out}" | jq '.mounts | length')" "all interactive mounts are kept"
  assert_equal "../shared" "$(printf '%s' "${out}" | jq -r '.mounts[1].source')" "relative host path is kept"
  assert_equal "/workspace/shared" "$(printf '%s' "${out}" | jq -r '.mounts[1].target')" "container target is kept"
  assert_equal "false" "$(printf '%s' "${out}" | jq -r '.mounts[1].readonly')" "read-write selection is kept"
}

test_no_mounts_omits_mount_directories() {
  local out
  out="$(_run_interactive_jq)"
  assert_equal "false" "$(printf '%s' "${out}" | jq 'has("mounts")')" "mount configuration is omitted when no mounts are added"
}

test_pnpm_npmrc_path_wires_toolchain() {
  local out
  out="$(NODE_VERSION=22 WANT_PNPM_ENFORCE=y PNPM_NPMRC_PATH="./x.npmrc" _run_interactive_jq)"
  assert_equal "/cwd/./x.npmrc" "$(printf '%s' "${out}" | jq -r '.dockerfileBuild.toolchains.pnpm.npmrcPath')" "project-relative npmrcPath remains absolute for resolving the temporary answers file"
}

test_pnpm_npmrc_path_bare_name_left_relative_to_submodule() {
  local out
  out="$(NODE_VERSION=22 WANT_PNPM_ENFORCE=y PNPM_NPMRC_PATH="examples/example.npmrc" _run_interactive_jq)"
  assert_equal "examples/example.npmrc" "$(printf '%s' "${out}" | jq -r '.dockerfileBuild.toolchains.pnpm.npmrcPath')" "bare (non ./ ../) npmrcPath left untouched for submodule-root resolution"
}

test_blank_pnpm_npmrc_path_omits_toolchain() {
  local out
  out="$(NODE_VERSION=22 _run_interactive_jq)"
  assert_equal "null" "$(printf '%s' "${out}" | jq -r '.dockerfileBuild.toolchains.pnpm // null')" "no pnpm toolchain when not requested"
}

test_files_entry_parses_executable_flag() {
  local out
  out="$(FILES_RAW="./foo.sh:/usr/local/bin/foo.sh:x, ./bar.conf:/etc/bar.conf" _run_interactive_jq)"
  assert_equal "/usr/local/bin/foo.sh" "$(printf '%s' "${out}" | jq -r '.dockerfileBuild.files[0].targetPath')" "first entry targetPath"
  assert_equal "/cwd/./foo.sh" "$(printf '%s' "${out}" | jq -r '.dockerfileBuild.files[0].sourcePath')" "first entry sourcePath made absolute against cwd"
  assert_equal "true" "$(printf '%s' "${out}" | jq -r '.dockerfileBuild.files[0].executable')" "first entry executable=true"
  assert_equal "/cwd/./bar.conf" "$(printf '%s' "${out}" | jq -r '.dockerfileBuild.files[1].sourcePath')" "second entry sourcePath made absolute against cwd"
  assert_equal "null" "$(printf '%s' "${out}" | jq -r '.dockerfileBuild.files[1].executable // null')" "second entry executable omitted"
}

test_blank_files_raw_omits_files_key() {
  local out
  out="$(_run_interactive_jq)"
  assert_equal "false" "$(printf '%s' "${out}" | jq 'has("dockerfileBuild")')" "no dockerfileBuild key when nothing requested"
}

test_remote_env_entries_parsed() {
  local out
  out="$(REMOTE_ENV_RAW="PATH=/opt/tools/bin, FOO=bar" _run_interactive_jq)"
  assert_equal "/opt/tools/bin" "$(printf '%s' "${out}" | jq -r '.remoteEnv.PATH')" "PATH entry parsed"
  assert_equal "bar" "$(printf '%s' "${out}" | jq -r '.remoteEnv.FOO')" "second entry parsed"
}

test_blank_remote_env_raw_omits_key() {
  local out
  out="$(_run_interactive_jq)"
  assert_equal "false" "$(printf '%s' "${out}" | jq 'has("remoteEnv")')" "no remoteEnv key when blank"
}
