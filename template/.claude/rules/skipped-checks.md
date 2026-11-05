---
paths:
  - "**/*.py"
  - "pyproject.toml"
---

# Skipped checks
These load when you read or edit Python or `pyproject.toml`.

- A skipped check (a *suppression*) is a comment or marker that tells a tool not to check a line
  or run a test: `# noqa`, `# type: ignore`, `# pyright: ignore`, `# nosec`, `# pragma: no cover`,
  `# fmt: skip/off`, a pytest skip. It is the last resort. Write one only after trying the
  alternatives (narrow the construct, restructure, use the idiom the rule points to, such as
  `contextlib.suppress` for an expected exception) and finding that each leaves the code harder
  to maintain
- Name the rule code and give the reason on the same line, in plain English. The reason answers
  what a reader of that line would ask, never why the tool flags it: for a catch-all, why
  catching everything is right here (`# noqa: BLE001 if one provider fails, carry on with the
  other providers`); for a type ignore, which library type is wrong. `# fmt: off` works only
  standing alone, so its reason goes on the comment line above
- BLE001 counts only stdlib-named log calls as logging, so it also flags a boundary handler that
  logs via `await log.aerror(...)`; the sync call it accepts is forbidden in async code
  (`python-conventions.md`, Logging). The suppression stays, and its reason still says why
  catching everything is right there
- The practices hook (`.claude/hooks/practices/`) stops an edit that adds a suppression without a
  reason, and asks the owner to approve one that has a reason; in an unattended run that ask
  counts as a refusal, so leave the suppression to the owner or find the better fix
