#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
# Regression suite for await-checks.sh. Run from any checkout: bash .claude/skills/release/scripts/await-checks.test.sh
# Stub gh answers `gh pr checks` for PR 7: poll n prints line n of $AWAIT_TEST_STATE/checks, and the
# last line once past it. Like gh, it exits 8 while a check is pending and 1 once one failed; a line
# "error" fails as a network error does. Stub sleep returns at once, and ends the script at its 20th
# call, so a script that would poll forever fails its case instead of hanging the suite. Each stub
# logs its call to $AWAIT_TEST_STATE/log.
# Bash takes SECONDS from the environment, so SECONDS=301 starts the script past its 300s grace,
# and SECONDS=3601 past its one-hour deadline.
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
[ "$*" = "pr checks 7 --json name,bucket,link" ] || exit 64
n=$(grep -c '^gh ' "$AWAIT_TEST_STATE/log")
last=$(wc -l <"$AWAIT_TEST_STATE/checks")
answer=$(sed -n "$((n < last ? n : last))p" "$AWAIT_TEST_STATE/checks")
[ "$answer" != error ] || { echo 'error connecting to api.github.com' >&2; exit 1; }
echo "$answer"
case "$answer" in
  *'"pending"'*) exit 8 ;;
  *'"fail"'* | *'"cancel"'*) exit 1 ;;
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
# A fresh run of await-checks.sh with <args>, gh answering <answers>, one per poll; its stdout in
# $WORK/out, its stderr in $WORK/err.
await_checks() {  # await_checks <answers> [<args>...]
  printf '%s\n' "$1" >"$AWAIT_TEST_STATE/checks"
  : >"$AWAIT_TEST_STATE/log"
  bash "$HERE/await-checks.sh" "${@:2}" >"$WORK/out" 2>"$WORK/err"
}
exits() {  # exits <status> <desc> <await_checks args...>
  await_checks "${@:3}"
  check "$2" test $? -eq "$1"
}
count() { grep -c -- "^$1" "$AWAIT_TEST_STATE/log"; }
printed() { test "$(cat "$WORK/out")" = "$(printf '%s\n' "$@")"; }  # printed <line>...: all it printed
answer() {  # answer <name>:<bucket>...: gh's JSON for those checks, each linking to https://ci/<name>
  jq -nc '[$ARGS.positional[] | split(":") | {name: .[0], bucket: .[1], link: "https://ci/\(.[0])"}]' --args "$@"
}
TAB=$'\t'
GREEN="$(answer gate:pass docs:skipping)"
PENDING="$(answer gate:pending docs:skipping)"

echo "-- usage"
exits 2 "no PR is refused"                         "$GREEN"
check "with the usage line"                        grep -q '^Usage: .*await-checks\.sh <pr-number>$' "$WORK/err"
check "and asks gh nothing"                        test "$(count gh)" -eq 0

echo "-- checks already done"
exits 0 "passed or skipped exits 0"                "$GREEN" 7
check "it prints each check: bucket, name, link"   printed "pass${TAB}gate${TAB}https://ci/gate" "skipping${TAB}docs${TAB}https://ci/docs"
check "without a sleep"                            test "$(count sleep)" -eq 0
exits 1 "a failed check exits 1"                   "$(answer gate:pass test:fail)" 7
check "and still prints every check"               printed "pass${TAB}gate${TAB}https://ci/gate" "fail${TAB}test${TAB}https://ci/test"
exits 1 "a cancelled check exits 1"                "$(answer gate:pass test:cancel)" 7

echo "-- checks still running"
exits 0 "it polls until none is pending"           "$(printf '%s\n' "$PENDING" "$PENDING" "$GREEN")" 7
check "three polls"                                test "$(count gh)" -eq 3
check "30 seconds apart"                           test "$(count 'sleep 30$')" -eq 2
check "printing only the final checks"             printed "pass${TAB}gate${TAB}https://ci/gate" "skipping${TAB}docs${TAB}https://ci/docs"

echo "-- checks not registered yet"
exits 0 "within the grace window, no check and an error mean poll again" "$(printf '%s\n' '[]' error "$GREEN")" 7
check "three polls"                                test "$(count gh)" -eq 3
SECONDS=301 exits 3 "past it, no check ever registered exits 3" '[]' 7
check "and says so"                                printed 'No check registered on PR #7 within 300s.'
SECONDS=301 exits 0 "once a check was seen, an error past it never reads as no check" "$(printf '%s\n' "$PENDING" error "$GREEN")" 7

echo "-- the deadline"
SECONDS=3601 exits 2 "checks still pending past it exit 2" "$PENDING" 7
check "and say so"                                 printed 'PR #7 still has pending checks after 3600s.'
SECONDS=3601 exits 0 "checks done when it passed are still reported" "$GREEN" 7

echo "== $pass passed, $fail failed"
[ "$fail" -eq 0 ]
