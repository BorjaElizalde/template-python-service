---
name: finish
description: Use when a task is done — closes its issue once the result is delivered, closes its session, and removes its worktree and branches. With no task named, finishes every task whose issue is closed.
allowed-tools: Bash(gh issue view:*), Bash(gh issue close:*), Bash(gh pr list:*), Bash(bash:*)
---

Run this from the main checkout's session, never from the task's own session: it closes that
session and deletes its folder. A task that spans repositories is finished once in each; the issue
closes with the first.

Given no issue number, run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/task.sh" sweep` in place of the
steps below. It runs step 3 for every task of this checkout whose issue is closed, such as one
whose PR merged on GitHub, reports each refusal and goes on, and skips open issues. Return what it
finished and each refusal.

1. Read the issue with `gh issue view <n> -R BorjaElizalde/template-python-service --json state,title,comments` and its
   PRs with `gh pr list --state all --search "BorjaElizalde/template-python-service#<n>"`.
2. An open issue closes only once its result is delivered: a merged PR that names it, or, for a
   research task, a result comment on the issue. Close it with
   `gh issue close <n> -R BorjaElizalde/template-python-service --comment "<where the result is>"`. When the result is
   not delivered, stop and say what is missing.
3. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/task.sh" finish <n>`. It removes the worktree and
   every local branch of the issue, `*/<n>-*`, and leaves remote branches to GitHub. It refuses
   while one of those branches has commits on no remote branch and in no merged PR, or while the
   worktree has uncommitted or untracked files. Report the refusal and stop: never force a
   removal, and leave moving the work to the task's own session.
4. Return what was closed and removed.
