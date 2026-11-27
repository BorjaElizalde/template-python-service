---
name: setup-rides-on-existing-steps
description: Automatic setup, such as installing commit hooks, goes on a step every clone already runs, never on a new target or a check that fails and asks someone to run a command
metadata:
  type: feedback
---

Setup that a clone needs once, such as installing the commit hooks, runs on a step every clone already takes, such as `make claude`. It never becomes a new make target, or a check that fails and prints a command for someone to run.

**Why:** The owner, on 2026-11-27, about a `commit-hooks` target that made `make gate` fail in a clone with no hooks: "I dont want another manual command that you or anyone could forget to use", and a new target is "yet another make target that we need to maintain and govern". The issue itself had asked for that failing check, so an issue's acceptance list can ask for this shape too.

**How to apply:** Before you add a target, or a check whose fix is a command, look for a step that already runs at that moment, and attach the work to it as a prerequisite. Keep it out of any target that CI runs: there, the setup runs for nothing, and a check fails every run. Related: [[readme-consumer-only]].
