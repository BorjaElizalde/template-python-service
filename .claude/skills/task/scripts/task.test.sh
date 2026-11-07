#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
# Regression suite for task.sh. Run from any checkout: bash .claude/skills/task/scripts/task.test.sh
# Two clones of one throwaway origin, named backend and frontend, stand in for two repositories.
# Stub gh answers issue state and title and merged PRs from files under $TASK_TEST_STATE; stub
# osascript logs the sessions it would open, end or bring to the front; stub ps and lsof report a
# claude process running in the folder named in $TASK_TEST_STATE/running.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
export TASK_TEST_STATE="$WORK/state"
export CLAUDE_CONFIG_DIR="$WORK/claude"
pass=0; fail=0

mkdir -p "$WORK/bin" "$TASK_TEST_STATE" "$WORK/seed/.claude/skills/task/scripts" "$WORK/repos"
cat >"$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "issue view")
    case "$3" in
      42) title="Name make close_claude_session in backend CLAUDE.md" ;;
      7) title="Second task" ;;
      5) title="Already done" ;;
      8|9|10|11) title="Task $3" ;;
      *) exit 1 ;;
    esac
    echo "$(cat "$TASK_TEST_STATE/issue-$3" 2>/dev/null || echo OPEN) $title" ;;
  "pr list")
    while [ $# -gt 0 ]; do [ "$1" = --head ] && branch=$2; shift; done
    grep -qxF "$branch" "$TASK_TEST_STATE/merged" 2>/dev/null && echo 1
    exit 0 ;;
  *) exit 1 ;;
esac
EOF
cat >"$WORK/bin/osascript" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
printf '%s\n' "$*" >>"$TASK_TEST_STATE/osascript.log"
# The session in a tab told to exit stops and its window closes. While $TASK_TEST_STATE/stuck exists
# the session never stops, and the script fails as session_tab's does after 30 seconds.
if [ "${3:-}" = exit ]; then
  [ ! -f "$TASK_TEST_STATE/stuck" ] || exit 1
  rm -f "$TASK_TEST_STATE/running"
fi
exit 0
EOF
cat >"$WORK/bin/ps" <<'EOF'
#!/usr/bin/env bash
[ -f "$TASK_TEST_STATE/running" ] && echo "4242 ttys042 /usr/local/bin/claude"
exit 0
EOF
cat >"$WORK/bin/lsof" <<'EOF'
#!/usr/bin/env bash
printf 'p4242\nfcwd\nn%s\n' "$(cat "$TASK_TEST_STATE/running")"
EOF
chmod +x "$WORK/bin/gh" "$WORK/bin/osascript" "$WORK/bin/ps" "$WORK/bin/lsof"
export PATH="$WORK/bin:$PATH"
echo CLOSED >"$TASK_TEST_STATE/issue-5"

cp "$HERE/task.sh" "$WORK/seed/.claude/skills/task/scripts/"
printf 'ISSUES_REPO=acme/tasks\nWORKTREE_ROOT=../worktrees\n' >"$WORK/seed/.claude/agentic.conf"
printf 'settings.local.json\n' >"$WORK/seed/.claude/.gitignore"
git init -q -b develop "$WORK/seed"
git -C "$WORK/seed" add -A
git -C "$WORK/seed" -c user.name=t -c user.email=t@t commit -qm seed
git clone -q --bare "$WORK/seed" "$WORK/origin.git"
git clone -q "$WORK/origin.git" "$WORK/repos/backend"
git clone -q "$WORK/origin.git" "$WORK/repos/frontend"
BACKEND="$WORK/repos/backend"
FRONTEND="$WORK/repos/frontend"

check() {  # check <desc> <command...>
  if "${@:2}" >/dev/null 2>&1; then pass=$((pass+1)); echo "PASS $1"
  else fail=$((fail+1)); echo "FAIL $1"; fi
}
task() { bash "$1/.claude/skills/task/scripts/task.sh" "${@:2}"; }
branch_of() { git -C "$1" rev-parse --abbrev-ref HEAD; }
memory_of() { jq -r .autoMemoryDirectory "$1/.claude/settings.local.json"; }
sessions() { grep -c -F "$1" "$TASK_TEST_STATE/osascript.log"; }
last_osascript() { tail -n 1 "$TASK_TEST_STATE/osascript.log"; }
transcript() {  # leaves the transcript a claude session in folder $1 writes
  local dir; dir="$CLAUDE_CONFIG_DIR/projects/$(printf '%s' "$1" | tr -c 'a-zA-Z0-9' '-')"
  mkdir -p "$dir" && touch "$dir/session.jsonl"
}
refuses() {  # refuses <desc> <reason pattern> <checkout> <task.sh args...>: fails, and says why
  local out
  if out="$(bash "$3/.claude/skills/task/scripts/task.sh" "${@:4}" 2>&1)"; then fail=$((fail+1)); echo "FAIL $1 (it ran)"
  elif grep -qE -- "$2" <<<"$out"; then pass=$((pass+1)); echo "PASS $1"
  else fail=$((fail+1)); echo "FAIL $1 (wrong reason: $out)"; fi
}
commit() { git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m work; }
run_in() {  # run_in <folder> <task.sh args...>: its own task.sh, run from inside it; output in $WORK/out
  (cd "$1" && bash .claude/skills/task/scripts/task.sh "${@:2}") >"$WORK/out" 2>&1
}

