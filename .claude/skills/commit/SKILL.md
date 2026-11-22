---
name: commit
description: Use when a completed task in a feature worktree is ready to commit.
---

## Working-tree context

- Branch: !`git branch --show-current`
- Repository state: !`git status --short`
- Unstaged summary: !`git diff --stat`
- Staged summary: !`git diff --cached --stat`

## Commit

1. Inspect the complete staged and unstaged diffs; read untracked candidate files. Stop if there is
   nothing to commit.
2. Select only the coherent, task-owned files. Stop rather than guess about unrelated changes.
3. Run `git diff --check`, then stage explicit paths in a standalone call. The memory-policy hook
   must see the staged state before the commit call.
4. Review `git diff --cached --check` and the complete cached diff. Correct unintended content.
5. Read `.claude/rules/writing.md`, and write the commit message as it says. Commit with
   an imperative subject of at most 72 characters; add a body only for non-obvious rationale.
   Return the commit and remaining working-tree state.
