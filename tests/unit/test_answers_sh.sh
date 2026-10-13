#!/usr/bin/env bash
# Tests for lib/answers.sh -- specifically that variables only assigned inside
# conditional branches (e.g. want_pnpm_enforce, gated on wanting Node) are
# still initialized on the path where that branch is skipped, so `set -u`
# doesn't blow up when they're referenced later in the jq --arg list.

test_interactive_answers_survive_declining_everything() {
  local tmp_home out rc
  tmp_home="$(mktemp -d)"
  # Project name, remote user, Node?, Java?, data mount?, hosts, extra hosts,
  # files, postCreateCommand, java source paths, extensions -- all blank/"n".
  # Piped directly (not via "$(...)") so trailing blank lines survive --
  # command substitution strips trailing newlines and would truncate stdin.
  out="$(printf '\n\n\nn\nn\nn\n\n\n\n\n\n\n' | TMPDIR="${tmp_home}" bash -c "source '${REPO_ROOT}/lib/answers.sh' && answers_collect_interactive" 2>&1)"
  rc=$?
  rm -rf "${tmp_home}"
  assert_equal "0" "${rc}" "declining Node/Java/mounts/pnpm doesn't crash"
  assert_not_contains "${out}" "unbound variable" "no unbound variable errors"
}
