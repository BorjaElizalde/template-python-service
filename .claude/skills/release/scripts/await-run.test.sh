#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
# Regression suite for await-run.sh. Run from any checkout: bash .claude/skills/release/scripts/await-run.test.sh
# Stub gh answers `gh run list` for the Deploy workflow on commit abc123: poll n prints line n of
# $AWAIT_TEST_STATE/ids, and the last line once past it; a line "error" fails as a network error
# does. `gh run watch` exits with $AWAIT_TEST_STATE/watch-exit. Stub sleep returns at once, and
# ends the script at its 20th call, so a script that would poll forever fails its case instead of
# hanging the suite. Each stub logs its call to $AWAIT_TEST_STATE/log.
# Bash takes SECONDS from the environment, so SECONDS=301 starts the script past its 300s grace.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
export AWAIT_TEST_STATE="$WORK/state"
pass=0; fail=0

mkdir -p "$WORK/bin" "$AWAIT_TEST_STATE"
cat >"$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >>"$AWAIT_TEST_STATE/log"
case "$*" in
  "run list --workflow Deploy --commit abc123 --limit 1 --json databaseId --jq .[0].databaseId")
    n=$(grep -c '^gh run list' "$AWAIT_TEST_STATE/log")
    last=$(wc -l <"$AWAIT_TEST_STATE/ids")
    id=$(sed -n "$((n < last ? n : last))p" "$AWAIT_TEST_STATE/ids")
    [ "$id" != error ] || { echo 'error connecting to api.github.com' >&2; exit 1; }
    echo "$id" ;;
  "run watch "*" --exit-status --interval 30") exit "$(cat "$AWAIT_TEST_STATE/watch-exit")" ;;
  *) exit 64 ;;
esac
EOF
cat >"$WORK/bin/sleep" <<'EOF'
#!/usr/bin/env bash
echo "sleep $*" >>"$AWAIT_TEST_STATE/log"
[ "$(grep -c '^sleep' "$AWAIT_TEST_STATE/log")" -lt 20 ] || kill "$PPID"
EOF
chmod +x "$WORK/bin/gh" "$WORK/bin/sleep"
export PATH="$WORK/bin:$PATH"

check() {  # check <desc> <command...>
  if "${@:2}" >/dev/null 2>&1; then pass=$((pass+1)); echo "PASS $1"
  else fail=$((fail+1)); echo "FAIL $1"; fi
}
# A fresh run of await-run.sh with <args>, gh answering <ids>, one per poll, and <watch exit>; its
# stderr in $WORK/err.
await_run() {  # await_run <ids> <watch exit> [<args>...]
  printf '%s\n' "$1" >"$AWAIT_TEST_STATE/ids"
  echo "$2" >"$AWAIT_TEST_STATE/watch-exit"
  : >"$AWAIT_TEST_STATE/log"
  bash "$HERE/await-run.sh" "${@:3}" >/dev/null 2>"$WORK/err"
}
exits() {  # exits <status> <desc> <await_run args...>
  await_run "${@:3}"
  check "$2" test $? -eq "$1"
}
logged() { grep -qxF -- "$1" "$AWAIT_TEST_STATE/log"; }
count() { grep -c -- "^$1" "$AWAIT_TEST_STATE/log"; }

echo "-- usage"
exits 2 "no argument is refused"                   4242 0
check "with the usage line"                        grep -q '^Usage: .*await-run\.sh <workflow-name> <commit-sha>$' "$WORK/err"
exits 2 "a workflow without a commit is refused"   4242 0 Deploy
check "and asks gh nothing"                        test "$(count gh)" -eq 0

echo "-- a run registered at once"
exits 0 "a run that succeeds exits 0"              4242 0 Deploy abc123
check "it watches that run, failing on its failure" logged 'gh run watch 4242 --exit-status --interval 30'
check "without a sleep before"                     test "$(count sleep)" -eq 0
exits 1 "a run that fails or is cancelled exits 1" 4242 1 Deploy abc123
exits 0 "started again, it watches the run anew"   4242 0 Deploy abc123
check "the same run"                               logged 'gh run watch 4242 --exit-status --interval 30'

echo "-- a run that registers late"
exits 0 "is watched once it shows"                 "$(printf '%s\n' '' null error 4242)" 0 Deploy abc123
check "after four polls"                           test "$(count 'gh run list')" -eq 4
check "15 seconds apart"                           test "$(count 'sleep 15$')" -eq 3
check "never read from an empty answer, null or an error" test "$(count 'gh run watch')" -eq 1

echo "-- no run within the grace window"
SECONDS=301 exits 2 "exits 2"                      '' 0 Deploy abc123
check "it names the workflow, the commit and the window" grep -qxF 'No Deploy run registered for abc123 within 300s.' "$WORK/err"
check "and watches nothing"                        test "$(count 'gh run watch')" -eq 0
SECONDS=301 exits 0 "a run that shows on that last poll is still watched" 4242 0 Deploy abc123

echo "== $pass passed, $fail failed"
[ "$fail" -eq 0 ]
