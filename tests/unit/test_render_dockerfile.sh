#!/usr/bin/env bash
# Tests for lib/render-dockerfile.sh, focused on the dockerfileBuild.toolchains.pnpm wiring.

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
  assert_not_contains "${out}" "RUN corepack disable" "no actual corepack-disable RUN step"
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
