#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
# Table-driven regression suite for staleness.sh and the guard hook that reports it. Run from any
# repo checkout: bash .claude/hooks/memory/guard.test.sh
#
# Fixtures are a throwaway git repo with fake memory stores, so the suite never depends on the
# real stores' contents.
# The notes are markdown, so their backticks are text. Tried double quotes, but then each backtick
# in some thirty notes needs a backslash.
# shellcheck disable=SC2016
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
CHECKER="$HERE/staleness.sh"
HOOK="$HERE/guard.sh"
pass=0; fail=0

FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT

mkdir -p "$FIX/app/api/tools" "$FIX/tools" "$FIX/.github/workflows" \
         "$FIX/.claude/memory" "$FIX/.claude/agent-memory/some-agent"
: > "$FIX/app/config.py"
: > "$FIX/app/api/tools/search.py"
: > "$FIX/tools/release.sh"
: > "$FIX/.github/workflows/gate.yaml"

store() { printf '%s' "$FIX/.claude/agent-memory/$1"; }

topic() { # topic <store> <name> <body...>
  local s="$1" n="$2"; shift 2
  printf '%s\n' "$@" > "$FIX/.claude/agent-memory/$s/$n.md"
}

reset_store() { rm -rf "${FIX:?}/.claude/agent-memory/some-agent"; mkdir -p "$FIX/.claude/agent-memory/some-agent"; }

commit() { git -C "$FIX" add -A >/dev/null 2>&1; git -C "$FIX" commit -qm t >/dev/null 2>&1 || true; }

git -C "$FIX" init -q
git -C "$FIX" config user.email t@t; git -C "$FIX" config user.name t

t() { # t <expected-exit> <desc> <grep-pattern-or-empty>
  local exp="$1" desc="$2" pat="${3:-}" out got
  commit
  out="$(bash "$CHECKER" "$(store some-agent)" 2>&1)"; got=$?
  if [ "$got" -ne "$exp" ]; then
    fail=$((fail+1)); echo "FAIL (want exit $exp, got $got) $desc"; return
  fi
  if [ -n "$pat" ] && ! printf '%s' "$out" | grep -qF -- "$pat"; then
    fail=$((fail+1)); echo "FAIL (exit ok, missing '$pat') $desc"; return
  fi
  pass=$((pass+1)); echo "PASS ($got) $desc"
}

echo "-- accepted shapes (must pass clean)"
reset_store
printf -- '- [T](a.md)\n' > "$(store some-agent)/MEMORY.md"
topic some-agent a '---' 'name: a' 'metadata:' '  type: project' '---' 'Live path `app/config.py`.'
t 0 "agent store: metadata.type + bare index bullet"

reset_store
printf -- '- [T](a.md) — a hook suffix\n' > "$(store some-agent)/MEMORY.md"
topic some-agent a '---' 'name: a' 'metadata:' '  type: feedback' '---' 'Live path `app/config.py`.'
t 0 "main store: metadata.type + hooked index bullet"

# Negative facts ("there is no X") cite no path, and they are among the most valuable notes.
reset_store
printf -- '- [T](a.md)\n' > "$(store some-agent)/MEMORY.md"
topic some-agent a '---' 'name: a' 'metadata:' '  type: project' '---' 'There is no cache-control middleware.'
t 0 "a note citing no path is accepted"

for accepted in user feedback project reference; do
  reset_store
  printf -- '- [T](a.md)\n' > "$(store some-agent)/MEMORY.md"
  topic some-agent a '---' 'name: a' 'metadata:' "  type: $accepted" '---' 'Body.'
  t 0 "harness type '$accepted' is accepted"
done

echo "-- true positives (must fail)"
reset_store
printf -- '- [T](a.md)\n' > "$(store some-agent)/MEMORY.md"
topic some-agent a '---' 'name: a' 'metadata:' '  type: note' '---' 'Live `app/config.py`.'
t 1 "a type outside the four kinds is rejected" "[policy]"

reset_store
printf -- '- [T](a.md)\n' > "$(store some-agent)/MEMORY.md"
topic some-agent a '---' 'name: a' 'metadata:' '  type: project' '---' 'Gone: `app/gone.py`.'
t 1 "dead path reference" "[off-branch]"

reset_store
printf -- '- [T](a.md)\n' > "$(store some-agent)/MEMORY.md"
topic some-agent a '---' 'name: a' 'metadata:' '  type: project' '---' '`app/config.py` [[nope]]'
t 1 "dead wikilink" "[deadlink]"

reset_store
printf -- '- [T](a.md)\n' > "$(store some-agent)/MEMORY.md"
topic some-agent a '---' 'name: a' '---' 'No type declared. `app/config.py`'
t 1 "missing type declaration" "[policy]"

reset_store
printf -- 'not a bullet or heading\n' > "$(store some-agent)/MEMORY.md"
topic some-agent a '---' 'name: a' 'metadata:' '  type: project' '---' '`app/config.py`'
t 1 "malformed index line" "[index-detail]"

