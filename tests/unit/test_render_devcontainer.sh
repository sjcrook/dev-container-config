#!/usr/bin/env bash
# Tests for lib/render-devcontainer.jq -- the auto-wired postCreateCommand.

_render() {
  bash "${REPO_ROOT}/lib/render-devcontainer.sh" "$1" "[]"
}

test_pnpm_auto_wires_post_create_command() {
  local tmp answers out
  tmp="$(mktemp -d)"
  answers="${tmp}/answers.json"
  echo 'registry=https://example.com/' > "${tmp}/x.npmrc"
  cat > "${answers}" <<'EOF'
{"schemaVersion":1,"name":"t","dockerfileBuild":{"toolchains":{"node":{"version":"22"},"pnpm":{"npmrcPath":"./x.npmrc"}}}}
EOF
  out="$(_render "${answers}")"
  rm -rf "${tmp}"
  assert_contains "${out}" "npm-guard.sh' >> ~/.bashrc" "auto npm-guard sourcing line present"
}

test_pnpm_merges_with_custom_post_create_command() {
  local tmp answers out pcc
  tmp="$(mktemp -d)"
  answers="${tmp}/answers.json"
  echo 'registry=https://example.com/' > "${tmp}/x.npmrc"
  cat > "${answers}" <<'EOF'
{"schemaVersion":1,"name":"t","dockerfileBuild":{"toolchains":{"node":{"version":"22"},"pnpm":{"npmrcPath":"./x.npmrc"}}},"postCreateCommand":"echo custom"}
EOF
  out="$(_render "${answers}")"
  rm -rf "${tmp}"
  pcc="$(printf '%s' "${out}" | jq -r '.postCreateCommand')"
  assert_contains "${pcc}" "npm-guard.sh' >> ~/.bashrc && echo custom" "guard line then custom command, in order"
}

test_no_pnpm_leaves_post_create_command_untouched() {
  local tmp answers out pcc
  tmp="$(mktemp -d)"
  answers="${tmp}/answers.json"
  cat > "${answers}" <<'EOF'
{"schemaVersion":1,"name":"t","postCreateCommand":"echo custom"}
EOF
  out="$(_render "${answers}")"
  rm -rf "${tmp}"
  pcc="$(printf '%s' "${out}" | jq -r '.postCreateCommand')"
  assert_equal "echo custom" "${pcc}" "postCreateCommand passthrough unchanged"
}

test_no_pnpm_no_post_create_omits_key() {
  local tmp answers out
  tmp="$(mktemp -d)"
  answers="${tmp}/answers.json"
  cat > "${answers}" <<'EOF'
{"schemaVersion":1,"name":"t"}
EOF
  out="$(_render "${answers}")"
  rm -rf "${tmp}"
  assert_equal "false" "$(printf '%s' "${out}" | jq 'has("postCreateCommand")')" "postCreateCommand key absent"
}

test_mounts_render_and_initialize_host_directories() {
  local tmp answers out
  tmp="$(mktemp -d)"
  answers="${tmp}/answers.json"
  cat > "${answers}" <<'EOF'
{"schemaVersion":1,"mounts":[{"source":"data","target":"/workspace/data","readonly":true},{"source":"../shared data","target":"/workspace/shared","readonly":false}]}
EOF
  out="$(_render "${answers}")"
  rm -rf "${tmp}"
  assert_equal "source=\${localWorkspaceFolder}/data,target=/workspace/data,type=bind,readonly" "$(printf '%s' "${out}" | jq -r '.mounts[0]')" "first mount keeps the read-only default"
  assert_equal "source=\${localWorkspaceFolder}/../shared data,target=/workspace/shared,type=bind" "$(printf '%s' "${out}" | jq -r '.mounts[1]')" "second mount uses its configured relative source and target"
  assert_contains "$(printf '%s' "${out}" | jq -r '.initializeCommand')" "'\${localWorkspaceFolder}/../shared data'" "initialize command safely quotes host paths"
}
