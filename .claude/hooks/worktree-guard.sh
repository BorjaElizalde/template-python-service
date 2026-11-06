#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
# PreToolUse(Edit|Write|MultiEdit) worktree guard — language-agnostic:
#   refuse to edit tracked source in the PRIMARY working tree (the main checkout),
#   on ANY branch. All feature work belongs in a linked worktree under
#   WORKTREE_ROOT (../agentic.conf) — branching off in the main checkout and editing
#   there is the anti-pattern this blocks (not just editing on a protected branch). See .claude/rules/agentic.md.
# Primary vs linked is detected structurally: a linked worktree's git-dir is
# <common>/worktrees/<name>, so git-dir != git-common-dir; in the main checkout they are
# equal. Holds on any branch and for the submodule repos (git-dir under .git/modules/<name>).
# Detected from the EDITED FILE's repo, so a linked worktree is always allowed even when the
# session cwd is the main checkout, and vice-versa.
# Fails OPEN (exit 0) for: empty paths, paths outside a git repo (such as scratchpads), and
# git-ignored files (such as .env and node_modules) — only tracked source in the main
# checkout is guarded. jq reads the path from the stdin payload.
set -u
. "$(cd "$(dirname "$0")/.." && pwd)/agentic.conf"

FILE_PATH="$(jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
[ -n "$FILE_PATH" ] || exit 0

# Nearest existing ancestor dir (handles new files in not-yet-created subdirs).
d="$(dirname "$FILE_PATH")"
while [ -n "$d" ] && [ "$d" != "/" ] && [ ! -d "$d" ]; do d="$(dirname "$d")"; done
[ -d "$d" ] || exit 0

git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0   # outside git -> allow
git -C "$d" check-ignore -q -- "$FILE_PATH" 2>/dev/null && exit 0        # ignored -> allow

# Fail open if either dir can't be resolved; block only when they are equal (main checkout).
GD="$(git -C "$d" rev-parse --absolute-git-dir 2>/dev/null || true)"
CD="$(git -C "$d" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
[ -n "$GD" ] && [ -n "$CD" ] || exit 0
if [ "$GD" = "$CD" ]; then
  BRANCH="$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  echo "Blocked: refusing to edit '$FILE_PATH' in the main checkout (branch '$BRANCH'). Feature work belongs in a linked worktree — start the task with /task:start and edit under $WORKTREE_ROOT/ (.claude/rules/agentic.md)." >&2
  exit 2
fi
exit 0