reset_store
printf -- '- [T](a.md)\n' > "$(store some-agent)/MEMORY.md"
topic some-agent a '---' 'name: a' 'metadata:' '  type: project' '---' \
  '`app/config.py` AKIAIOSFODNN7EXAMPLE'
t 1 "secret-shaped token" "[SECRET]"

# The hook routes findings to stderr, so a report that echoed a note's tokens would put a secret in
# the transcript and the session log - defeating the redaction the [SECRET] branch exists for.
reset_store
printf -- '- [T](a.md)\n' > "$(store some-agent)/MEMORY.md"
topic some-agent a '---' 'name: a' 'metadata:' '  type: project' '---' \
  'key `AKIAQQQQQQQQQQQQQQQQ` and `PlaintextDbPassword` in `app/config.py`'
commit
secret_out="$(bash "$CHECKER" "$(store some-agent)" 2>&1)"
if printf '%s' "$secret_out" | grep -qF 'AKIAQQQQQQQQQQQQQQQQ' \
  || printf '%s' "$secret_out" | grep -qF 'PlaintextDbPassword'; then
  fail=$((fail+1)); echo "FAIL a secret-bearing file echoed its tokens verbatim"
elif printf '%s' "$secret_out" | grep -qF '[SECRET]'; then
  pass=$((pass+1)); echo "PASS (1) secret-bearing file is reported without echoing its tokens"
else
  fail=$((fail+1)); echo "FAIL secret-bearing file was not reported at all"
fi

echo "-- text that is no broken reference (must pass clean)"
reset_store
printf -- '- [T](a.md)\n' > "$(store some-agent)/MEMORY.md"
topic some-agent a '---' 'name: a' 'metadata:' '  type: project' '---' \
  'Release lives in `sibling/.github/workflows/release.yaml`, ours in `.github/workflows/gate.yaml`.'
t 0 "a sibling repository's path is not this repo's, and must not be chopped into .github/"

reset_store
printf -- '- [T](a.md)\n' > "$(store some-agent)/MEMORY.md"
topic some-agent a '---' 'name: a' 'metadata:' '  type: project' '---' \
  'See `api/tools/search.py`.'
t 0 "mid-path 'tools/' segment is not a separate broken reference"

reset_store
printf -- '- [T](a.md)\n' > "$(store some-agent)/MEMORY.md"
topic some-agent a '---' 'name: a' 'metadata:' '  type: project' '---' \
  'Owner said user-curated rows win. Promotion runs on `origin/main` and `origin/staging`.' \
  'Verified 2026-08-11. `app/config.py`'
t 0 "prose is not checked: user-curated, origin/ refs and dates are not findings"

reset_store
printf -- '- [T](a.md)\n' > "$(store some-agent)/MEMORY.md"
topic some-agent a '---' 'name: a' 'metadata:' '  type: project' '---' 'Top-level `tools/release.sh`.'
t 0 "top-level tools/ path resolves"

echo "-- hook contract: git commit blocks on broken or unstaged memory"
cmd_case() { # cmd_case <expected-exit> <desc> <command> [grep-pattern]
  local exp="$1" desc="$2" c="$3" pat="${4:-}" got
  printf '{"cwd":"%s","tool_input":{"command":"%s"}}' "$FIX" "$c" \
    | CLAUDE_PROJECT_DIR="$FIX" bash "$HOOK" >"$FIX/.o" 2>"$FIX/.e"
  got=$?
  if [ "$got" -ne "$exp" ]; then
    fail=$((fail+1)); echo "FAIL (want exit $exp, got $got) $desc"; sed 's/^/      /' "$FIX/.e"; return
  fi
  if [ -n "$pat" ] && ! grep -qF -- "$pat" "$FIX/.e"; then
    fail=$((fail+1)); echo "FAIL (exit ok, missing '$pat') $desc"; sed 's/^/      /' "$FIX/.e"; return
  fi
  pass=$((pass+1)); echo "PASS ($got) $desc"
}

reset_store
printf -- '- [T](a.md)\n' > "$(store some-agent)/MEMORY.md"
topic some-agent a '---' 'name: a' 'metadata:' '  type: project' '---' 'Live `app/config.py`.'
commit
cmd_case 0 "clean tree: git commit proceeds" "git commit -m x"
cmd_case 0 "non-commit command is ignored entirely" "git status"

# Use a WELL-FORMED note, so the block can only come from the untracked rule and not from some
# other finding riding along.
topic some-agent floating '---' 'name: floating' 'metadata:' '  type: project' '---' 'Live `app/config.py`.'
cmd_case 2 "well-formed but untracked memory blocks git commit" "git commit -m x" \
  "[BLOCKING] untracked memory file"
git -C "$FIX" add .claude/agent-memory/some-agent/floating.md >/dev/null 2>&1
cmd_case 0 "staging it in a PRIOR call clears the block" "git commit -m x"

# PreToolUse reads the tree before the command runs, so a compound add+commit cannot pass.
topic some-agent floating2 '---' 'name: floating2' 'metadata:' '  type: project' '---' 'Live `app/config.py`.'
cmd_case 2 "compound 'git add && git commit' is blocked: staging is not visible yet" \
  "git add .claude/agent-memory/some-agent/floating2.md && git commit -m x" \
  "[BLOCKING] untracked memory file"

