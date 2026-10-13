#!/usr/bin/env bash
# Minimal, dependency-free assertion helpers for tests/run.sh.
# Failures are counted in ASSERT_FAILURES rather than aborting the test file,
# so one bad assertion doesn't hide the rest of a test's results.

ASSERT_FAILURES=0

assert_equal() {
  local expected="$1" actual="$2" label="${3:-assert_equal}"
  if [ "${expected}" != "${actual}" ]; then
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
    echo "    FAIL ${label}: expected [${expected}] got [${actual}]" >&2
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" label="${3:-assert_contains}"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
    echo "    FAIL ${label}: expected to find [${needle}]" >&2
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" label="${3:-assert_not_contains}"
  if [[ "${haystack}" == *"${needle}"* ]]; then
    ASSERT_FAILURES=$((ASSERT_FAILURES + 1))
    echo "    FAIL ${label}: expected NOT to find [${needle}]" >&2
  fi
}
