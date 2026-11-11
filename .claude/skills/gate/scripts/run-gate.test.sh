#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
# Regression suite for run-gate.sh. Run from any checkout: bash .claude/skills/gate/scripts/run-gate.test.sh
# A throwaway repository stands in for the project. Stub make is its gate: it prints "line 1" to
# "line <GATE_TEST_LINES>", then "gate exit <GATE_TEST_EXIT>" on stderr, exits with that status,
# and keeps the folder it ran in.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
export GATE_TEST_STATE="$WORK/state"
pass=0; fail=0

mkdir -p "$WORK/bin" "$GATE_TEST_STATE" "$WORK/tmp" "$WORK/elsewhere"
cat >"$WORK/bin/make" <<'EOF'
#!/usr/bin/env bash
[ "$*" = gate ] || exit 64
pwd -P >"$GATE_TEST_STATE/make.cwd"
seq "${GATE_TEST_LINES:-10}" | sed 's/^/line /'
echo "gate exit ${GATE_TEST_EXIT:-0}" >&2
exit "${GATE_TEST_EXIT:-0}"
EOF
chmod +x "$WORK/bin/make"
export PATH="$WORK/bin:$PATH"

REPO="$WORK/repo"
git init -q "$REPO"
mkdir -p "$REPO/sub"
echo a >"$REPO/a.txt"
echo b >"$REPO/sub/b.txt"
echo '*.log' >"$REPO/.gitignore"
git -C "$REPO" add -A
git -C "$REPO" -c user.name=t -c user.email=t@t commit -qm init

check() {  # check <desc> <command...>
  if "${@:2}" >/dev/null 2>&1; then pass=$((pass+1)); echo "PASS $1"
  else fail=$((fail+1)); echo "FAIL $1"; fi
}
# run-gate.sh run from <folder>, its temporary files in $WORK/tmp; stdout in $WORK/out, stderr in
# $WORK/err.
run_gate() {  # run_gate <folder> [<args>...]
  (cd "$1" && TMPDIR="$WORK/tmp" bash "$HERE/run-gate.sh" "${@:2}") >"$WORK/out" 2>"$WORK/err"
}
exits() {  # exits <status> <desc> <folder> [<args>...]
  run_gate "${@:3}"
  check "$2" test $? -eq "$1"
}
fingerprint() { run_gate "$1" --fingerprint && cat "$WORK/out"; }
warned() { grep -qxF -- "$1" "$WORK/err"; }  # warned <line>: the last run printed it on stderr
temp_files() { find "$WORK/tmp" -type f; }
numbered() { seq "$1" "$2" | sed 's/^/line /'; }  # numbered <from> <to>: the stub's lines

echo "-- usage"
exits 2 "an unknown argument is refused"           "$REPO" --verbose
check "with the usage line"                        grep -qE '^Usage: .*run-gate\.sh \[--fingerprint\]$' "$WORK/err"
exits 2 "--fingerprint takes no other argument"    "$REPO" --fingerprint extra
exits 2 "outside a Git worktree it refuses"        "$WORK/elsewhere"
check "and says so"                                warned 'Not inside a Git worktree.'

echo "-- --fingerprint: HEAD's tree plus every change git does not ignore"
FP="$(fingerprint "$REPO")"
check "a clean checkout's is HEAD's tree"          test "$FP" = "$(git -C "$REPO" rev-parse 'HEAD^{tree}')"
check "the same from a subfolder"                  test "$(fingerprint "$REPO/sub")" = "$FP"
echo changed >>"$REPO/a.txt"
check "an edited file changes it"                  test "$(fingerprint "$REPO")" != "$FP"
git -C "$REPO" checkout -q -- a.txt
check "undoing the edit gives it back"             test "$(fingerprint "$REPO")" = "$FP"
rm "$REPO/sub/b.txt"
check "a deleted file changes it"                  test "$(fingerprint "$REPO")" != "$FP"
git -C "$REPO" checkout -q -- sub/b.txt
echo new >"$REPO/new.txt"
check "a new file changes it"                      test "$(fingerprint "$REPO")" != "$FP"
check "and stays untracked: the real index is untouched" test "$(git -C "$REPO" status --porcelain)" = '?? new.txt'
rm "$REPO/new.txt"
echo log >"$REPO/run.log"
check "an ignored file leaves it"                  test "$(fingerprint "$REPO")" = "$FP"
check "no temporary index is left"                 test -z "$(temp_files)"

echo "-- a gate that passes"
exits 0 "exits 0"                                  "$REPO/sub"
check "make gate ran at the top of the worktree"   test "$(cat "$GATE_TEST_STATE/make.cwd")" = "$REPO"
check "it prints PASS, the tree and the log's last 8 lines, stderr among them" \
  test "$(sed 3d "$WORK/out")" = "$(printf '%s\n' 'Gate: PASS' "Tree: $FP"; numbered 4 10; echo 'gate exit 0')"
check "and, third, the duration"                   grep -qxE 'Duration: [0-9]+s' "$WORK/out"
check "the log is removed"                         test -z "$(temp_files)"

echo "-- a gate that fails"
GATE_TEST_EXIT=2 GATE_TEST_LINES=100 exits 2 "exits with make's status, 2 for a failed recipe" "$REPO"
LOG="$(sed -n 's/^Log: //p' "$WORK/out")"
check "it prints FAIL with that status, the tree and the log's path" \
  test "$(head -n 4 "$WORK/out")" = "$(printf '%s\n' 'Gate: FAIL (exit 2)' "Tree: $FP" "Log: $LOG" 'Failure output (last 80 lines):')"
check "the log is kept in TMPDIR"                  test "$(temp_files)" = "$LOG"
check "with all of make's output, stderr among it" test "$(cat "$LOG")" = "$(numbered 1 100; echo 'gate exit 2')"
check "then the log's last 80 lines"               test "$(tail -n +5 "$WORK/out")" = "$(tail -n 80 "$LOG")"
rm "$LOG"
GATE_TEST_EXIT=3 exits 3 "any other status of make passes through too" "$REPO"
rm "$(sed -n 's/^Log: //p' "$WORK/out")"

echo "-- no tree to fingerprint: a repository with no commit"
EMPTY="$WORK/empty"
git init -q "$EMPTY"
exits 2 "--fingerprint exits 2"                    "$EMPTY" --fingerprint
exits 2 "a gate that passed exits 2"               "$EMPTY"
check "it says why"                                warned 'Gate: FAIL (fingerprint unavailable)'
LOG="$(sed -n 's/^Log: //p' "$WORK/err")"
check "and keeps the log"                          test "$(temp_files)" = "$LOG"
check "whose last lines it prints"                 test "$(cat "$WORK/out")" = "$(cat "$LOG")"
rm "$LOG"
GATE_TEST_EXIT=3 exits 3 "a gate that failed keeps make's status" "$EMPTY"

echo "== $pass passed, $fail failed"
[ "$fail" -eq 0 ]
