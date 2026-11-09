---
name: start
description: Use to start, open or resume the session of any task or subagent — a new task, or an existing issue with or without a worktree or a session. Finds or creates the issue, creates or reuses its worktree, and opens, resumes or brings forward its session.
allowed-tools: Bash(gh issue list:*), Bash(gh issue view:*), Bash(gh issue create:*), Bash(bash:*)
---

Every subagent session belongs to one issue in BorjaElizalde/template-python-service and works in its own worktree,
research tasks included: the worktree is the agent's workspace for notes, test runs and drafts.
The same steps start a new task and pick up an existing one.

1. Find the issue. Given a number, use it. Otherwise search the open issues with
   `gh issue list -R BorjaElizalde/template-python-service --state open --search "<keywords>"` and reuse one that
   covers the task. Otherwise create one with `gh issue create -R BorjaElizalde/template-python-service`: an imperative
   title, and a body that states the goal, the scope, and what done means. For a research task,
   also say where its result goes: a PR, or a comment on the issue. The issue is the session's
   whole brief: it sees nothing of the conversation that started it, so the body carries every
   decision already taken and what the conversation found out. On an existing issue, add what was
   settled since as a comment.
2. Pick the branch type: `feat`, `fix`, `refactor` or `chore` for a change, `research` for a task
   whose result is an answer. It names a new branch only: an issue that has a branch keeps it.
3. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/task.sh" start <n> <type>`. It first finishes every
   task whose issue is closed, as a bare `/task:finish` does. Then it picks up what the issue
   already has:
   - its worktree, else its branch (left without a worktree, or pushed from another clone), else
     a new branch from `origin/develop`;
   - its running session, brought to the front and never opened twice, else its last session,
     resumed, else a new one.

   A new or resumed session starts with a prompt that sends it to the issue and its comments. A
   running session gets no prompt: send it what changed with SendMessage.
4. Return the issue URL, the worktree path, the session name, what the script picked up, and the
   tasks it finished or refused to finish.
