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
    --arg extensionsRaw "${EXTENSIONS_RAW:-}"
}

test_mount_directories_are_included_in_answers() {
  local out
  out="$(MOUNT_DIRECTORIES='[{"hostPath":"data","containerPath":"/workspace/data","readonly":true},{"hostPath":"../shared","containerPath":"/workspace/shared","readonly":false}]' _run_interactive_jq)"
  assert_equal "2" "$(printf '%s' "${out}" | jq '.mountDirectories | length')" "all interactive mounts are kept"
  assert_equal "../shared" "$(printf '%s' "${out}" | jq -r '.mountDirectories[1].hostPath')" "relative host path is kept"
  assert_equal "/workspace/shared" "$(printf '%s' "${out}" | jq -r '.mountDirectories[1].containerPath')" "container target is kept"
  assert_equal "false" "$(printf '%s' "${out}" | jq -r '.mountDirectories[1].readonly')" "read-write selection is kept"
}

test_no_mounts_omits_mount_directories() {
  local out
  out="$(_run_interactive_jq)"
  assert_equal "false" "$(printf '%s' "${out}" | jq 'has("mountDirectories")')" "mount configuration is omitted when no mounts are added"
}

test_pnpm_npmrc_path_wires_toolchain() {
  local out
  out="$(NODE_VERSION=22 WANT_PNPM_ENFORCE=y PNPM_NPMRC_PATH="./x.npmrc" _run_interactive_jq)"
  assert_equal "/cwd/./x.npmrc" "$(printf '%s' "${out}" | jq -r '.toolchains.pnpm.npmrcPath')" "project-relative npmrcPath remains absolute for resolving the temporary answers file"
}

test_pnpm_npmrc_path_bare_name_left_relative_to_submodule() {
  local out
  out="$(NODE_VERSION=22 WANT_PNPM_ENFORCE=y PNPM_NPMRC_PATH="examples/example.npmrc" _run_interactive_jq)"
  assert_equal "examples/example.npmrc" "$(printf '%s' "${out}" | jq -r '.toolchains.pnpm.npmrcPath')" "bare (non ./ ../) npmrcPath left untouched for submodule-root resolution"
}

test_blank_pnpm_npmrc_path_omits_toolchain() {
  local out
  out="$(NODE_VERSION=22 _run_interactive_jq)"
  assert_equal "null" "$(printf '%s' "${out}" | jq -r '.toolchains.pnpm // null')" "no pnpm toolchain when not requested"
}

test_files_entry_parses_executable_flag() {
  local out
  out="$(FILES_RAW="./foo.sh:/usr/local/bin/foo.sh:x, ./bar.conf:/etc/bar.conf" _run_interactive_jq)"
  assert_equal "/usr/local/bin/foo.sh" "$(printf '%s' "${out}" | jq -r '.files[0].targetPath')" "first entry targetPath"
  assert_equal "/cwd/./foo.sh" "$(printf '%s' "${out}" | jq -r '.files[0].sourcePath')" "first entry sourcePath made absolute against cwd"
  assert_equal "true" "$(printf '%s' "${out}" | jq -r '.files[0].executable')" "first entry executable=true"
  assert_equal "/cwd/./bar.conf" "$(printf '%s' "${out}" | jq -r '.files[1].sourcePath')" "second entry sourcePath made absolute against cwd"
  assert_equal "null" "$(printf '%s' "${out}" | jq -r '.files[1].executable // null')" "second entry executable omitted"
}

test_blank_files_raw_omits_files_key() {
  local out
  out="$(_run_interactive_jq)"
  assert_equal "false" "$(printf '%s' "${out}" | jq 'has("files")')" "no files key when filesRaw blank"
}
