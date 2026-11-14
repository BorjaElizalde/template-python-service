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

**Tasks:** every task, and every subagent session, is an issue in BorjaElizalde/template-python-service. `/task:start` finds or creates the issue, creates its worktree at ../../worktrees/<n>-<slug>/<repo> (a cross-repository task's worktrees share the issue folder), and opens its session in a new Terminal window, resuming one that exists. A task's branch type is its mode, for life: execution, the default, whose session works alone, or `design`, whose session works the task out with the owner in its Terminal tab and builds nothing; start a design task only when the owner asks to work it out together. `/task:finish <n>` closes the issue once its result is delivered, then the session, the worktree and the issue's local branches. When the user names a task loosely, find its number with `gh issue list -R BorjaElizalde/template-python-service --search`. An issue that is blocked (a "blocked by" link to an open issue) or parked (the `backlog` label, with a comment `Parked: <reason>`) must not start, and `/task:start` refuses it. Only the owner's word parks or releases an issue, and a planning or design task parks every issue it creates; the start skill says how to park, release, link and plan.

**Following tasks:** the main session follows its tasks through two commands of `.claude/skills/task/scripts/task.sh`: `cleanup` finishes every task whose issue is closed, and `status` only reads, one line per task, then every other open issue as ready, blocked or parked. Both run by themselves, cleanup first: in each `/task:start`, and in a SessionStart hook that puts the cleanup's lines and the task lines in the context of a session that starts or resumes in the main checkout. Report the status to the owner through `/task:status`, which says how to read the lines, act on them and write the reply: each time the owner asks for it, and in your first reply after a session start. A main session that runs a `/loop` runs `bash .claude/skills/task/scripts/task.sh status` on each round, and `/task:status` when a line ends in `needs attention`.

**Worktrees:** all feature work happens in the task's worktree, never in the main checkout. Never call EnterWorktree.

**Memory:** .claude/memory/ is yours, .claude/agent-memory/<agent>/ the reviewers'; both commit on the branch and are reviewed in its PR. Any memory should earn its keep, write only when it is load-bearing and unrecoverable from the repo. No history, no framing against an earlier state, nothing the code or .claude/rules/ already says.

**Files:** YAML files end in `.yaml`; `.yml` only where a tool requires that exact name.

## Optional agentic workflow

Invoke `/agentic-flow` only when the user explicitly requests the agentic flow for the current
task.
