#!/usr/bin/env bash
# Builds the generated Dockerfile against a local fake registry to exercise
# install-pnpm.sh's .npmrc parsing + min-release-age version selection for
# real (not just by reading the source). Requires docker and python3.
#
# The final `npm install -g pnpm@<version>` step is expected to fail here --
# the fake registry has no real tarballs. That's fine; this test only checks
# that the right version was *selected* before that point.

test_pnpm_build_selects_eligible_version() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "    SKIP: python3 not available" >&2
    return 0
  fi

  local tmp image server_pid log
  tmp="$(mktemp -d)"
  image="dcc-test-pnpm-build-$$"

  # Dates computed relative to "now" so this test doesn't rot: one version
  # just inside the gate (too new, must be excluded), one well past it.
  local recent old
  recent="$(python3 -c "import datetime; print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(days=1)).strftime('%Y-%m-%dT%H:%M:%S.000Z'))")"
  old="$(python3 -c "import datetime; print((datetime.datetime.now(datetime.timezone.utc)-datetime.timedelta(days=40)).strftime('%Y-%m-%dT%H:%M:%S.000Z'))")"

  mkdir -p "${tmp}/fake-registry"
  cat > "${tmp}/fake-registry/pnpm" <<EOF
{"time":{"9.9.9":"${recent}","9.9.8":"${old}"}}
EOF
  python3 -m http.server 8787 --directory "${tmp}/fake-registry" >/dev/null 2>&1 &
  server_pid=$!

  cat > "${tmp}/test.npmrc" <<'EOF'
registry=http://host.docker.internal:8787/
min-release-age=30
EOF
  cat > "${tmp}/answers.json" <<'EOF'
{"schemaVersion":2,"name":"t","dockerfileBuild":{"toolchains":{"node":{"version":"22"},"pnpm":{"npmrcPath":"./test.npmrc"}}}}
EOF
  bash "${REPO_ROOT}/generate.sh" --answers "${tmp}/answers.json" --out-dir "${tmp}/.devcontainer" >/dev/null

  log="$(docker build --add-host host.docker.internal:host-gateway -t "${image}" "${tmp}/.devcontainer" 2>&1)"

  kill "${server_pid}" 2>/dev/null
  wait "${server_pid}" 2>/dev/null
  docker rmi "${image}" >/dev/null 2>&1
  rm -rf "${tmp}"

  assert_contains "${log}" "Selected pnpm@9.9.8" "picks newest version past the min-release-age gate"
  assert_not_contains "${log}" "Selected pnpm@9.9.9" "excludes version newer than the gate"
}
