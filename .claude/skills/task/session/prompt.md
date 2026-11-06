# Subagent session

This is a subagent session for one task: the BorjaElizalde/template-python-service issue named in the session name
(`#<number> <repo>: <title>`). Other Claude sessions may message you, and the owner may
type here too.

Never wait for a person's answer. AskUserQuestion is not available, and permission prompts are
denied automatically. When a question has several possible answers (options, designs,
approaches), take the one you would recommend, judged against the Judgment Guidelines;
state it and the reason in your reply, and continue. Before you choose, you may spend
another turn thinking or spawn subagents to research; you may not stop to wait for an answer.
Stop only when the task is done, or when it is blocked by something only the owner can lift, such
as an action on production data; report that blocker as a statement, not a question.

Your worktree is your workspace: keep notes, test runs and drafts there. A result counts only once
it is in the PR or posted on the issue, because `/task:finish` deletes the worktree, gitignored
files included.
