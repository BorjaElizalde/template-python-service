#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
# Regression suite for task.sh. Run from any checkout: bash .claude/skills/task/scripts/task.test.sh
# Two clones of one throwaway origin, named backend and frontend, stand in for two repositories.
# Stub gh answers issue state and title, labels, blockers and comments, the open issues, and PRs,
# from files under $TASK_TEST_STATE, keeps the labels and comments it is given there, and can't
# answer while $TASK_TEST_STATE/gh-down exists; stub osascript logs each call, runs the line it
# types into a new tab as the tab's shell would, and ends or brings to the front the session in a
# tab; stub claude lists a session running in each folder named in $TASK_TEST_STATE/running, and a
# session it launches keeps its arguments and runs there until a test or a finish ends it; stub ps
# gives a session's tty; stub sleep returns at once.
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
[ ! -f "$TASK_TEST_STATE/gh-down" ] || exit 1
cd "$TASK_TEST_STATE" || exit 1
title() {
  case "$1" in
    42) echo "Name make close_claude_session in backend CLAUDE.md" ;;
    7) echo "Second task" ;;
    5) echo "Already done" ;;
    23) echo "Task 23, with a title longer than the forty characters of a task line" ;;
    25) echo "Design the next step" ;;
    26) echo "Design a launch longer than a tty line" ;;
    8|9|1[0-9]|2[0-4]) echo "Task $1" ;;
    *) return 1 ;;
  esac
}
state() { cat "issue-$1" 2>/dev/null || echo OPEN; }
# Issue $1 as JSON: its number and title, its labels and comments, one per line of labels-<n> and
# comments-<n>, and the issues it is blocked by, one number per line of blocked-by-<n>, each in the
# state its issue-<n> file gives.
issue() {
  local blockers
  blockers=$(for m in $(cat "blocked-by-$1" 2>/dev/null); do echo "$m $(state "$m")"; done)
  jq -n --argjson number "$1" --arg title "$(title "$1")" --arg labels "$(cat "labels-$1" 2>/dev/null)" \
    --arg comments "$(cat "comments-$1" 2>/dev/null)" --arg blockers "$blockers" '
    def lines: split("\n") | map(select(. != ""));
    {number: $number, title: $title, labels: ($labels | lines | map({name: .})),
      blockedBy: {nodes: ($blockers | lines | map(split(" ") | {number: (.[0] | tonumber), state: .[1]}))},
      comments: ($comments | lines | map({body: .}))}'
}
case "$1 $2" in
  "issue view")
    title "$3" >/dev/null || exit 1
    # --json state,title asks for "<STATE> <title>", as its -q prints it; any other --json, for the issue.
    if [ "$7" = state,title ]; then echo "$(state "$3") $(title "$3")"; else issue "$3"; fi ;;
  "issue list")
    # The open issues, newest first, as gh lists them for --state open.
    for n in 42 {24..7} 5; do [ "$(state "$n")" != OPEN ] || issue "$n"; done | jq -s . ;;
  "issue comment")
    n=$3; while [ $# -gt 0 ]; do [ "$1" != --body ] || echo "$2" >>"$TASK_TEST_STATE/comments-$n"; shift; done ;;
  "issue edit")
    # Like gh, it adds no label the repository lacks.
    n=$3; while [ $# -gt 0 ]; do
      if [ "$1" = --add-label ]; then
        grep -qxF "$2" "$TASK_TEST_STATE/repo-labels" 2>/dev/null || exit 1
        echo "$2" >>"$TASK_TEST_STATE/labels-$n"
      fi
      shift
    done ;;
  "label create")
    # --force updates a label that exists, so the repository lists it once.
    grep -qxF "$3" "$TASK_TEST_STATE/repo-labels" 2>/dev/null || echo "$3" >>"$TASK_TEST_STATE/repo-labels" ;;
  "pr list")
    while [ $# -gt 0 ]; do case "$1" in --head) branch=$2 ;; --state) state=$2 ;; esac; shift; done
    # --state merged asks whether a PR from the branch merged; --state all, for its newest PR.
    if [ "$state" = merged ]; then
      grep -qxF "$branch" "$TASK_TEST_STATE/merged" 2>/dev/null && echo 1
    else
      cat "$TASK_TEST_STATE/pr-${branch//\//-}" 2>/dev/null || echo '[]'
    fi
    exit 0 ;;
  *) exit 1 ;;
