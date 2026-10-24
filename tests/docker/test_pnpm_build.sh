#!/usr/bin/env bash

test_bootstrap_selection_rejects_recent_missing_and_incompatible_versions() {
  local out rc
  out="$(docker run --rm \
    -v "${REPO_ROOT}/templates/install-package-manager.cjs:/installer.cjs:ro" \
    -v "${REPO_ROOT}/tests/docker/bootstrap-fixture.cjs:/fixture.cjs:ro" \
    node:22 node /fixture.cjs 2>&1)"
  rc=$?
  assert_equal "0" "${rc}" "bootstrap fixture succeeds: ${out}"
  assert_contains "${out}" "bootstrap assertions passed" "selection and explicit errors verified"
}

test_runtime_policy_resolves_global_and_project_dependencies() {
  if [ -z "${DCC_TEST_IMAGE:-}" ]; then
    echo "    SKIP: set DCC_TEST_IMAGE to a generated image with 14-day/ignore-scripts policy" >&2
    return 0
  fi
  local out rc
  out="$(docker run --rm --user vscode --workdir /tmp \
    -v "${REPO_ROOT}/tests/docker/runtime-fixture.cjs:/runtime-fixture.cjs:ro" \
    "${DCC_TEST_IMAGE}" node /runtime-fixture.cjs 2>&1)"
  rc=$?
  assert_equal "0" "${rc}" "runtime fixture succeeds: ${out}"
  assert_contains "${out}" "runtime assertions passed" "global and nested-project behavior verified"
}