ISSUE42="$WORK/repos/worktrees/42-name-make-close-claude-session-in"
ISSUE7="$WORK/repos/worktrees/7-second-task"

echo "-- start: one folder per issue, one subfolder per repository"
check "backend starts issue 42"                task "$BACKEND" start 42
check "the worktree is <root>/<n>-<slug>/backend" test -d "$ISSUE42/backend"
check "its branch is feat/<n>-<slug>"          test "$(branch_of "$ISSUE42/backend")" = feat/42-name-make-close-claude-session-in
check "it branches off origin/develop"         git -C "$ISSUE42/backend" merge-base --is-ancestor origin/develop HEAD
check "its memory points at itself"            test "$(memory_of "$ISSUE42/backend")" = "$ISSUE42/backend/.claude/memory"
check "the main checkout's memory points at it" test "$(memory_of "$BACKEND")" = "$BACKEND/.claude/memory"
check "its session opens with the issue name"  test "$(sessions '#42 backend: Name make close_claude_session in')" -eq 1
check "with a first prompt that reads its issue" bash -c "tail -n 1 '$TASK_TEST_STATE/osascript.log' | grep -qF 'gh issue view 42 -R acme/tasks --comments'"
check "starting again resumes, creates nothing" task "$BACKEND" start 42
check "the session opens a second time"        test "$(sessions '#42 backend:')" -eq 2
check "both fresh: no transcript exists yet"   bash -c "! grep -q -- --continue '$TASK_TEST_STATE/osascript.log'"
check "frontend joins the same issue folder"   task "$FRONTEND" start 42
check "side by side, no collision"             test -d "$ISSUE42/frontend"
check "a start inside a worktree"              task "$ISSUE42/backend" start 7 fix
check "resolves from the main checkout"        test -d "$ISSUE7/backend"
check "and takes the branch type"              test "$(branch_of "$ISSUE7/backend")" = fix/7-second-task
refuses "a closed issue does not start"          'is CLOSED'            "$BACKEND" start 5

echo "-- start: an existing issue picks up its session"
transcript "$ISSUE42/backend"
check "a session with a transcript"            task "$BACKEND" start 42
check "resumes it with --continue"             bash -c "tail -n 1 '$TASK_TEST_STATE/osascript.log' | grep -q -- ' --continue '"
check "and the same first prompt"              bash -c "tail -n 1 '$TASK_TEST_STATE/osascript.log' | grep -qF 'Work on issue #42 in acme/tasks.'"
echo "$ISSUE42/backend" >"$TASK_TEST_STATE/running"
check "a running session"                      task "$BACKEND" start 42
check "is brought to the front"                test "$(last_osascript)" = "- /dev/ttys042 focus"
check "and never opened twice"                 test "$(sessions '#42 backend:')" -eq 3
rm "$TASK_TEST_STATE/running"

echo "-- start: an existing issue picks up its branch"
commit "$ISSUE7/backend"
rm -rf "$ISSUE7/backend"
check "a branch whose folder was deleted"      task "$BACKEND" start 7
check "gets it back, on its own branch"        test "$(branch_of "$ISSUE7/backend")" = fix/7-second-task
check "with its commit"                        test "$(git -C "$ISSUE7/backend" rev-list --count origin/develop..HEAD)" -eq 1
git -C "$ISSUE7/backend" push -q origin HEAD 2>/dev/null
ELSEWHERE="$WORK/elsewhere/backend"
git clone -q "$WORK/origin.git" "$ELSEWHERE"
check "a branch only on origin, in another clone" task "$ELSEWHERE" start 7
check "is checked out at origin's commit"      test "$(git -C "$WORK/elsewhere/worktrees/7-second-task/backend" rev-parse HEAD)" = "$(git -C "$ISSUE7/backend" rev-parse HEAD)"
check "tracking origin's branch"               test "$(git -C "$WORK/elsewhere/worktrees/7-second-task/backend" rev-parse --abbrev-ref '@{upstream}')" = origin/fix/7-second-task

