#!/usr/bin/env bash
# Tests for lib/files.sh -- path resolution and the pnpm_copy_files helper.
# Each call is wrapped in a subshell (via command substitution) so files.sh's
# own `set -euo pipefail` can't leak into this test runner's shell.

_resolve() {
  (source "${REPO_ROOT}/lib/files.sh" && resolve_submodule_path "$1" "$2" "$3")
}

_pnpm_copy() {
  (source "${REPO_ROOT}/lib/files.sh" && pnpm_copy_files "$1" "$2" "$3")
}

_files_copy_all() {
  (source "${REPO_ROOT}/lib/files.sh" && files_copy_all "$1" "$2" "$3")
}

test_resolve_submodule_path_variants() {
  assert_equal "/abs/path" "$(_resolve "/abs/path" "/answers" "/submodule")" "absolute passthrough"
  assert_equal "/answers/./foo" "$(_resolve "./foo" "/answers" "/submodule")" "dot-relative to answers dir"
  assert_equal "/answers/../foo" "$(_resolve "../foo" "/answers" "/submodule")" "dotdot-relative to answers dir"
  assert_equal "/submodule/templates/x.sh" "$(_resolve "templates/x.sh" "/answers" "/submodule")" "bare path relative to submodule root"
}

test_pnpm_copy_files_missing_npmrc_errors() {
  local tmp answers out_dir out rc
  tmp="$(mktemp -d)"
  answers="${tmp}/answers.json"
  out_dir="${tmp}/out"
  mkdir -p "${out_dir}"
  cat > "${answers}" <<'EOF'
{"schemaVersion":1,"name":"t","dockerfileBuild":{"toolchains":{"node":{"version":"22"},"pnpm":{"npmrcPath":"./missing.npmrc"}}}}
EOF
  out="$(_pnpm_copy "${answers}" "${REPO_ROOT}" "${out_dir}" 2>&1)"
  rc=$?
  rm -rf "${tmp}"
  assert_equal "1" "${rc}" "missing npmrc exit code"
  assert_contains "${out}" "dockerfileBuild.toolchains.pnpm.npmrcPath not found" "missing npmrc error message"
}

test_pnpm_copy_files_copies_expected_files() {
  local tmp answers out_dir
  tmp="$(mktemp -d)"
  answers="${tmp}/answers.json"
  out_dir="${tmp}/out"
  mkdir -p "${out_dir}"
  echo 'registry=https://example.com/' > "${tmp}/x.npmrc"
  cat > "${answers}" <<'EOF'
{"schemaVersion":1,"name":"t","dockerfileBuild":{"toolchains":{"node":{"version":"22"},"pnpm":{"npmrcPath":"./x.npmrc"}}}}
EOF
  _pnpm_copy "${answers}" "${REPO_ROOT}" "${out_dir}" >/dev/null

  [ -f "${out_dir}/.npmrc" ]; assert_equal "0" "$?" ".npmrc copied"
  [ -f "${out_dir}/install-pnpm.sh" ]; assert_equal "0" "$?" "install-pnpm.sh copied"
  [ -f "${out_dir}/npm-guard.sh" ]; assert_equal "0" "$?" "npm-guard.sh copied"
  rm -rf "${tmp}"
}

test_files_copy_all_noop_when_files_empty() {
  # Regression test: on macOS's /bin/bash (3.2), expanding "${entries[@]}" on
  # an empty array under `set -u` raises "unbound variable". This must not
  # crash when files[] is empty/absent.
  local tmp answers out_dir rc
  tmp="$(mktemp -d)"
  answers="${tmp}/answers.json"
  out_dir="${tmp}/out"
  mkdir -p "${out_dir}"
  echo '{"schemaVersion":1,"name":"t"}' > "${answers}"
  _files_copy_all "${answers}" "${REPO_ROOT}" "${out_dir}" >/dev/null
  rc=$?
  rm -rf "${tmp}"
  assert_equal "0" "${rc}" "files_copy_all succeeds when files[] is absent"
}

test_files_copy_all_copies_expected_file() {
  local tmp answers out_dir
  tmp="$(mktemp -d)"
  answers="${tmp}/answers.json"
  out_dir="${tmp}/out"
  mkdir -p "${out_dir}"
  echo 'hello' > "${tmp}/myfile.txt"
  cat > "${answers}" <<'EOF'
{"schemaVersion":1,"name":"t","dockerfileBuild":{"files":[{"sourcePath":"./myfile.txt","targetPath":"myfile.txt"}]}}
EOF
  _files_copy_all "${answers}" "${REPO_ROOT}" "${out_dir}" >/dev/null
  [ -f "${out_dir}/myfile.txt" ]; assert_equal "0" "$?" "myfile.txt copied"
  rm -rf "${tmp}"
}

test_pnpm_copy_files_noop_when_not_set() {
  local tmp answers out_dir count
  tmp="$(mktemp -d)"
  answers="${tmp}/answers.json"
  out_dir="${tmp}/out"
  mkdir -p "${out_dir}"
  cat > "${answers}" <<'EOF'
{"schemaVersion":1,"name":"t"}
EOF
  _pnpm_copy "${answers}" "${REPO_ROOT}" "${out_dir}" >/dev/null
  count="$(find "${out_dir}" -type f | wc -l | tr -d ' ')"
  rm -rf "${tmp}"
  assert_equal "0" "${count}" "no files copied when dockerfileBuild.toolchains.pnpm absent"
}
