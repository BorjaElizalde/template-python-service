## Judgment Guidelines

Any judgment call you need to take, or you want to delegate, is decided against the Product Stage
in CLAUDE.md and the two subsections below. These override your default instincts.

### Agentic Coding Economics
This codebase is built by coding agents. You are trained on human-effort economics, so you will
overprice wide-but-mechanical work — renames, call-site sweeps across many files, schema/data
migrations, regenerating tests. Behind a green `make gate` those are cheap: when choosing between
the clean design that needs a broad mechanical migration and a compromised one that avoids it,
pick the clean design. Never keep a bad shape just to keep the diff small.
What kept its old price: review attention (several small verifiable diffs beat one big-bang
rewrite) and anything `git revert` cannot undo, production data, user-curated records, deployed
contracts. This re-weights design tradeoffs; it is not license to restructure outside the task.

### Design Philosophy
Core principle: **simplicity** meaning no unnecessary complexity, never cheap-and-quick code.
We dread stupid complexity: complexity an outsider needs help to understand. We praise elegant
complexity: hard problems solved with few, well-chosen concepts. Fewer moving parts, no defensive
coding for impossible scenarios, let exceptions propagate and catch only at boundaries, no
premature abstractions. Always ask: "Can this be done more elegantly?"

## Git
Use standard git commands (`git status`, `git diff`, `git log`) without the `-C` flag when working in this directory. The `-C` flag is unnecessary and triggers extra permission prompts.

**Tasks:** every task, and every subagent session, is an issue in BorjaElizalde/template-python-service. `/task:start` finds or creates the issue, creates its worktree at ../../worktrees/<n>-<slug>/<repo> (a cross-repository task's worktrees share the issue folder), and opens its session in a new Terminal window, resuming one that exists. `/task:finish <n>` closes the issue once its result is delivered, then the session, the worktree and the issue's local branches. When the user names a task loosely, find its number with `gh issue list -R BorjaElizalde/template-python-service --search`.

**Following tasks:** the main session follows its tasks through the ones that need attention: a task whose session waits for an answer, or has been idle or gone for 10 minutes since it last wrote. A busy session is working, and one that went quiet only just now often waits for a background check that will wake it. `/task:start` lists them after its sweep, and a SessionStart hook puts them in the context of a session that starts or resumes in the main checkout; a main session that runs a `/loop` lists them on each round with `bash .claude/skills/task/scripts/task.sh attention`, which prints nothing when no task needs attention. Act on each as the last step of the start skill says (`.claude/skills/task/skills/start/SKILL.md`). `task.sh status` shows every task, after finishing those whose issue is closed.

**Worktrees:** all feature work happens in the task's worktree, never in the main checkout. Never call EnterWorktree.

**Memory:** .claude/memory/ is yours, .claude/agent-memory/<agent>/ the reviewers'; both commit on the branch and are reviewed in its PR. Any memory should earn its keep, write only when it is load-bearing and unrecoverable from the repo. No history, no framing against an earlier state, nothing the code or .claude/rules/ already says.

**Files:** YAML files end in `.yaml`; `.yml` only where a tool requires that exact name.

## Optional agentic workflow

Invoke `/agentic-flow` only when the user explicitly requests the agentic flow for the current
task.
