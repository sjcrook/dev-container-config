#!/usr/bin/env bash

test_corporate_policy_translates_without_duplicate_answers() {
  local out
  out="$(printf '%s\r\n' '# corporate' ' registry = https://example.com/ ' 'min-release-age=14' 'ignore-scripts=true' 'strict-ssl=true' 'verify-deps-before-run=never' |
    jq -Rs -f "${REPO_ROOT}/lib/npm-policy.jq")"
  assert_equal "20160" "$(echo "${out}" | jq -r .minimumReleaseAge)" "14 days becomes 20160 minutes"
  assert_equal "true" "$(echo "${out}" | jq -r .ignoreScripts)" "scripts disabled"
  assert_equal "true" "$(echo "${out}" | jq -r .strictSsl)" "TLS policy translated"
  assert_equal "false" "$(echo "${out}" | jq -r .verifyDepsBeforeRun)" "legacy never translates to false"
  assert_equal "false" "$(echo "${out}" | jq -r .minimumReleaseAgeIgnoreMissingTime)" "missing timestamps not exempt"
}

test_corporate_policy_rejects_invalid_values_and_literal_secrets() {
  local line rc out
  for line in 'min-release-age=-1' 'min-release-age=oops' 'ignore-scripts=yes' \
    'strict-ssl=nope' 'verify-deps-before-run=oops' '//example.com/:_authToken=secret' \
    'registry=https://user:secret@example.com/' 'malformed'; do
    out="$(printf '%s\n' 'registry=https://example.com/' "${line}" |
      jq -Rs -f "${REPO_ROOT}/lib/npm-policy.jq" 2>&1)"
    rc=$?
    assert_equal "5" "${rc}" "invalid policy rejected: ${line%%=*}"
    assert_contains "${out}" "error" "explicit diagnostic"
  done
}

test_corporate_policy_requires_a_registry() {
  local out rc
  out="$(printf '%s\n' 'min-release-age=14' | jq -Rs -f "${REPO_ROOT}/lib/npm-policy.jq" 2>&1)"
  rc=$?
  assert_equal "5" "${rc}" "missing registry rejected"
  assert_contains "${out}" "requires registry=" "missing registry diagnostic"
}

test_corporate_policy_preserves_missing_policy_defaults_and_env_auth() {
  local out
  out="$(printf '%s\n' 'registry=https://example.com/' '//example.com/:_authToken=${NPM_TOKEN}' |
    jq -Rs -f "${REPO_ROOT}/lib/npm-policy.jq")"
  assert_equal "0" "$(echo "${out}" | jq -r .minimumReleaseAge)" "absent age remains zero"
  assert_equal "false" "$(echo "${out}" | jq -r .ignoreScripts)" "absent script policy matches npm default"
}
