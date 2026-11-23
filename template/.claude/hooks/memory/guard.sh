#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
# Memory guard, a PreToolUse hook on Bash: on `git commit`, it checks every memory store holding
# changes and tells the INTEGRATOR before the commit lands. It runs inside Claude's own hook layer,
# so the checker beside it is never reached from a build target or from CI.
#
# The exit code is the mechanism. PreToolUse surfaces stderr to Claude only on exit 2; every other
# nonzero code is a non-blocking error whose notice carries just the first stderr line, and stdout
# is never surfaced unless it parses as JSON. So ending this script with the checker call would
# inherit its exit 1 and leave the findings on stdout, where they are discarded silently.
#
# The guard inherits the checker's "untracked memory file" as BLOCKING. Be precise about what that
# enforces: this is PreToolUse, so the state it reads is the one BEFORE the command runs. It cannot
# see what the command would stage, so `git add -A` and an explicit path are indistinguishable to
# it. What it actually enforces is narrower and still worth having — a commit is blocked while
# `git status` reports an untracked `.md` under a memory store, which is what catches a memory note
# nobody ever committed.
#
# The consequence is that staging must be its own tool call. A compound
# `git add <new-note> && git commit` is blocked, because at hook time the note is still untracked.
#
# The guard may not anchor on PROJECT_DIR. Hooks register against the SESSION's root, while all
# feature work happens in a linked worktree, so a store committed in a worktree is not under
# PROJECT_DIR and a prefix test silently skips it — the guard passes by never running.
# `worktree-guard.sh` already solved this: identity is the git COMMON dir, which every linked
# worktree of one repo shares and a different repo does not. The guard resolves the commit's
# checkout, then checks it belongs to this repo family.

set -u

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "${HOOK_DIR}/../../.." && pwd)}"
CHECKER="$HOOK_DIR/staleness.sh"

# The repo a directory belongs to, worktrees collapsed onto their main checkout. Empty when the
# directory is not in git, or does not exist.
common_dir_of() { git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null; }
THIS_REPO="$(common_dir_of "$PROJECT_DIR")"

payload="$(cat 2>/dev/null || true)"
COMMAND="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
# Top-level, on every event: the working directory the event fired in — the Bash tool's PERSISTED
# cwd, which is what a relative path inside the command resolves against. Not the project root.
CWD="$(printf '%s' "$payload" | jq -r '.cwd // ""' 2>/dev/null || true)"
[ -n "$CWD" ] || CWD="$PWD"

# Relative paths in the payload resolve against CWD, exactly as the shell would resolve them.
absolutize() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$CWD" "$1" ;; esac; }

# A substring test both misses (`git  commit`, `git -c user.name=z commit`, `bash -c "git commit"`)
# and over-fires (`git log --grep="git commit"`, which would run the whole scan), so a quote
# before `git` counts only after `bash -c`, `sh -c` or `eval`.
RE_WRAPPER="((ba)?sh[[:space:]]+-c|eval)[[:space:]]+[\"']"
RE_COMMIT="(^|[[:space:]&;|]|$RE_WRAPPER)git[[:space:]]+(-[Cc][[:space:]]+[^[:space:]]+[[:space:]]+)*commit([[:space:]]|$)"
[[ "$COMMAND" =~ $RE_COMMIT ]] || exit 0
[ -x "$CHECKER" ] || [ -f "$CHECKER" ] || exit 0

# Which checkout will this commit land in? The event's own cwd by default, and `cd <dir> && …` or
# `git -C <dir> …` when the command moves — a worktree commit is always one of those. Relative
# forms are honoured too, resolved against the same cwd the shell will use. Last writer wins,
# matching how the shell resolves it.
target="$CWD"
if [[ "$COMMAND" =~ (^|[[:space:]\&\;\|])cd[[:space:]]+([^[:space:]\&\;\|]+) ]]; then
  target="$(absolutize "${BASH_REMATCH[2]}")"
fi
if [[ "$COMMAND" =~ git[[:space:]]+-[Cc][[:space:]]+([^[:space:]]+) ]]; then
  target="$(absolutize "${BASH_REMATCH[1]}")"
fi
root="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)" || root=""
[ -n "$root" ] || root="$PROJECT_DIR"
# A commit in a different repo (a submodule, a scratchpad) is not this guard's business.
[ "$(common_dir_of "$root")" = "$THIS_REPO" ] || exit 0

dirty=()
for store in "$root/.claude/memory" "$root"/.claude/agent-memory/*/; do
  [ -d "$store" ] || continue
  [ -n "$(git -C "$root" status --porcelain -- "$store" 2>/dev/null)" ] || continue
  dirty+=("$store")
done
[ ${#dirty[@]} -gt 0 ] || exit 0

if ! findings="$(bash "$CHECKER" "${dirty[@]}" 2>&1)"; then
  # Explain the staging rule here rather than in CLAUDE.md: it is only needed at the moment of the
  # block, and an agent seeing an untracked finding on a commit has no other way to work out why.
  case "$findings" in
    *"untracked memory file"*)
      findings="$findings
Stage memory in a tool call of its own, before the commit call. This check runs BEFORE your command,
so a compound \`git add <note> && git commit\` cannot pass: the note is still untracked when it runs."
      ;;
  esac
  printf 'Memory policy guard: hard findings in memory changed by this commit\n\n%s\n' "$findings" >&2
  exit 2
fi
exit 0
