#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
set -u -o pipefail

gate_repo=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'Not inside a Git worktree.\n' >&2
  exit 2
}
cd "$gate_repo" || exit 2

tree_fingerprint() {
  local gate_index gate_tree
  gate_index=$(mktemp "${TMPDIR:-/tmp}/gate-index.XXXXXX") || return 2
  rm -f "$gate_index"

  if ! GIT_INDEX_FILE="$gate_index" git read-tree HEAD \
    || ! GIT_INDEX_FILE="$gate_index" git add --all \
    || ! gate_tree=$(GIT_INDEX_FILE="$gate_index" git write-tree); then
    rm -f "$gate_index"
    return 2
  fi

  rm -f "$gate_index"
  printf '%s\n' "$gate_tree"
}

if [[ "${1:-}" == "--fingerprint" ]]; then
  if [[ $# -ne 1 ]]; then
    printf 'Usage: %s [--fingerprint]\n' "$0" >&2
    exit 2
  fi
  tree_fingerprint
  exit
fi

if [[ $# -ne 0 ]]; then
  printf 'Usage: %s [--fingerprint]\n' "$0" >&2
  exit 2
fi

gate_tmp_root=${TMPDIR:-/tmp}
gate_log=$(mktemp "${gate_tmp_root%/}/gate.XXXXXX") || exit 2
gate_started=$(date +%s)
make gate >"$gate_log" 2>&1
gate_status=$?
gate_finished=$(date +%s)
if ! gate_tree=$(tree_fingerprint); then
  printf 'Gate: FAIL (fingerprint unavailable)\nLog: %s\n' "$gate_log" >&2
  tail -n 80 "$gate_log"
  [[ $gate_status -ne 0 ]] && exit "$gate_status"
  exit 2
fi

if [[ $gate_status -eq 0 ]]; then
  printf 'Gate: PASS\nTree: %s\nDuration: %ss\n' \
    "$gate_tree" "$((gate_finished - gate_started))"
  tail -n 8 "$gate_log"
  rm -f "$gate_log"
  exit 0
fi

printf 'Gate: FAIL (exit %s)\nTree: %s\nLog: %s\nFailure output (last 80 lines):\n' \
  "$gate_status" "$gate_tree" "$gate_log"
tail -n 80 "$gate_log"
exit "$gate_status"
