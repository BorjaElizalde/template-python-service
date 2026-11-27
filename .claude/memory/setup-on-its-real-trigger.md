---
name: setup-on-its-real-trigger
description: Setup a clone needs, such as its commit hooks, runs by itself on the event that creates the need, never as a new target to remember or as a step of the gate
metadata:
  type: feedback
---

Setup that a clone needs, such as installing its commit hooks, runs by itself on the event that creates the need: a clone's first `make claude`, or a new worktree. It is never a new target that someone must remember to run, and never a step of the gate.

**Why:** The owner chose this on 2026-11-27, for the commit hooks of issue #148, as a matter of governance:
- Automation is a must: "no one will remember when to run a new target". Each new target adds cognitive load, because people must remember when to use it.
- Coupling the install to the gate is wrong: "no one reinstalls stuff everytime they need to run the gate". An install belongs to its real triggers.
- Off the gate, the install never runs in CI, which does not need it, and that lowers the risk.

The issue itself had asked for a gate check that fails in a clone with no hooks, so an issue can ask for this shape too.

**How to apply:** For each setup step, find the event that creates the need, and attach the step to what already runs at that event. Example, real: the hook file is a prerequisite of `make claude`, so make installs the hooks only while they are missing. Add no target and no check whose fix is a command, and put no setup in the gate or in anything CI runs. Related: [[readme-consumer-only]].
