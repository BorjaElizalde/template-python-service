#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
# Regression suite for task.sh. Run from any checkout: bash .claude/skills/task/scripts/task.test.sh
# Two clones of one throwaway origin, named backend and frontend, stand in for two repositories,
# each with a real tmux server of its own on a private socket folder.
# Stub sleep waits a tenth of a second, as a window's shell takes real time to start.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(cd "$(mktemp -d)" && pwd -P)"
export TASK_TEST_STATE="$WORK/state"
export CLAUDE_CONFIG_DIR="$WORK/claude"
unset CLAUDE_PID  # a start runs from no session, unless a check names the pid of one
# tmux talks to the server that TMUX names before any other, and keeps its sockets in TMUX_TMPDIR.
unset TMUX TMUX_PANE
export TMUX_TMPDIR="$WORK"
# The pid of a session this suite lists without launching it: a process of its own, never this
# suite's, and out of its jobs, so its end prints nothing.
LISTED_PID=$(sleep 3600 >/dev/null 2>&1 & echo $!)
trap 'kill "$LISTED_PID"; for socket in "$WORK"/tmux-*/*; do tmux -S "$socket" kill-server; done; rm -rf "$WORK"' EXIT
pass=0; fail=0

mkdir -p "$WORK/bin" "$TASK_TEST_STATE" "$WORK/seed/.claude/skills/task/scripts" "$WORK/seed/.claude/hooks" "$WORK/repos"
cat >"$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
[ ! -f "$TASK_TEST_STATE/gh-down" ] || exit 1
cd "$TASK_TEST_STATE" || exit 1
title() {
  case "$1" in
    42) echo "Add a retry_limit setting to the upload client" ;;
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
issue() {
  local blockers comments
  blockers=$(for m in $(cat "blocked-by-$1" 2>/dev/null); do echo "$m $(state "$m")"; done)
  comments=$(for f in "comment-$1"???; do [ ! -f "$f" ] || jq -Rs --arg url "$(comment_url "${f#comment-}")" '{url: $url, body: .}' "$f"; done | jq -s .)
  jq -n --argjson number "$1" --arg title "$(title "$1")" --arg labels "$(cat "labels-$1" 2>/dev/null)" \
    --argjson comments "$comments" --arg blockers "$blockers" '
    def lines: split("\n") | map(select(. != ""));
    {number: $number, title: $title, labels: ($labels | lines | map({name: .})),
      blockedBy: {nodes: ($blockers | lines | map(split(" ") | {number: (.[0] | tonumber), state: .[1]}))},
      comments: $comments}'
}
# A comment is the file comment-<id>, which holds its text. Its id is its issue's number, then
# three digits that count the issue's comments from 000.
comment_url() { echo "https://github.com/acme/tasks/issues/${1%???}#issuecomment-$1"; }
case "$1 $2" in
  "issue view")
    title "$3" >/dev/null || exit 1
    if [ "$7" = state,title ]; then echo "$(state "$3") $(title "$3")"; else issue "$3"; fi ;;
  "issue list")
    # The open issues, newest first, as gh lists them for --state open.
    for n in 42 {24..7} 5; do [ "$(state "$n")" != OPEN ] || issue "$n"; done | jq -s . ;;
  "issue comment")
    # Like gh, it prints the URL of the comment it posts.
    n=$3; while [ $# -gt 0 ]; do [ "$1" != --body ] || body=$2; shift; done
    id=$n$(printf '%03d' "$(find . -name "comment-$n???" | wc -l)")
    printf '%s' "$body" >"comment-$id"
    comment_url "$id" ;;
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
  "api -X")
    id=${4#repos/acme/tasks/issues/comments/}
    case "$3 $id" in
      "PATCH "*) printf '%s' "${6#body=}" >"comment-$id" ;;
      "PUT "*/pin) id=${id%/pin}; echo "$id" >"pinned-${id%???}" ;;
      *) exit 1 ;;
    esac ;;
  "pr list")
    while [ $# -gt 0 ]; do case "$1" in --head) branch=$2 ;; --state) state=$2 ;; esac; shift; done
    if [ "$state" = merged ]; then
      grep -qxF "$branch" "$TASK_TEST_STATE/merged" 2>/dev/null && echo 1
    else
      cat "$TASK_TEST_STATE/pr-${branch//\//-}" 2>/dev/null || echo '[]'
    fi
    exit 0 ;;
  *) exit 1 ;;
