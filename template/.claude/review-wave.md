# Review wave

`/agentic-flow` reads this file as its roster.

- **Plan reviewer:** `plan-reviewer`. Read-only.
- **Review wave:** `code-reviewer`, `security-reviewer` and `test-reviewer`, in parallel. The
  first two are read-only; `test-reviewer` edits only changed files under `tests/`. When fixes
  change tests, rerun `test-reviewer`.
- **Last pass:** `docstring-reviewer`. It edits only comment and docstring text on lines the
  branch added or changed.
- **Resolver for lint, format and type failures:** `lint-problem-resolver`. It edits project code
  only where the reported failures need it.