rm -f "$(store some-agent)/floating2.md"
topic some-agent broken '---' 'name: broken' 'metadata:' '  type: project' '---' 'Gone `app/gone.py`.'
git -C "$FIX" add .claude/agent-memory/some-agent/broken.md >/dev/null 2>&1
cmd_case 2 "staging does not launder a broken reference" "git commit -m x" "[off-branch]"
rm -f "$(store some-agent)/broken.md"; commit
cmd_case 0 "removing it clears the block" "git commit -m x"

printf '%s\n' '---' 'name: m' 'metadata:' '  type: reference' '---' 'Gone: `app/gone.py`.' > "$FIX/.claude/memory/m.md"
printf -- '- [M](m.md) — hook\n' > "$FIX/.claude/memory/MEMORY.md"
git -C "$FIX" add .claude/memory >/dev/null 2>&1
cmd_case 2 "the repo store .claude/memory is covered too" "git commit -m x" "[off-branch]"
rm -f "$FIX/.claude/memory/m.md" "$FIX/.claude/memory/MEMORY.md"; commit

# git collapses a wholly-untracked directory to `?? <dir>/`, so a brand-new store would present no
# *.md path at all and slip past the untracked rule.
mkdir -p "$FIX/.claude/agent-memory/brandnew"
printf -- '- [N](n.md)\n' > "$FIX/.claude/agent-memory/brandnew/MEMORY.md"
printf '%s\n' '---' 'name: n' 'metadata:' '  type: project' '---' 'Live `app/config.py`.' \
  > "$FIX/.claude/agent-memory/brandnew/n.md"
cmd_case 2 "a wholly-untracked NEW store still blocks the commit" "git commit -m x" \
  "[BLOCKING] untracked memory file"
rm -rf "$FIX/.claude/agent-memory/brandnew"; commit

echo "-- commit matcher precision"
topic some-agent probe '---' 'name: probe' 'metadata:' '  type: project' '---' 'Gone `app/gone.py`.'
cmd_case 2 "git -C <dir> commit is matched"        "git -C . commit -m x"
cmd_case 2 "git -c k=v commit is matched"          "git -c user.name=z commit -m x"
cmd_case 2 "extra whitespace is matched"           "git   commit -m x"
cmd_case 2 "a commit bash -c runs is matched"      "bash -c 'git commit -m x'"
cmd_case 0 "git log --grep=git commit is not"      "git log --grep=git commit --oneline"
rm -f "$(store some-agent)/probe.md"; commit

# A commit aimed at a DIFFERENT checkout must be checked against THAT checkout's stores, not the
# session's. Both shapes appear in this workflow, and both are commonly relative — the payload's
# `cwd` is what makes a relative one resolvable, so these also pin that it is read.
# Track it clean first, then dirty it: the commit path only inspects stores that hold changes, so a
# note committed in the same breath would leave nothing to find and pass for the wrong reason.
WT="$FIX-wt"
git -C "$FIX" worktree add -q -b wt-probe "$WT" >/dev/null 2>&1
mkdir -p "$WT/.claude/agent-memory/some-agent"
printf '%s\n' '---' 'name: wtnote' 'metadata:' '  type: project' '---' 'Live `app/config.py`.' \
  > "$WT/.claude/agent-memory/some-agent/wtnote.md"
git -C "$WT" add -A >/dev/null 2>&1; git -C "$WT" commit -qm wt3 >/dev/null 2>&1 || true
printf '%s\n' '---' 'name: wtnote' 'metadata:' '  type: project' '---' 'Gone `app/gone.py`.' \
  > "$WT/.claude/agent-memory/some-agent/wtnote.md"

cmd_case 2 "git -C <worktree> commit is checked against the WORKTREE" \
  "git -C $WT commit -m x" "[off-branch]"
cmd_case 2 "a RELATIVE git -C resolves against the payload cwd" \
  "git -C ../$(basename "$WT") commit -m x" "[off-branch]"
cmd_case 2 "cd <worktree> && git commit is checked against the WORKTREE" \
  "cd $WT && git commit -m x" "[off-branch]"

# The session's own tree is clean here, so the same command without a target must NOT block —
# proof the three above are reading the worktree rather than blocking on something ambient.
cmd_case 0 "an untargeted commit still reads the session tree" "git commit -m x"

git -C "$WT" checkout -q -- . >/dev/null 2>&1
cmd_case 0 "and a clean worktree commit proceeds" "git -C $WT commit -m x"

# A memory store in a DIFFERENT repo has its own guard and its own checker; ours must not reach in.
OTHER="$FIX-other"
mkdir -p "$OTHER/.claude/memory"
git -C "$OTHER" init -q >/dev/null 2>&1
printf '%s\n' '---' 'name: x' '---' 'No type, and `app/gone.py`.' > "$OTHER/.claude/memory/x.md"
cmd_case 0 "a commit in another repo is not ours to police" "git -C $OTHER commit -m x"
rm -rf "$OTHER"

echo
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