esac
EOF
# A tmux window's login shell, as zsh is with a chpwd hook: it runs each line typed on its tty,
# where a line past MAX_CANON never arrives whole, and each cd it runs exports HOOK_FOLDER, the
# folder it entered.
cat >"$WORK/bin/window-shell" <<'EOF'
#!/usr/bin/env bash
cd() { builtin cd "$@" && export HOOK_FOLDER=$PWD; }
while IFS= read -r line; do eval "$line"; done
EOF
# claude agents --json, as Claude Code prints it; any other call launches a session. A launch's
# arguments each end in a NUL, since the system prompt spans lines.
cat >"$WORK/bin/claude" <<'EOF'
#!/usr/bin/env bash
if [ "$*" != "agents --json" ]; then
  [ ! -f "$TASK_TEST_STATE/no-start" ] || exit 1
  printf '%s\0' "$@" >"$TASK_TEST_STATE/launched"
  echo "${*//$'\n'/ }" >>"$TASK_TEST_STATE/launches"
  echo $$ >"$TASK_TEST_STATE/claude-pid"
  echo "${HOOK_FOLDER:-}" >"$TASK_TEST_STATE/hook-folder"
  echo "$(pwd -P) $$" >>"$TASK_TEST_STATE/running"
  while read -r _; do :; done
  exit 0
fi
[ ! -f "$TASK_TEST_STATE/claude-down" ] || exit 1
[ -f "$TASK_TEST_STATE/running" ] || { echo '[]'; exit 0; }
while read -r folder pid status; do
  if kill -0 "$pid" 2>/dev/null; then echo "$folder $pid $status"; fi
done <"$TASK_TEST_STATE/running" | jq -Rn '[inputs | capture("^(?<cwd>[^ ]+) (?<pid>[0-9]+) (?<status>.*)$")] | map(
  {id: "b0b0b0b0", cwd: .cwd, kind: "background", name: "a background session", state: "blocked"},
  {pid: (.pid | tonumber), cwd: .cwd, kind: "interactive", name: "a task session", status: (if .status == "" then "busy" else .status end)})'
EOF
printf '#!/usr/bin/env bash\nexec %s 0.1\n' "$(command -v sleep)" >"$WORK/bin/sleep"
chmod +x "$WORK/bin/gh" "$WORK/bin/window-shell" "$WORK/bin/claude" "$WORK/bin/sleep"
export PATH="$WORK/bin:$PATH" SHELL="$WORK/bin/window-shell"
echo CLOSED >"$TASK_TEST_STATE/issue-5"