echo "-- finish: refused while anything would be lost"
refuses "an open issue does not finish"          'still open'           "$BACKEND" finish 42
echo CLOSED >"$TASK_TEST_STATE/issue-42"
echo notes >"$ISSUE42/backend/notes.md"
refuses "untracked files block it"               'untracked files'      "$BACKEND" finish 42
check "and the worktree stays"                 test -f "$ISSUE42/backend/notes.md"
rm "$ISSUE42/backend/notes.md"
commit "$ISSUE42/backend"
refuses "unpushed commits block it"              'push them first'      "$BACKEND" finish 42
git -C "$ISSUE42/backend" push -q origin HEAD 2>/dev/null
echo "$ISSUE42/backend" >"$TASK_TEST_STATE/running"
touch "$TASK_TEST_STATE/stuck"
refuses "a session that never exits blocks it"    'did not exit'         "$BACKEND" finish 42
check "and the worktree stays"                 test -d "$ISSUE42/backend"
rm "$TASK_TEST_STATE/stuck"

echo "-- finish: closed issue, nothing unshipped"
check "a pushed branch finishes"               task "$BACKEND" finish 42
check "its session ended and its window closed" test "$(sessions '/dev/ttys042 exit')" -eq 2
check "its worktree is gone"                   test ! -e "$ISSUE42/backend"
check "its local branch is gone"               bash -c "! git -C '$BACKEND' rev-parse -q --verify feat/42-name-make-close-claude-session-in"
check "the issue folder stays for frontend"    test -d "$ISSUE42/frontend"
check "a branch with no commits finishes"      task "$FRONTEND" finish 42
check "the last one removes the issue folder"  test ! -e "$ISSUE42"

echo "-- finish: never from inside the worktree it removes"
echo CLOSED >"$TASK_TEST_STATE/issue-7"
commit "$ISSUE7/backend"
check "not from a shell inside it"             bash -c "cd '$ISSUE7/backend' && bash '$BACKEND/.claude/skills/task/scripts/task.sh' finish 7 2>&1 | grep -q 'from outside its worktree'"
refuses "not through its own copy of task.sh"    "main checkout's"     "$ISSUE7/backend" finish 7
refuses "its unpushed commit blocks it"          'push them first'      "$BACKEND" finish 7
echo fix/7-second-task >"$TASK_TEST_STATE/merged"
check "a merged PR covers a squash-merged branch" task "$BACKEND" finish 7
check "its worktree is gone"                   test ! -e "$ISSUE7/backend"

echo "-- sweep: a start first finishes every task whose issue is closed"
ISSUE8="$WORK/repos/worktrees/8-task-8"
ISSUE9="$WORK/repos/worktrees/9-task-9"
ISSUE10="$WORK/repos/worktrees/10-task-10"
check "backend starts issue 8"                 task "$BACKEND" start 8
check "and issue 9"                            task "$BACKEND" start 9
echo CLOSED >"$TASK_TEST_STATE/issue-8"
echo CLOSED >"$TASK_TEST_STATE/issue-9"
echo notes >"$ISSUE8/backend/notes.md"
check "a start goes on past a refused finish"  run_in "$BACKEND" start 10
check "and opens its own session"              test "$(sessions '#10 backend:')" -eq 1
check "it finished the closed task"            test ! -e "$ISSUE9"
check "and removed its branch"                 bash -c "! git -C '$BACKEND' rev-parse -q --verify feat/9-task-9"
check "it reported the refusal"                grep -q 'untracked files' "$WORK/out"
check "and kept the refused worktree"          test -f "$ISSUE8/backend/notes.md"

echo "-- sweep: a bare finish"
rm "$ISSUE8/backend/notes.md"
check "a sweep runs on its own"                run_in "$BACKEND" sweep
check "it finished the closed task"            test ! -e "$ISSUE8"
check "it left the open task alone"            test -d "$ISSUE10/backend"
check "without a word about it"                bash -c "! grep -q 'issue 10' '$WORK/out'"

echo "-- sweep: from inside a task worktree"
echo CLOSED >"$TASK_TEST_STATE/issue-10"
check "a start from the task's own session"    run_in "$ISSUE10/backend" start 11
check "starts its issue"                       test -d "$WORK/repos/worktrees/11-task-11/backend"
check "past the finish of its own worktree"    grep -q 'from outside its worktree' "$WORK/out"
check "which stays"                            test -d "$ISSUE10/backend"

echo "-- usage"
refuses "no command is refused"                  '^usage:'              "$BACKEND"

echo "== $pass passed, $fail failed"
[ "$fail" -eq 0 ]
