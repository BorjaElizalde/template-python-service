---
name: pull-request
description: Use when committed and validated feature-branch work is ready for a PR into `develop`.
model: haiku
effort: high
allowed-tools: Bash(git branch:*), Bash(git rev-parse:*), Bash(git status:*), Bash(git fetch origin develop:*), Bash(git diff:*), Bash(git log:*), Bash(git push:*), Bash(gh issue view:*), Bash(gh pr list:*), Bash(gh pr create:*)
---

## Branch context

- Current branch: !`git branch --show-current`
- Upstream: !`git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo "(none)"`
- Working tree: !`git status --short`
- Commits vs develop: !`git fetch origin develop --quiet 2>/dev/null; git --no-pager log origin/develop..HEAD --oneline 2>/dev/null`
- Diff stat vs develop: !`git --no-pager diff origin/develop...HEAD --stat 2>/dev/null`

## Your task

1. Stop on `develop`, `staging`, or `main`; a dirty tree; or an empty diff from `origin/develop`.
2. Require a current-session green `/gate` result for the current tree fingerprint. Stop if absent.
3. Return any open PR with the same head and base instead of creating a duplicate.
4. Push with `git push -u origin HEAD` unless the upstream is already
   `origin/<current-branch>`; new worktrees initially track their base, `origin/develop`.
5. Read `git diff origin/develop...HEAD` and, when the branch is named `<type>/<n>-<slug>`, its
   task issue: `gh issue view <n> -R BorjaElizalde/template-python-service`. Then run
   `gh pr create --base develop` with an imperative title (≤72 characters) and a body a person
   can follow without the diff open:
   - Open with why the PR exists: the problem it solves, or the need behind it.
   - Then say what it changes, in plain prose.
   - Leave out a test plan and the gate result.
   - On a `<type>/<n>-<slug>` branch, add `Closes BorjaElizalde/template-python-service#<n>`: task issues
     live in that repo.
6. Return the PR URL.