cp "$HERE/task.sh" "$WORK/seed/.claude/skills/task/scripts/"
cp "$HERE/../../../hooks/pr-checks.jq" "$WORK/seed/.claude/hooks/"
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
tmux_main() { tmux -L "$(basename "$1")" new-session -d -s "$(basename "$1")" -n main -c "$1"; }  # repository $1's tmux, as make claude starts it
has_window() { tmux -L "$1" list-windows -F '#{window_name}' | grep -qxF "$2"; }  # has_window <repository> <window>: in its tmux
in_view() { test "$(tmux -L "$1" list-windows -f '#{window_active}' -F '#{window_name}')" = main; }  # main is the window in view
closes() {  # closes <repository> <window>: that window of the repository's tmux closes within 3 seconds
  for _ in {1..30}; do
    has_window "$@" || return 0
    sleep
  done
  return 1
}
sessions_exit() {  # every running session exits, and its window closes; each repository's main window stays
  local socket
  for socket in "$WORK"/tmux-*/*; do tmux -S "$socket" kill-window -a -t main; done
  rm -f "$TASK_TEST_STATE/running"
}
launched() { jq -e -Rs 'split("\u0000")[:-1] | '"$1" "$TASK_TEST_STATE/launched"; }  # launched <jq filter>: over the last launch's arguments
launched_arg() { launched ".[index(\"$1\") + 1]" | jq -r .; }  # the value the launch gave option $1
# launches_in execution|design: the session last opened launches in that mode.
launches_in() {
  local settings
  settings="$(launched_arg --settings)"
  [ ! -f "$settings" ] || settings="$(cat "$settings")"
  jq -e '.hooks.PermissionRequest' <<<"$settings" && [ "$(launched_arg --disallowed-tools)" = AskUserQuestion ] &&
    [ "$(launched_arg --append-system-prompt)" = "$(cat "$SESSION/prompt.md" "$SESSION/$1.md")" ] &&
    jq -e --arg mode "$1" '.hooks | has("Stop") == ($mode == "execution")' <<<"$settings"
}
# The session last opened runs claude interactively, as its window's only process.
interactive() {
  launched 'all(.[]; . != "-p" and . != "--print")' &&
    tmux -L backend list-panes -a -F '#{pane_pid}' | grep -qxF "$(cat "$TASK_TEST_STATE/claude-pid")"
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

ISSUE42="$WORK/repos/worktrees/42-add-a-retry-limit-setting-to-the-upload"
ISSUE7="$WORK/repos/worktrees/7-second-task"

echo "-- start: one folder per issue, one subfolder per repository"
tmux_main "$BACKEND"
check "backend starts issue 42"                run_in "$BACKEND" start 42
check "the worktree is <root>/<n>-<slug>/backend" test -d "$ISSUE42/backend"
check "its branch is feat/<n>-<slug>"          test "$(branch_of "$ISSUE42/backend")" = feat/42-add-a-retry-limit-setting-to-the-upload
check "it branches off origin/develop"         git -C "$ISSUE42/backend" merge-base --is-ancestor origin/develop HEAD
check "the main checkout's memory points at it" test "$(memory_of "$BACKEND")" = "$BACKEND/.claude/memory"
check "its session opens with the issue name"  test "$(sessions '#42 backend: Add a retry_limit setting to the upload')" -eq 1
check "and the start names its mode"           grep -qxF '✓ session opened in execution mode: #42 backend: Add a retry_limit setting to the upload' "$WORK/out"
check "with a first prompt that reads its issue" bash -c "tail -n 1 '$TASK_TEST_STATE/launches' | grep -qF 'gh issue view 42 -R acme/tasks --json title,body,comments'"
check "and names no orchestrator, as no session runs the start" bash -c "! tail -n 1 '$TASK_TEST_STATE/launches' | grep -qF 'Your orchestrator'"
check "an interactive claude, never -p or --print, its window's only process" interactive
check "in window #42 of backend's tmux"        has_window backend '#42'
check "behind the main window, still in view"  in_view backend
check "with the folder hooks of its window's shell run in its worktree" test "$(cat "$TASK_TEST_STATE/hook-folder")" = "$ISSUE42/backend"
check "in execution mode: no question tool, a Stop hook, permission prompts denied" launches_in execution
sessions_exit
check "starting again resumes, creates nothing" task "$BACKEND" start 42
check "the session opens a second time"        test "$(sessions '#42 backend:')" -eq 2
check "both fresh: no transcript exists yet"   bash -c "! grep -q -- --continue '$TASK_TEST_STATE/launches'"
refuses "a start where the repository's tmux does not run" 'start the main session with make claude' "$FRONTEND" start 42
check "starts no tmux of its own"              bash -c "! tmux -L frontend has-session"
tmux_main "$FRONTEND"
check "frontend joins the same issue folder"   task "$FRONTEND" start 42
check "side by side, no collision"             test -d "$ISSUE42/frontend"
check "in window #42 of frontend's own tmux"   has_window frontend '#42'
check "a start inside a worktree"              task "$ISSUE42/backend" start 7 fix
check "resolves from the main checkout"        test -d "$ISSUE7/backend"
check "and takes the branch type"              test "$(branch_of "$ISSUE7/backend")" = fix/7-second-task
check "a fix launches in execution mode too"   launches_in execution
refuses "a closed issue does not start"          'is CLOSED'            "$BACKEND" start 5

echo "-- start: an existing issue picks up its session"
transcript "$ISSUE42/backend"
sessions_exit
echo "$BACKEND $LISTED_PID" >"$TASK_TEST_STATE/running"
CLAUDE_PID=$LISTED_PID check "a session with a transcript, started from a session in the main checkout" task "$BACKEND" start 42
check "resumes it with --continue"             launched 'index("--continue") != null'
check "and the same first prompt"              bash -c "tail -n 1 '$TASK_TEST_STATE/launches' | grep -qF 'Work on issue #42 in acme/tasks.'"
check "which names that session its orchestrator" bash -c "tail -n 1 '$TASK_TEST_STATE/launches' | grep -qF 'Your orchestrator, the session that started this task, is \`a task session\`.'"
check "still interactive"                      interactive
check "a running session"                      run_in "$BACKEND" start 42
check "is left where it runs"                  grep -qxF '✓ session already running in execution mode: #42 backend: Add a retry_limit setting to the upload' "$WORK/out"
check "and never opened twice"                 test "$(sessions '#42 backend:')" -eq 3
check "while the main window stays in view"    in_view backend
sessions_exit

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
check "in design mode: no question tool, no Stop hook, permission prompts denied" launches_in design
transcript "$ISSUE25/backend"
sessions_exit
check "a start with no type"                   run_in "$BACKEND" start 25
check "resumes it in design mode"              grep -qxF '✓ session resumed in design mode: #25 backend: Design the next step' "$WORK/out"
check "and launches it so"                     launches_in design
check "a start with another type"              run_in "$BACKEND" start 25 feat
check "finds the running session, still in design mode" grep -qxF '✓ session already running in design mode: #25 backend: Design the next step' "$WORK/out"
run_in "$BACKEND" status
check "the status line of a design task says so" test "$(status_line 25)" = '#25 Design the next step: design mode, session busy, no PR, active 0 min ago'
check "and an execution task's names no mode"  bash -c "grep -q '^#42 ' '$WORK/out' && ! grep -q '^#42 .*mode' '$WORK/out'"
sessions_exit
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
# The length comes from the folders above the repository: a tmux socket's path, which holds the
# repository's name, holds about 100 bytes.
LONG="$WORK/$(printf 'long-%.0s' {1..30})/backend"
ISSUE26="$(dirname "$LONG")/worktrees/26-design-a-launch-longer-than-a-tty-line/backend"
git clone -q "$WORK/origin.git" "$LONG"
check "a design task in a repository with a long path" run_in "$LONG" start 26 design
check "has a command over 1024 bytes"          test "$(wc -c <"$(git -C "$ISSUE26" rev-parse --absolute-git-dir)/task-session.sh")" -gt 1024
check "and its session runs"                   grep -qxF "✓ session opened in design mode: #26 backend: Design a launch longer than a tty line" "$WORK/out"
check "in design mode"                         launches_in design
check "its window's only process"              interactive
sessions_exit
touch "$TASK_TEST_STATE/no-start"
check "a start whose session never runs fails" bash -c "! (cd '$LONG' && bash .claude/skills/task/scripts/task.sh start 26) >'$WORK/out' 2>&1"
check "says why, and never that a session opened" bash -c "
  tail -n 1 '$WORK/out' | grep -q '^no session runs in .* 30 seconds after its launch: ' && ! grep -q '^✓ session' '$WORK/out'"
check "and its window has closed"              closes backend '#26'
rm "$TASK_TEST_STATE/no-start"

echo "-- finish: refused while anything would be lost"
refuses "an open issue does not finish"          'still open'           "$BACKEND" finish 42
check "a task whose session runs"              task "$BACKEND" start 42
echo CLOSED >"$TASK_TEST_STATE/issue-42"
echo notes >"$ISSUE42/backend/notes.md"
refuses "untracked files block it"               'untracked files'      "$BACKEND" finish 42
check "and the worktree stays"                 test -f "$ISSUE42/backend/notes.md"
check "and so does its session"                has_window backend '#42'
rm "$ISSUE42/backend/notes.md"
commit "$ISSUE42/backend"
refuses "unpushed commits block it"              'push them first'      "$BACKEND" finish 42
git -C "$ISSUE42/backend" push -q origin HEAD 2>/dev/null

echo "-- finish: closed issue, nothing unshipped"
check "a pushed branch finishes"               task "$BACKEND" finish 42
check "its session ended, and its window closed" closes backend '#42'
check "its worktree is gone"                   test ! -e "$ISSUE42/backend"
check "its local branch is gone"               bash -c "! git -C '$BACKEND' rev-parse -q --verify feat/42-add-a-retry-limit-setting-to-the-upload"
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

echo "-- cleanup: finishes every task whose issue is closed"
ISSUE8="$WORK/repos/worktrees/8-task-8"
ISSUE9="$WORK/repos/worktrees/9-task-9"
ISSUE10="$WORK/repos/worktrees/10-task-10"
check "backend starts issue 8"                 task "$BACKEND" start 8
check "and issue 9"                            task "$BACKEND" start 9
check "and issue 10"                           task "$BACKEND" start 10
echo CLOSED >"$TASK_TEST_STATE/issue-8"
echo CLOSED >"$TASK_TEST_STATE/issue-9"
echo notes >"$ISSUE8/backend/notes.md"
check "a cleanup goes on past a refused finish" run_in "$BACKEND" cleanup
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
check "a cleanup from the task's own session"  run_in "$ISSUE10/backend" cleanup
check "refuses the finish of its own worktree" grep -qx '✗ issue 10 not finished: finish issue 10 from outside its worktree: .*' "$WORK/out"
check "which stays"                            test -d "$ISSUE10/backend"
run_in "$BACKEND" cleanup
check "until a cleanup from the main checkout" test ! -e "$ISSUE10"

echo "-- status: every task in one view, and it only reads"
ISSUE11="$WORK/repos/worktrees/11-task-11"
ISSUE13="$WORK/repos/worktrees/13-task-13"
ISSUE14="$WORK/repos/worktrees/14-task-14"
ISSUE17="$WORK/repos/worktrees/17-task-17"
check "backend starts issue 11"                task "$BACKEND" start 11
check "and issue 13"                           task "$BACKEND" start 13
check "and issue 14"                           task "$BACKEND" start 14
check "and issue 17"                           task "$BACKEND" start 17
echo CLOSED >"$TASK_TEST_STATE/issue-14"
echo "$ISSUE11/backend $LISTED_PID idle" >"$TASK_TEST_STATE/running"
transcript "$ISSUE11/backend" old 200001010000
transcript "$ISSUE11/backend"
PENDING='{"__typename": "CheckRun", "name": "lint", "status": "IN_PROGRESS", "conclusion": ""}'
FAILED='{"__typename": "CheckRun", "name": "test", "status": "COMPLETED", "conclusion": "FAILURE"}'
CONTEXT='{"__typename": "StatusContext", "context": "ci", "state": "SUCCESS"}'
pr_from feat/11-task-11 OPEN false "[$PENDING, $CONTEXT]"
check "a look runs"                            run_in "$BACKEND" status
check "a task's session, PR, checks and last write" test "$(status_line 11)" = "#11 Task 11: session idle, PR #21 open, checks pending, active 0 min ago"
check "a task with none of them yet, marked"   test "$(status_line 13)" = "#13 Task 13: no session, no PR, no transcript, needs attention"
check "it finishes no task whose issue closed" test -d "$ISSUE14/backend"
check "and lists it"                           test -n "$(status_line 14)"
check "it opens with the In progress heading"  test "$(head -n 1 "$WORK/out")" = 'In progress:'
check "under which is one line per task"       test "$(under 'In progress' | grep -c '^#[0-9]* Task [0-9]*: ')" -eq 4 -a "$(under 'In progress' | wc -l)" -eq 4
pr_from feat/11-task-11 OPEN true "[$FAILED, $CONTEXT]"
run_in "$BACKEND" status
check "a draft, with the verdict on its checks" bash -c "grep -qF '#11 Task 11: session idle, PR #21 draft, checks failed,' '$WORK/out'"
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
echo "$ISSUE11/backend $LISTED_PID waiting" >"$TASK_TEST_STATE/running"
run_in "$BACKEND" status
check "a waiting session at once"              bash -c "grep -qE '^#11 Task 11: session waiting, .*, needs attention$' '$WORK/out' && ! grep -qE '^#13 .*needs attention' '$WORK/out'"
echo "$ISSUE11/backend $LISTED_PID" >"$TASK_TEST_STATE/running"
transcript "$ISSUE11/backend" session 200001010000
transcript "$ISSUE11/backend" old 200001010000
run_in "$BACKEND" status
check "never a busy one, however long ago it wrote" bash -c "grep -qE '^#11 Task 11: session busy, .*, active [0-9]+ d ago$' '$WORK/out'"

echo "-- on-session-start: sends the session to /task:status, which runs the cleanup and the status"
echo CLOSED >"$TASK_TEST_STATE/issue-17"
touch "$TASK_TEST_STATE/gh-down" "$TASK_TEST_STATE/claude-down"
check "a session start in the main checkout, with gh and claude down" run_in "$BACKEND" on-session-start
check "prints only the line that names /task:status" test "$(cat "$WORK/out")" = 'In your first reply, report the status to the owner through /task:status.'
check "and finishes nothing"                   bash -c "test -d '$ISSUE14/backend' && test -d '$ISSUE17/backend'"
check "a session start in a task worktree"     run_in "$ISSUE11/backend" on-session-start
check "says nothing"                           test ! -s "$WORK/out"
check "a session start where no task is"       run_in "$FRONTEND" on-session-start
check "says nothing either"                    test ! -s "$WORK/out"
rm "$TASK_TEST_STATE/gh-down" "$TASK_TEST_STATE/claude-down"
run_in "$BACKEND" cleanup

echo "-- start: leaves the cleanup and the status to /task:status"
ISSUE16="$WORK/repos/worktrees/16-task-16"
check "backend starts issue 16"                task "$BACKEND" start 16
echo CLOSED >"$TASK_TEST_STATE/issue-16"
check "a start"                                run_in "$BACKEND" start 15
check "finishes no task, and prints no task line" bash -c "test -d '$ISSUE16/backend' && ! grep -q '^#' '$WORK/out'"
run_in "$BACKEND" cleanup

echo "-- park and block: a start refuses an issue that must wait, and says why"
check "an issue parks where the label never was" task "$BACKEND" park 18 "planned in #19"
check "which creates the label"                grep -qx backlog "$TASK_TEST_STATE/repo-labels"
check "labels the issue"                       grep -qx backlog "$TASK_TEST_STATE/labels-18"
check "and gives the reason in a comment"      test "$(cat "$TASK_TEST_STATE/comment-18000")" = 'Parked: planned in #19'
refuses "a start refuses a parked issue, naming the reason" '^issue 18 is parked: planned in #19$' "$BACKEND" start 18
check "and creates nothing"                    test ! -e "$WORK/repos/worktrees/18-task-18"
printf '%s' "A comment of the owner's" >"$TASK_TEST_STATE/comment-18001"
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
printf '%s' 'Parked: planned in #19' >"$TASK_TEST_STATE/comment-20000"
echo backlog >"$TASK_TEST_STATE/labels-21"
printf '%s' 'Parked: waits for the review' >"$TASK_TEST_STATE/comment-21000"
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

echo "-- plan: a task's design, the one pinned comment of its issue"
# The heading of the owner's comment only starts like a plan's.
OWNERS="$(printf '## Planning, in the words of the owner\n\nA note.')"
printf '%s' "$OWNERS" >"$TASK_TEST_STATE/comment-24000"
printf 'Build one thing.\n' >"$ISSUE11/backend/plan.md"
check "a session posts its plan, from a path relative to its folder" run_in "$ISSUE11/backend" plan 24 plan.md
check "as a comment headed Plan, which says whose words it holds, then the file's text" test "$(cat "$TASK_TEST_STATE/comment-24001")" = \
  "$(printf '%s\n\n%s\n\n%s' '## Plan' '_The design this task builds. Its session chose it and keeps it current here; it is not a decision of the owner._' 'Build one thing.')"
check "the issue's pinned comment"             test "$(cat "$TASK_TEST_STATE/pinned-24")" = 24001
rm "$TASK_TEST_STATE/pinned-24"
printf 'Build another thing.\n\n### Changes\n\n- Another thing: the first one failed.\n' >"$WORK/plan.md"
check "a plan posted again"                    task "$BACKEND" plan 24 "$WORK/plan.md"
check "replaces the text of that comment"      grep -qx -- '- Another thing: the first one failed.' "$TASK_TEST_STATE/comment-24001"
check "under the same two lines"               test "$(head -n 1 "$TASK_TEST_STATE/comment-24001")" = '## Plan'
check "adds no second comment"                 test ! -e "$TASK_TEST_STATE/comment-24002"
check "and pins it again, where the pin was lost" test "$(cat "$TASK_TEST_STATE/pinned-24")" = 24001
check "the owner's comment stays as it was"    test "$(cat "$TASK_TEST_STATE/comment-24000")" = "$OWNERS"
refuses "a file that is not there posts no plan" 'No such file'         "$BACKEND" plan 23 "$WORK/none.md"
check "not even an empty one"                  test ! -e "$TASK_TEST_STATE/comment-23000"

echo "-- usage"
refuses "no command is refused"                  '^usage:'              "$BACKEND"
refuses "a park with no reason is refused"       '^usage:'              "$BACKEND" park 18
refuses "a plan with no file is refused"         '^usage:'              "$BACKEND" plan 24

echo "== $pass passed, $fail failed"
[ "$fail" -eq 0 ]
