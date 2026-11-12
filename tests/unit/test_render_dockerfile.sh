#!/usr/bin/env bash
# Tests for lib/render-dockerfile.sh, focused on the dockerfileBuild.toolchains.pnpm wiring.

test_apt_packages_render_valid_package_names_and_qualifiers() {
  local tmp out
  tmp="$(mktemp -d)"
  printf '%s\n' '{"dockerfileBuild":{"aptPackages":["sshpass","libstdc++6","libc6:amd64=2.35-0ubuntu3.1","g++"]}}' >"${tmp}/answers.json"
  out="$(bash "${REPO_ROOT}/lib/render-dockerfile.sh" "${tmp}/answers.json")"
  assert_contains "${out}" "apt-get install -y sshpass" "sshpass installed at build time"
  assert_contains "${out}" "apt-get install -y libstdc++6" "plus signs allowed"
  assert_contains "${out}" "apt-get install -y libc6:amd64=2.35-0ubuntu3.1" "architecture and version allowed"
  assert_contains "${out}" "apt-get install -y g++" "compiler package allowed"
  rm -rf "${tmp}"
}

test_apt_packages_reject_invalid_entries_before_emitting_dockerfile() {
  local tmp packages out rc
  tmp="$(mktemp -d)"
  for packages in '["sshpass; echo bad"]' '["$(id)"]' '["--allow-unauthenticated"]' \
    '["sshpass rsync"]' '["sshpass\nRUN echo bad"]' '[""]' '[42]' \
    '["sshpass\n"]' '["sshpass",null]' '"sshpass"' '{}' 'false' 'true'; do
    jq -n --argjson packages "${packages}" '{dockerfileBuild:{aptPackages:$packages}}' >"${tmp}/answers.json"
    out="$(bash "${REPO_ROOT}/lib/render-dockerfile.sh" "${tmp}/answers.json" 2>&1)"
    rc=$?
    assert_equal "1" "${rc}" "invalid apt packages rejected: ${packages}"
    assert_contains "${out}" "aptPackages" "explicit apt package validation error"
    assert_not_contains "${out}" "FROM mcr.microsoft.com" "no Dockerfile emitted for invalid packages"
  done
  rm -rf "${tmp}"
}

test_omitted_or_empty_apt_packages_emit_no_install_block() {
  local tmp answers out
  tmp="$(mktemp -d)"
  for answers in '{}' '{"dockerfileBuild":{"aptPackages":[]}}'; do
    printf '%s\n' "${answers}" >"${tmp}/answers.json"
    out="$(bash "${REPO_ROOT}/lib/render-dockerfile.sh" "${tmp}/answers.json")"
    assert_not_contains "${out}" "Additional apt packages" "no apt installation when not requested"
  done
  rm -rf "${tmp}"
}

test_pnpm_without_node_fails() {
  local tmp answers out rc
  tmp="$(mktemp -d)"
  answers="${tmp}/answers.json"
  echo 'registry=https://example.com/' > "${tmp}/x.npmrc"
  cat > "${answers}" <<'EOF'
{"schemaVersion":1,"name":"t","dockerfileBuild":{"toolchains":{"pnpm":{"npmrcPath":"./x.npmrc"}}}}
EOF
  out="$(bash "${REPO_ROOT}/lib/render-dockerfile.sh" "${answers}" 2>&1)"
  rc=$?
  rm -rf "${tmp}"
  assert_equal "1" "${rc}" "pnpm-without-node exit code"
  assert_contains "${out}" "dockerfileBuild.toolchains.pnpm requires dockerfileBuild.toolchains.node" "pnpm-without-node error message"
}

test_pnpm_with_node_emits_toolchain_block() {
  local tmp answers out
  tmp="$(mktemp -d)"
  answers="${tmp}/answers.json"
  echo 'registry=https://example.com/' > "${tmp}/x.npmrc"
  cat > "${answers}" <<'EOF'
{"schemaVersion":1,"name":"t","dockerfileBuild":{"toolchains":{"node":{"version":"22"},"pnpm":{"npmrcPath":"./x.npmrc"}}}}
EOF
  out="$(bash "${REPO_ROOT}/lib/render-dockerfile.sh" "${answers}")"
  rm -rf "${tmp}"
  assert_contains "${out}" "COPY .npmrc /root/.npmrc" "copies npmrc"
  assert_contains "${out}" "COPY install-pnpm.sh /usr/local/bin/install-pnpm.sh" "copies install-pnpm.sh"
  assert_contains "${out}" "COPY npm-guard.sh /etc/profile.d/npm-guard.sh" "copies npm-guard.sh"
  assert_contains "${out}" "COPY pnpm-config.yaml /root/.config/pnpm/config.yaml" "build policy configured"
  assert_contains "${out}" 'cp /root/.npmrc "$home/.npmrc"' "runtime registry configured"
  assert_contains "${out}" 'cp /root/.config/pnpm/config.yaml "$home/.config/pnpm/config.yaml"' "runtime policy configured"
  assert_contains "${out}" 'ENV PATH="/opt/devcontainer/bin:${PATH}"' "global CLI PATH available outside VS Code"
  assert_contains "${out}" "NPM_VERSION=11 PNPM_VERSION=12" "supported default majors"
  assert_not_contains "${out}" "RUN corepack disable" "no actual corepack-disable RUN step"
}

test_package_manager_versions_are_consumer_selectable() {
  local tmp out
  tmp="$(mktemp -d)"
  echo '{"remoteUser":"coder","dockerfileBuild":{"toolchains":{"node":{"version":"24"},"pnpm":{"npmrcPath":"./x","npmVersion":"12.2.0","version":"12.11.2"}}}}' > "${tmp}/answers.json"
  out="$(bash "${REPO_ROOT}/lib/render-dockerfile.sh" "${tmp}/answers.json")"
  assert_contains "${out}" "NPM_VERSION=12.2.0 PNPM_VERSION=12.11.2" "exact selections rendered"
  assert_contains "${out}" "getent passwd coder" "configured user home resolved"
  rm -rf "${tmp}"
}

test_pnpm_rejects_unsupported_or_unsafe_selections() {
  local tmp options out rc
  tmp="$(mktemp -d)"
  for options in '{"version":"11"}' '{"npmVersion":"latest"}' '{"version":"12;echo bad"}'; do
    jq -n --argjson options "${options}" \
      '{dockerfileBuild:{toolchains:{node:{version:"22"},pnpm:({npmrcPath:"./x"} + $options)}}}' > "${tmp}/answers.json"
    out="$(bash "${REPO_ROOT}/lib/render-dockerfile.sh" "${tmp}/answers.json" 2>&1)"
    rc=$?
    assert_equal "1" "${rc}" "invalid version rejected"
    assert_contains "${out}" "ERROR:" "explicit selection error"
  done
  rm -rf "${tmp}"
}

test_no_pnpm_omits_toolchain_block() {
  local tmp answers out
  tmp="$(mktemp -d)"
  answers="${tmp}/answers.json"
  cat > "${answers}" <<'EOF'
{"schemaVersion":1,"name":"t","dockerfileBuild":{"toolchains":{"node":{"version":"22"}}}}
EOF
  out="$(bash "${REPO_ROOT}/lib/render-dockerfile.sh" "${answers}")"
  rm -rf "${tmp}"
  assert_not_contains "${out}" "install-pnpm.sh" "no pnpm wiring when dockerfileBuild.toolchains.pnpm absent"
}
