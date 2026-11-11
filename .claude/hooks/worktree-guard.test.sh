#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
# Table-driven regression suite for worktree-guard.sh (the copy sitting next to this file).
# Run from any repo checkout: bash .claude/hooks/worktree-guard.test.sh
# Exit 2 = guard blocked, 0 = guard allowed. A throwaway repository stands in for the project: its
# main checkout, with a submodule, and a linked worktree.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
pass=0; fail=0

# The guard reads WORKTREE_ROOT from the agentic.conf beside its folder. Its copy runs beside a
# fixture answer, so the cases never depend on the answers this project was rendered with.
mkdir -p "$WORK/.claude/hooks" "$WORK/scratch"
cp "$HERE/worktree-guard.sh" "$WORK/.claude/hooks/"
printf 'WORKTREE_ROOT=../trees\n' >"$WORK/.claude/agentic.conf"
GUARD="$WORK/.claude/hooks/worktree-guard.sh"

g() { git -c user.name=t -c user.email=t@t -c protocol.file.allow=always "$@"; }
MAIN="$WORK/repo"
WT="$WORK/trees/1-task/repo"
g init -q -b develop "$WORK/lib"
echo lib >"$WORK/lib/lib.txt"
g -C "$WORK/lib" add -A
g -C "$WORK/lib" commit -qm lib
g init -q -b develop "$MAIN"
mkdir -p "$MAIN/src"
echo app >"$MAIN/src/app.py"
printf '.env\nnode_modules/\n' >"$MAIN/.gitignore"
g -C "$MAIN" add -A
g -C "$MAIN" submodule add -q "$WORK/lib" lib
g -C "$MAIN" commit -qm init
g -C "$MAIN" worktree add -q -b feat/1-task "$WT"

# A block explains itself on stderr; an allowed edit goes on in silence.
guard_case() {  # guard_case <want> <desc> <payload> [<folder the session runs in>]
  local want="$1" out got
  out="$(cd "${4:-$WORK}" && bash "$GUARD" <<<"$3" 2>&1)"
  got=$?
  if [ "$got" -eq "$want" ] && { [ "$got" -eq 2 ] || [ -z "$out" ]; }; then
    pass=$((pass+1)); echo "PASS ($got) $2"
  else fail=$((fail+1)); echo "FAIL (want $want, got $got) $2 :: $out"; fi
}
edit() { jq -n --arg p "$1" '{tool_input:{file_path:$p}}'; }
t() { guard_case "$1" "$2" "$(edit "$3")" "${4:-}"; }
says() {  # says <phrase> <desc> <file_path>: the guard blocks, its stderr naming <phrase>
  local out
  out="$(cd "$WORK" && edit "$3" | bash "$GUARD" 2>&1 >/dev/null)"
  if [[ "$out" == *"$1"* ]]; then pass=$((pass+1)); echo "PASS (says) $2"
  else fail=$((fail+1)); echo "FAIL (want '$1') $2 :: $out"; fi
}

echo "-- the main checkout: any file git would track is blocked"
t 2 "a tracked file"                              "$MAIN/src/app.py"
t 2 "a new file"                                  "$MAIN/src/new.py"
t 2 "a new file in folders not yet made"          "$MAIN/src/a/b/new.py"
t 2 "a file of a submodule"                       "$MAIN/lib/lib.txt"
t 2 "from a session in a linked worktree"         "$MAIN/src/app.py" "$WT"
says "in the main checkout (branch 'develop')"    "the block names the file's branch" "$MAIN/src/app.py"
says "edit under ../trees/"                       "and where the worktrees go"        "$MAIN/src/app.py"
g -C "$MAIN" switch -q -c feat/in-main
t 2 "on a feature branch too"                     "$MAIN/src/app.py"
says "(branch 'feat/in-main')"                    "the block names that branch"       "$MAIN/src/app.py"

echo "-- a linked worktree: allowed"
t 0 "a tracked file"                              "$WT/src/app.py"
t 0 "a new file in folders not yet made"          "$WT/src/a/b/new.py"
t 0 "from a session in the main checkout"         "$WT/src/app.py" "$MAIN"

echo "-- fails open"
guard_case 0 "no payload"                         ''
guard_case 0 "a payload that is not JSON"         'not json'
guard_case 0 "no file_path"                       '{"tool_input":{}}'
t 0 "an empty file_path"                          ''
t 0 "a file outside any git repository"           "$WORK/scratch/notes.md"
t 0 "a file in a folder that is nowhere"          "/no-such-folder/notes.md"
t 0 "a git-ignored file in the main checkout"     "$MAIN/.env"
t 0 "a new file in an ignored folder not yet made" "$MAIN/node_modules/pkg/index.js"

echo "== $pass passed, $fail failed"
[ "$fail" -eq 0 ]