esac
EOF
cat >"$WORK/bin/osascript" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TASK_TEST_STATE/osascript.log"
# A line typed into a tab past 1024 bytes, newline included, never runs: its tty drops it.
# $TASK_TEST_STATE/tab keeps the pid of the line's process.
if [ $# -eq 2 ]; then
  rm -f "$TASK_TEST_STATE/launched" "$TASK_TEST_STATE/claude-pid"
  if [ "$(printf '%s\n' "$2" | wc -c)" -le 1024 ]; then
    bash -s <<<"$2" &
    echo $! >"$TASK_TEST_STATE/tab"
    wait
  fi
fi
# The session in a tab told to exit stops and its window closes. While $TASK_TEST_STATE/stuck exists
# the session never stops, and the script fails as session_tab's does after 30 seconds.
if [ "${3:-}" = exit ]; then
  [ ! -f "$TASK_TEST_STATE/stuck" ] || exit 1
  # Its session's line goes: the session on /dev/ttys042 is on line 1, /dev/ttys043 on line 2.
  awk -v n=$((10#${2#/dev/ttys} - 41)) 'NR != n' "$TASK_TEST_STATE/running" >"$TASK_TEST_STATE/running.next"
  mv "$TASK_TEST_STATE/running.next" "$TASK_TEST_STATE/running"
fi
exit 0
EOF
# claude agents --json, as Claude Code prints it. Each line of $TASK_TEST_STATE/running,
# "<folder> [<status>]", is a background session, then an interactive one, busy unless the line
# says else, with pid 4242 on line 1, 4243 on line 2. While $TASK_TEST_STATE/claude-down exists,
# it can't answer. Any other call launches a session, which fails while $TASK_TEST_STATE/no-start
# exists, else adds its folder to running: its arguments go to $TASK_TEST_STATE/launched, each ended
# by a NUL, since the system prompt spans lines, and joined on one line of launches; its pid to
# claude-pid.
cat >"$WORK/bin/claude" <<'EOF'
#!/usr/bin/env bash
if [ "$*" != "agents --json" ]; then
  [ ! -f "$TASK_TEST_STATE/no-start" ] || exit 1
  printf '%s\0' "$@" >"$TASK_TEST_STATE/launched"
  echo "${*//$'\n'/ }" >>"$TASK_TEST_STATE/launches"
  echo $$ >"$TASK_TEST_STATE/claude-pid"
  pwd -P >>"$TASK_TEST_STATE/running"
  exit 0
fi
[ ! -f "$TASK_TEST_STATE/claude-down" ] || exit 1
[ -f "$TASK_TEST_STATE/running" ] || { echo '[]'; exit 0; }
jq -Rn '[inputs | capture("^(?<cwd>[^ ]+)( (?<status>.+))?$")] | to_entries | map(
  {id: "b0b0b0b0", cwd: .value.cwd, kind: "background", name: "a background session", state: "blocked"},
  {pid: (4242 + .key), cwd: .value.cwd, kind: "interactive", name: "a task session", status: (.value.status // "busy")})' \
  "$TASK_TEST_STATE/running"
EOF
# The tty of pid 4242 is ttys042, of 4243 ttys043.
cat >"$WORK/bin/ps" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2 $3" = "-o tty= -p" ] && printf 'ttys%03d    \n' $(($4 - 4200))
EOF
printf '#!/usr/bin/env bash\n' >"$WORK/bin/sleep"
chmod +x "$WORK/bin/gh" "$WORK/bin/osascript" "$WORK/bin/claude" "$WORK/bin/ps" "$WORK/bin/sleep"
export PATH="$WORK/bin:$PATH"
echo CLOSED >"$TASK_TEST_STATE/issue-5"

cp "$HERE/task.sh" "$WORK/seed/.claude/skills/task/scripts/"
cp -R "$HERE/../session" "$WORK/seed/.claude/skills/task/"
SESSION="$HERE/../session"
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
sessions() { grep -c -F "$1" "$TASK_TEST_STATE/launches"; }
last_osascript() { tail -n 1 "$TASK_TEST_STATE/osascript.log"; }
sessions_exit() { rm -f "$TASK_TEST_STATE/running"; }  # every running session exits
launched() { jq -e -Rs 'split("\u0000")[:-1] | '"$1" "$TASK_TEST_STATE/launched"; }  # launched <jq filter>: over the last launch's arguments
launched_arg() { launched ".[index(\"$1\") + 1]" | jq -r .; }  # the value the launch gave option $1
# launches_in execution|design: the session last opened launches in that mode. Every session has its
# permission prompts denied, and the words both modes share, then its mode's own, as the system
# prompt it appends. An execution session has no question tool and has a Stop hook; a design
# session has the tool and no hook. claude --settings reads a file or a JSON string.
launches_in() {
  local settings
  settings="$(launched_arg --settings)"
  [ ! -f "$settings" ] || settings="$(cat "$settings")"
  jq -e '.hooks.PermissionRequest' <<<"$settings" &&
    [ "$(launched_arg --append-system-prompt)" = "$(cat "$SESSION/prompt.md" "$SESSION/$1.md")" ] || return 1
  if [ "$1" = design ]; then
    launched 'index("--disallowed-tools") == null' && jq -e '.hooks | has("Stop") | not' <<<"$settings"
  else
    [ "$(launched_arg --disallowed-tools)" = AskUserQuestion ] && jq -e '.hooks.Stop' <<<"$settings"
  fi
}
# The session last opened runs claude interactively, with no -p or --print, as its tab's only process.
interactive() {
  launched 'all(.[]; . != "-p" and . != "--print")' &&
    [ "$(cat "$TASK_TEST_STATE/claude-pid")" = "$(cat "$TASK_TEST_STATE/tab")" ]
}
transcript() {  # transcript <folder> [<name> <[CC]YYMMDDhhmm>]: a claude session in that folder writes it, now or then
  local dir; dir="$CLAUDE_CONFIG_DIR/projects/$(printf '%s' "$1" | tr -c 'a-zA-Z0-9' '-')"
  mkdir -p "$dir" && touch ${3:+-t "$3"} "$dir/${2:-session}.jsonl"
}
pr_from() {  # pr_from <branch> <state> <isDraft> <statusCheckRollup>: the newest PR from that branch, #21
  printf '[{"number": 21, "state": "%s", "isDraft": %s, "statusCheckRollup": %s}]\n' "$2" "$3" "$4" \
    >"$TASK_TEST_STATE/pr-${1//\//-}"
}
status_line() { grep "^#$1 " "$WORK/out"; }  # the line the last run_in ... status printed for issue $1
under() { awk -v heading="$1:" '!/^#/ { on = $0 == heading; next } on' "$WORK/out"; }  # its lines under heading $1
unknown_last() { tail -n 1 "$WORK/out" | grep -q '^The tasks are unknown: .*/task:status'; }  # the last run_in ended so
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
check "backend starts issue 42"                run_in "$BACKEND" start 42
check "the worktree is <root>/<n>-<slug>/backend" test -d "$ISSUE42/backend"
check "its branch is feat/<n>-<slug>"          test "$(branch_of "$ISSUE42/backend")" = feat/42-name-make-close-claude-session-in
check "it branches off origin/develop"         git -C "$ISSUE42/backend" merge-base --is-ancestor origin/develop HEAD
check "its memory points at itself"            test "$(memory_of "$ISSUE42/backend")" = "$ISSUE42/backend/.claude/memory"
check "the main checkout's memory points at it" test "$(memory_of "$BACKEND")" = "$BACKEND/.claude/memory"
check "its session opens with the issue name"  test "$(sessions '#42 backend: Name make close_claude_session in')" -eq 1
check "and the start names its mode"           grep -qxF '✓ session opened in execution mode: #42 backend: Name make close_claude_session in' "$WORK/out"
check "with a first prompt that reads its issue" bash -c "tail -n 1 '$TASK_TEST_STATE/launches' | grep -qF 'gh issue view 42 -R acme/tasks --json title,body,comments'"
check "an interactive claude, never -p or --print, the tab's only process" interactive
check "in execution mode: no question tool, a Stop hook, permission prompts denied" launches_in execution
sessions_exit
check "starting again resumes, creates nothing" task "$BACKEND" start 42
check "the session opens a second time"        test "$(sessions '#42 backend:')" -eq 2
check "both fresh: no transcript exists yet"   bash -c "! grep -q -- --continue '$TASK_TEST_STATE/launches'"
check "frontend joins the same issue folder"   task "$FRONTEND" start 42
check "side by side, no collision"             test -d "$ISSUE42/frontend"
check "a start inside a worktree"              task "$ISSUE42/backend" start 7 fix
check "resolves from the main checkout"        test -d "$ISSUE7/backend"
check "and takes the branch type"              test "$(branch_of "$ISSUE7/backend")" = fix/7-second-task
check "a fix launches in execution mode too"   launches_in execution
refuses "a closed issue does not start"          'is CLOSED'            "$BACKEND" start 5

echo "-- start: an existing issue picks up its session"
transcript "$ISSUE42/backend"
sessions_exit
check "a session with a transcript"            task "$BACKEND" start 42
check "resumes it with --continue"             launched 'index("--continue") != null'
check "and the same first prompt"              bash -c "tail -n 1 '$TASK_TEST_STATE/launches' | grep -qF 'Work on issue #42 in acme/tasks.'"
check "still interactive"                      interactive
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

echo "-- start: the branch type is the task's mode, for its life"
ISSUE25="$WORK/repos/worktrees/25-design-the-next-step"
check "backend starts issue 25 as design"      run_in "$BACKEND" start 25 design
check "on a design branch"                     test "$(branch_of "$ISSUE25/backend")" = design/25-design-the-next-step
check "and the start names design mode"        grep -qxF '✓ session opened in design mode: #25 backend: Design the next step' "$WORK/out"
check "in design mode: the question tool, no Stop hook, permission prompts denied" launches_in design
transcript "$ISSUE25/backend"
sessions_exit
check "a start with no type"                   run_in "$BACKEND" start 25
check "resumes it in design mode"              grep -qxF '✓ session resumed in design mode: #25 backend: Design the next step' "$WORK/out"
check "and launches it so"                     launches_in design
echo "$ISSUE25/backend" >"$TASK_TEST_STATE/running"
check "a start with another type"              run_in "$BACKEND" start 25 feat
check "brings the running session forward, still in design mode" grep -qxF '✓ session already running in design mode, brought to the front: #25 backend: Design the next step' "$WORK/out"
run_in "$BACKEND" status
check "the status line of a design task says so" test "$(status_line 25)" = '#25 Design the next step: design mode, session busy, no PR, active 0 min ago'
check "and an execution task's names no mode"  bash -c "grep -q '^#42 ' '$WORK/out' && ! grep -q '^#42 .*mode' '$WORK/out'"
rm "$TASK_TEST_STATE/running"
commit "$ISSUE25/backend"
rm -rf "$ISSUE25/backend"
check "a design branch whose folder was deleted" run_in "$BACKEND" start 25
check "comes back in design mode"              bash -c "grep -qF '(branch design/25-design-the-next-step)' '$WORK/out' && grep -qF '✓ session resumed in design mode: ' '$WORK/out'"
check "and launches so"                        launches_in design
refuses "an unknown type is refused"             '^unknown type feature: ' "$BACKEND" start 24 feature
check "before anything is created"             test ! -e "$WORK/repos/worktrees/24-task-24"
git -C "$ISSUE25/backend" push -q origin HEAD 2>/dev/null
echo CLOSED >"$TASK_TEST_STATE/issue-25"
check "a design task finishes as any other"    task "$BACKEND" finish 25

echo "-- start: a session launched by a command longer than the 1024 bytes a tty line holds"
LONG="$WORK/repos/$(printf 'long-%.0s' {1..30})backend"
ISSUE26="$WORK/repos/worktrees/26-design-a-launch-longer-than-a-tty-line/$(basename "$LONG")"
git clone -q "$WORK/origin.git" "$LONG"
check "a design task in a repository with a long name" run_in "$LONG" start 26 design
check "has a command over 1024 bytes"          test "$(wc -c <"$(git -C "$ISSUE26" rev-parse --absolute-git-dir)/task-session.sh")" -gt 1024
check "and its session runs"                   grep -qxF "✓ session opened in design mode: #26 $(basename "$LONG"): Design a launch longer than a tty line" "$WORK/out"
check "in design mode"                         launches_in design
check "the tab's only process"                 interactive
sessions_exit
touch "$TASK_TEST_STATE/no-start"
check "a start whose session never runs fails" bash -c "! (cd '$LONG' && bash .claude/skills/task/scripts/task.sh start 26) >'$WORK/out' 2>&1"
check "says why, and never that a session opened" bash -c "
  tail -n 1 '$WORK/out' | grep -q '^no session runs in .* 30 seconds after its launch: ' && ! grep -q '^✓ session' '$WORK/out'"
rm "$TASK_TEST_STATE/no-start"

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
check "its session ended and its window closed" test "$(last_osascript)" = "- /dev/ttys042 exit"
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

echo "-- finish: every local branch of the issue"
ISSUE12="$WORK/repos/worktrees/12-task-12"
check "backend starts issue 12"                task "$BACKEND" start 12
commit "$ISSUE12/backend"
# The task moves on to a second branch for a follow-up PR and leaves its first one unpushed.
git -C "$ISSUE12/backend" switch -q -c docs/12-follow-up origin/develop
git -C "$BACKEND" branch -q feat/112-other origin/develop
echo CLOSED >"$TASK_TEST_STATE/issue-12"
refuses "an unshipped branch beside the worktree's blocks it" 'feat/12-task-12 has commits' "$BACKEND" finish 12
check "before anything is removed"             test -d "$ISSUE12/backend"
echo feat/12-task-12 >>"$TASK_TEST_STATE/merged"
check "once shipped, it finishes with the worktree" task "$BACKEND" finish 12
check "both branches of the issue are gone"    test -z "$(git -C "$BACKEND" for-each-ref 'refs/heads/*/12-*')"
check "another issue's branch stays"           git -C "$BACKEND" rev-parse -q --verify feat/112-other

echo "-- cleanup: a start first finishes every task whose issue is closed"
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
check "it reported the finish in one line"     grep -qxF '✓ issue 9 finished: session closed, worktree removed, branches removed: feat/9-task-9' "$WORK/out"
check "and the refusal in one line, with why"  grep -qx "✗ issue 8 not finished: $ISSUE8/backend has uncommitted or untracked files: .*" "$WORK/out"
check "with no line of git's own"              bash -c "! grep -q '^fatal:' '$WORK/out'"
check "and kept the refused worktree"          test -f "$ISSUE8/backend/notes.md"

echo "-- cleanup: on its own"
rm "$ISSUE8/backend/notes.md"
check "a cleanup runs on its own"              run_in "$BACKEND" cleanup
check "it finished the closed task"            test ! -e "$ISSUE8"
check "it left the open task alone"            test -d "$ISSUE10/backend"
check "and printed one line, for the finish"   test "$(cat "$WORK/out")" = '✓ issue 8 finished: session closed, worktree removed, branches removed: feat/8-task-8'

echo "-- cleanup: from inside a task worktree"
echo CLOSED >"$TASK_TEST_STATE/issue-10"
check "a start from the task's own session"    run_in "$ISSUE10/backend" start 11
check "starts its issue"                       test -d "$WORK/repos/worktrees/11-task-11/backend"
check "past the finish of its own worktree"    grep -qx '✗ issue 10 not finished: finish issue 10 from outside its worktree: .*' "$WORK/out"
check "which stays"                            test -d "$ISSUE10/backend"

echo "-- status: every task in one view, and it only reads"
ISSUE11="$WORK/repos/worktrees/11-task-11"
ISSUE13="$WORK/repos/worktrees/13-task-13"
ISSUE14="$WORK/repos/worktrees/14-task-14"
ISSUE17="$WORK/repos/worktrees/17-task-17"
check "backend starts issue 13"                task "$BACKEND" start 13
check "and issue 14"                           task "$BACKEND" start 14
check "and issue 17"                           task "$BACKEND" start 17
echo CLOSED >"$TASK_TEST_STATE/issue-14"
echo "$ISSUE11/backend idle" >"$TASK_TEST_STATE/running"
transcript "$ISSUE11/backend" old 200001010000
transcript "$ISSUE11/backend"
PENDING='{"__typename": "CheckRun", "name": "gate", "status": "IN_PROGRESS", "conclusion": ""}'
PASSED='{"__typename": "CheckRun", "name": "gate", "status": "COMPLETED", "conclusion": "SUCCESS"}'
SKIPPED='{"__typename": "CheckRun", "name": "lint", "status": "COMPLETED", "conclusion": "SKIPPED"}'
FAILED='{"__typename": "CheckRun", "name": "gate", "status": "COMPLETED", "conclusion": "FAILURE"}'
NO_CONCLUSION='{"__typename": "CheckRun", "name": "gate", "status": "COMPLETED", "conclusion": ""}'
CONTEXT='{"__typename": "StatusContext", "context": "ci", "state": "SUCCESS"}'
pr_from feat/11-task-11 OPEN false "[$PENDING, $CONTEXT]"
check "a look runs"                            run_in "$BACKEND" status
check "a task's session, PR, checks and last write" test "$(status_line 11)" = "#11 Task 11: session idle, PR #21 open, checks pending, active 0 min ago"
check "a task with none of them yet, marked"   test "$(status_line 13)" = "#13 Task 13: no session, no PR, no transcript, needs attention"
check "it finishes no task whose issue closed" test -d "$ISSUE14/backend"
check "and lists it"                           test -n "$(status_line 14)"
check "it opens with the In progress heading"  test "$(head -n 1 "$WORK/out")" = 'In progress:'
check "under which is one line per task"       test "$(under 'In progress' | grep -c '^#[0-9]* Task [0-9]*: ')" -eq 4 -a "$(under 'In progress' | wc -l)" -eq 4
pr_from feat/11-task-11 OPEN false "[$PENDING, $FAILED]"
run_in "$BACKEND" status
check "a failed check outweighs a pending one" bash -c "grep -qF '#11 Task 11: session idle, PR #21 open, checks failed,' '$WORK/out'"
pr_from feat/11-task-11 OPEN true "[$PASSED, $SKIPPED, $CONTEXT]"
run_in "$BACKEND" status
check "a draft whose checks passed or skipped" bash -c "grep -qF 'PR #21 draft, checks passed,' '$WORK/out'"
pr_from feat/11-task-11 OPEN false "[$PASSED, $NO_CONCLUSION]"
run_in "$BACKEND" status
check "a check completed with no conclusion has not passed" bash -c "grep -qF 'PR #21 open, checks failed,' '$WORK/out'"
pr_from feat/11-task-11 MERGED false "[]"
transcript "$ISSUE11/backend" session 200001010000
run_in "$BACKEND" status
check "a merged PR with no checks"             bash -c "grep -qF 'PR #21 merged, no checks,' '$WORK/out'"
check "a session idle for days, marked"        bash -c "grep -qE '^#11 Task 11: session idle, .*, active [0-9]+ d ago, needs attention$' '$WORK/out'"

echo "-- status: marks the tasks that need attention"
transcript "$ISSUE13/backend" old 200001010000
run_in "$BACKEND" status
check "a session idle for 10 minutes"          grep -qE '^#11 Task 11: session idle, .*, needs attention$' "$WORK/out"
check "and a session gone for 10 minutes"      grep -qE '^#13 Task 13: no session, .*, needs attention$' "$WORK/out"
transcript "$ISSUE11/backend"
transcript "$ISSUE13/backend"
run_in "$BACKEND" status
check "not a session idle, nor one gone, for less than 10 minutes" bash -c "
  grep -q '^#11 Task 11: session idle,' '$WORK/out' && grep -q '^#13 Task 13: no session,' '$WORK/out' &&
  ! grep -qE '^#1[13] .*needs attention' '$WORK/out'"
echo "$ISSUE11/backend waiting" >"$TASK_TEST_STATE/running"
run_in "$BACKEND" status
check "a waiting session at once"              bash -c "grep -qE '^#11 Task 11: session waiting, .*, needs attention$' '$WORK/out' && ! grep -qE '^#13 .*needs attention' '$WORK/out'"
echo "$ISSUE11/backend" >"$TASK_TEST_STATE/running"
transcript "$ISSUE11/backend" session 200001010000
transcript "$ISSUE11/backend" old 200001010000
run_in "$BACKEND" status
check "never a busy one, however long ago it wrote" bash -c "grep -qE '^#11 Task 11: session busy, .*, active [0-9]+ d ago$' '$WORK/out'"

echo "-- on-session-start: a cleanup, then the status"
echo CLOSED >"$TASK_TEST_STATE/issue-17"
echo notes >"$ISSUE17/backend/notes.md"
check "a session start in the main checkout"   run_in "$BACKEND" on-session-start
check "finishes the closed task"               test ! -e "$ISSUE14"
check "and reports it"                         grep -qF '✓ issue 14 finished:' "$WORK/out"
check "reports a refusal and starts anyway"    grep -qF '✗ issue 17 not finished:' "$WORK/out"
check "then prints the status of what is left" bash -c "grep -q '^#17 ' '$WORK/out' && grep -q '^#11 ' '$WORK/out' && grep -q '^#13 ' '$WORK/out' && ! grep -q '^#14 ' '$WORK/out'"
check "after the cleanup's lines"              awk '/^#/ { status = 1 } status && /^(✓|✗)/ { exit 1 }' "$WORK/out"
check "and ends with the line that names /task:status" test "$(tail -n 1 "$WORK/out")" = 'In your first reply, report the status to the owner through /task:status.'
rm "$ISSUE17/backend/notes.md"
task "$BACKEND" finish 17 >/dev/null
echo CLOSED >"$TASK_TEST_STATE/issue-13"
check "a session start in a task worktree"     run_in "$ISSUE11/backend" on-session-start
check "says nothing"                           test ! -s "$WORK/out"
check "and finishes nothing"                   test -d "$ISSUE13/backend"
rm "$TASK_TEST_STATE/issue-13"
touch "$TASK_TEST_STATE/gh-down" "$TASK_TEST_STATE/claude-down"
check "a session start where no task is, with gh and claude down" run_in "$FRONTEND" on-session-start
check "says nothing: it calls neither"         test ! -s "$WORK/out"
rm "$TASK_TEST_STATE/gh-down"
check "claude agents can't answer: it still exits 0" run_in "$BACKEND" on-session-start
check "and ends saying the tasks are unknown, naming /task:status" unknown_last
rm "$TASK_TEST_STATE/claude-down"
touch "$TASK_TEST_STATE/gh-down"
check "gh can't answer: it still exits 0"      run_in "$BACKEND" on-session-start
check "and ends saying the tasks are unknown, naming /task:status" unknown_last
rm "$TASK_TEST_STATE/gh-down"

echo "-- start: a cleanup, then every other task"
ISSUE16="$WORK/repos/worktrees/16-task-16"
check "backend starts issue 16"                task "$BACKEND" start 16
echo CLOSED >"$TASK_TEST_STATE/issue-16"
check "a start"                                run_in "$BACKEND" start 15
check "finishes the closed task"               bash -c "test ! -e '$ISSUE16' && grep -qF '✓ issue 16 finished:' '$WORK/out'"
check "lists every other task, and leaves out its own" bash -c "
  grep -q '^#11 ' '$WORK/out' && grep -q '^#13 ' '$WORK/out' && ! grep -q '^#15 ' '$WORK/out'"
check "and no heading or backlog line"         bash -c "! grep -qE '^(In progress|Ready|Blocked|Parked):|^#2[0-4] ' '$WORK/out'"

echo "-- park and block: a start refuses an issue that must wait, and says why"
check "an issue parks where the label never was" task "$BACKEND" park 18 "planned in #19"
check "which creates the label"                grep -qx backlog "$TASK_TEST_STATE/repo-labels"
check "labels the issue"                       grep -qx backlog "$TASK_TEST_STATE/labels-18"
check "and gives the reason in a comment"      grep -qx 'Parked: planned in #19' "$TASK_TEST_STATE/comments-18"
refuses "a start refuses a parked issue, naming the reason" '^issue 18 is parked: planned in #19$' "$BACKEND" start 18
check "and creates nothing"                    test ! -e "$WORK/repos/worktrees/18-task-18"
echo "A comment of the owner's" >>"$TASK_TEST_STATE/comments-18"
check "a park where the label is"              task "$BACKEND" park 18 "waits for the review"
refuses "the reason named is the last one given" '^issue 18 is parked: waits for the review$' "$BACKEND" start 18
printf '18\n5\n' >"$TASK_TEST_STATE/blocked-by-19"
echo backlog >"$TASK_TEST_STATE/labels-19"
refuses "a start refuses a blocked issue, naming its open blocker only" '^issue 19 is blocked by #18$' "$BACKEND" start 19
refuses "and, parked too, the reason, even when no comment gives one" '^issue 19 is parked: no reason given$' "$BACKEND" start 19
echo CLOSED >"$TASK_TEST_STATE/issue-18"
run_in "$BACKEND" start 19
check "a block clears itself when its blocker closes" test "$(cat "$WORK/out")" = 'issue 19 is parked: no reason given'
rm "$TASK_TEST_STATE/labels-19"
check "and a released issue starts"            task "$BACKEND" start 19
check "with its worktree"                      test -d "$WORK/repos/worktrees/19-task-19/backend"

echo "-- status: every open issue, under the first heading that fits"
# By now 11, 13, 15 and 19 have a task worktree in backend, and every other issue up to 19 is closed.
echo backlog >"$TASK_TEST_STATE/labels-11"
echo backlog >"$TASK_TEST_STATE/labels-20"
echo 'Parked: planned in #19' >"$TASK_TEST_STATE/comments-20"
echo backlog >"$TASK_TEST_STATE/labels-21"
echo 'Parked: waits for the review' >"$TASK_TEST_STATE/comments-21"
echo 22 >"$TASK_TEST_STATE/blocked-by-21"
printf '20\n5\n' >"$TASK_TEST_STATE/blocked-by-22"
check "a look runs"                            run_in "$BACKEND" status
check "four headings, in order"                test "$(grep -v '^#' "$WORK/out" | tr '\n' ' ')" = 'In progress: Ready: Blocked: Parked: '
check "a task's issue only under In progress, even parked" bash -c "
  test \"\$(grep -c '^#11 ' '$WORK/out')\" -eq 1 && grep -q '^#11 Task 11: session ' '$WORK/out'"
check "ready issues, lowest number first, each with its whole title" \
  test "$(under Ready)" = "$(printf '#23 Task 23, with a title longer than the forty characters of a task line\n#24 Task 24')"
check "a blocked one, naming its open blockers" test "$(under Blocked)" = '#22 Task 22: blocked by #20'
check "a parked one with its reason, and one parked and blocked, once, naming its blocker" \
  test "$(under Parked)" = "$(printf '#20 Task 20: planned in #19\n#21 Task 21: waits for the review; blocked by #22')"
echo CLOSED >"$TASK_TEST_STATE/issue-22"
run_in "$BACKEND" status
check "a closed issue leaves, with its block and its empty heading" bash -c "
  ! grep -qE '^Blocked:|^#22 ' '$WORK/out' && grep -qx '#21 Task 21: waits for the review' '$WORK/out'"
touch "$TASK_TEST_STATE/claude-down"
check "a look where there is no task worktree, with claude down" run_in "$FRONTEND" status
check "lists the backlog, with no In progress heading" bash -c "
  ! grep -q '^In progress:' '$WORK/out' && grep -qx '#24 Task 24' '$WORK/out'"
rm "$TASK_TEST_STATE/claude-down"
check "a session start in the main checkout"   run_in "$BACKEND" on-session-start
check "prints the task lines, and no heading or backlog line" \
  test "$(sed '$d' "$WORK/out" | cut -d ' ' -f 1 | sort | tr '\n' ' ')" = '#11 #13 #15 #19 '

echo "-- usage"
refuses "no command is refused"                  '^usage:'              "$BACKEND"
refuses "a park with no reason is refused"       '^usage:'              "$BACKEND" park 18

echo "== $pass passed, $fail failed"
[ "$fail" -eq 0 ]
