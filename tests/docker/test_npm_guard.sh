#!/usr/bin/env bash
# Confirms templates/npm-guard.sh blocks npm install/ci shell-wide while
# letting other npm subcommands pass through, inside a real container.

test_npm_guard_blocks_install_and_ci_but_allows_other_commands() {
  local out blocked_count
  out="$(docker run --rm -v "${REPO_ROOT}/templates/npm-guard.sh:/npm-guard.sh:ro" node:22 bash -c '
    . /npm-guard.sh
    npm install
    npm ci
    npm --version
  ' 2>&1)"

  blocked_count="$(printf '%s\n' "${out}" | grep -c "\[BLOCKED\] This project uses pnpm")"
  assert_equal "2" "${blocked_count}" "npm install and npm ci both blocked"

  printf '%s\n' "${out}" | grep -E -q '^[0-9]+\.[0-9]+\.[0-9]+$'
  assert_equal "0" "$?" "npm --version still passes through"
}
