---
name: pull-request
description: Use when committed and validated feature-branch work is ready for a PR into `develop`.
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
3. Look for an open PR with the same head and base, so that no duplicate opens.
4. Bring the branch up to date with `git fetch origin develop`, then
   `git merge --no-edit origin/develop`: a PR whose branch lacks `develop`'s newest commits opens
   with a failed `up-to-date` check. When the merge changes the tree or stops on a conflict, stop
   and report it: the gate must pass on the result first.
5. Push with `git push -u origin HEAD`: a new worktree's branch tracks its base,
   `origin/develop`, until then.
6. Read `git diff origin/develop...HEAD` and, when the branch is named `<type>/<n>-<slug>`, its
   task issue: `gh issue view <n> -R BorjaElizalde/template-python-service --json title,body,comments`. Write the
   PR's text as the writing rule in `.claude/rules/` says. Then run
   `gh pr create --base develop --draft`, or `gh pr edit <n>` on the open PR, with an
   imperative title (≤72 characters) and a body a person can follow without the diff open:
   - Open with why the PR exists: the problem it solves, or the need behind it.
   - Then say what it changes, in plain prose.
   - Where the change departs from the task's plan, the issue's comment headed `Plan`, say where
     and why. The plan's `Changes` say what changed since the session first posted it.
   - Leave out a test plan and the gate result.
   - On a `<type>/<n>-<slug>` branch, add `Closes BorjaElizalde/template-python-service#<n>`: task issues
     live in that repo.
7. Mark the PR ready with `gh pr ready <n>`, unless the caller said to stop before this step: a
   task's session does, until its review steps end. Until then the PR is a draft, which nobody
   can merge and the gate skips: the gate runs on the head the PR has when it is marked ready.
8. Return the PR URL.
