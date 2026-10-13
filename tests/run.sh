#!/usr/bin/env bash
# Test suite entry point.
#
# Usage: tests/run.sh [--no-docker]
#   unit/*.sh   -- fast, only need bash + jq. Always run.
#   docker/*.sh -- real `docker build`/`docker run` checks. Skipped
#                  automatically if docker is missing/not running, or if
#                  --no-docker is passed.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"
export REPO_ROOT

# shellcheck source=tests/lib/assert.sh
source "${TESTS_DIR}/lib/assert.sh"

RUN_DOCKER=1
[ "${1:-}" = "--no-docker" ] && RUN_DOCKER=0
if [ "${RUN_DOCKER}" = "1" ] && { ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; }; then
  RUN_DOCKER=0
fi

PASS_COUNT=0
FAIL_COUNT=0
FAILED_TESTS=()

# Sources a test file, then runs every function it defines named test_*,
# comparing ASSERT_FAILURES before/after to decide pass/fail.
run_test_file() {
  local file="$1" fn before
  # shellcheck source=/dev/null
  source "${file}"
  for fn in $(declare -F | awk '{print $3}' | grep '^test_'); do
    before="${ASSERT_FAILURES}"
    "${fn}"
    if [ "${ASSERT_FAILURES}" = "${before}" ]; then
      echo "PASS ${fn}"
      PASS_COUNT=$((PASS_COUNT + 1))
    else
      echo "FAIL ${fn}"
      FAIL_COUNT=$((FAIL_COUNT + 1))
      FAILED_TESTS+=("${fn}")
    fi
    unset -f "${fn}"
  done
}

echo "== unit tests =="
for f in "${TESTS_DIR}"/unit/test_*.sh; do
  run_test_file "${f}"
done

if [ "${RUN_DOCKER}" = "1" ]; then
  echo "== docker tests =="
  for f in "${TESTS_DIR}"/docker/test_*.sh; do
    run_test_file "${f}"
  done
else
  echo "== docker tests skipped (docker unavailable or --no-docker) =="
fi

echo
echo "${PASS_COUNT} passed, ${FAIL_COUNT} failed"
if [ "${FAIL_COUNT}" -gt 0 ]; then
  printf 'Failed: %s\n' "${FAILED_TESTS[@]}"
  exit 1
fi
exit 0
