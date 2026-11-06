---
name: agentic-flow
description: Use only when the user explicitly requests the agentic flow for the current task.
---

The stack layer names its reviewers in `.claude/review-wave.md`: the plan reviewer, the review
wave, the last pass, and the resolver for lint, format and type failures. Without that file, run
the steps that need no reviewer.

## Workflow

1. Work in a task worktree. Create or receive a scratchpad outside the checkout for plans and
   artifacts; give every agent that needs it the exact absolute path.
2. For non-trivial work, write the plan there. Re-derive externally sourced approaches instead of
   inheriting their decisions. End with **Assumptions** and **Tradeoffs**.
3. If there is a plan, spawn the plan reviewer with its exact path. Resolve Must-Change findings
   before implementation.
4. Implement, invoke `/gate`, invoke `/simplify develop...HEAD`, then invoke `/gate` again.
5. Commit with `/commit`; push and open the `develop` PR with `/pull-request` before review.
6. Spawn the review wave with the explicit branch range, as `.claude/review-wave.md` describes.
   Add `memory-cleaner` when memory changed. Wait for every report.
7. Apply findings under the Judgment Guidelines and explain the decisions. Escalate rejected
   findings and changes required outside this repository. Fixes re-enter at step 4; rerun a
   reviewer whose surface the fixes changed.
8. Run the last pass alone. Then invoke `/gate`, push, and confirm PR CI is green.

## Rules

- Invoke built-in skills from the main loop, never through a subagent.
- On lint, format, or type failures, spawn the resolver. Fix test and behavior failures directly.
  Never suppress a failure; decide explicitly when it exposes a design problem.
- Minimize user input. Weigh options and choose the recommendation that compounds without patchiness
  or overengineering; apply the Judgment Guidelines to every deferred judgment.
- Take reversible, in-scope decisions and actions yourself. Resolve merge conflicts from both
  branches' intent, never by choosing the smaller diff. Escalate only product scope, public
  contracts, irreversible data or external state, and changes required in another repository.
- Fix pre-existing blockers and small issues on the surface changed; report unrelated issues
  without expanding scope.
- This invocation authorizes the workflow's subagents, commits, push, and PR for this task.
- Finish only when `/gate` and PR CI pass on a PR into `develop`.
