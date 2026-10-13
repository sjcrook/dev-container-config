#!/usr/bin/env bash
# Verifies that interactive path inputs are saved relative to the durable
# answers file, while still being resolved correctly during generation.

test_interactive_paths_saved_relative_to_answers_file() {
  local tmp project out regenerated npmrc_path blocked_hosts_file rendered_config
  tmp="$(mktemp -d)"
  project="${tmp}/project"
  mkdir -p "${project}"
  printf 'registry=https://registry.example/\n' >"${project}/.npmrc"
  printf 'registry.example\n' >"${project}/blocked-hosts.txt"

  out="$(
    cd "${project}" &&
      printf '%s\n' "" "" "y" "" "n" "y" "data" "" "" "y" "../shared" "/workspace/shared" "n" "n" "y" "../project/.npmrc" "./blocked-hosts.txt" "" "" "" "" "" |
      TMPDIR="${tmp}" bash "${REPO_ROOT}/generate.sh" --out-dir .devcontainer 2>&1
  )"
  npmrc_path="$(jq -r '.toolchains.pnpm.npmrcPath' "${project}/.devcontainer/devcontainer.answers.json")"
  blocked_hosts_file="$(jq -r '.blockedRegistryHostsFile' "${project}/.devcontainer/devcontainer.answers.json")"

  assert_equal "2" "$(jq '.mountDirectories | length' "${project}/.devcontainer/devcontainer.answers.json")" "interactive answers save multiple mounts"
  assert_equal "../shared" "$(jq -r '.mountDirectories[1].hostPath' "${project}/.devcontainer/devcontainer.answers.json")" "interactive answers save relative host path"
  assert_equal "false" "$(jq -r '.mountDirectories[1].readonly' "${project}/.devcontainer/devcontainer.answers.json")" "interactive answers save read-write selection"
  rendered_config="$(bash "${REPO_ROOT}/lib/render-devcontainer.sh" "${project}/.devcontainer/devcontainer.answers.json" '[]')"
  assert_equal "2" "$(printf '%s' "${rendered_config}" | jq '.mounts | length')" "generated devcontainer includes both mounts"
  assert_contains "$(printf '%s' "${rendered_config}" | jq -r '.mounts[1]')" "source=\${localWorkspaceFolder}/../shared,target=/workspace/shared,type=bind" "generated mount uses workspace-relative source and selected target"
  assert_not_contains "$(printf '%s' "${rendered_config}" | jq -r '.mounts[1]')" ",readonly" "read-write choice is rendered"

  assert_equal "../.npmrc" "${npmrc_path}" "saved npmrc path is relative to the answers file"
  assert_equal "../blocked-hosts.txt" "${blocked_hosts_file}" "saved blocked-hosts path is relative to the answers file"
  assert_contains "${out}" "Wrote .devcontainer/.npmrc" "interactive generation resolves and copies the npmrc"
  assert_equal "0" "$([ -f "${project}/.devcontainer/.npmrc" ] && echo 0 || echo 1)" "generated npmrc exists"
  assert_equal "0" "$([ -f "${project}/.devcontainer/devcontainer.json" ] && echo 0 || echo 1)" "devcontainer generation succeeds"

  regenerated="$(
    cd "${project}" &&
      bash "${REPO_ROOT}/generate.sh" --answers .devcontainer/devcontainer.answers.json --out-dir .devcontainer --force 2>&1
  )"
  assert_contains "${regenerated}" "Done." "saved relative paths resolve on a later generation"

  rm -rf "${tmp}"
}
