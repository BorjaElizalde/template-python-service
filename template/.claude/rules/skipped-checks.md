---
paths:
  - "**/*.py"
  - "pyproject.toml"
---

# Skipped checks
These load when you read or edit Python or `pyproject.toml`.

- A skipped check (a *suppression*) is a comment or marker that tells a tool not to check a line
  or run a test: `# noqa`, `# type: ignore`, `# pyright: ignore`, `# nosec`, `# pragma: no cover`,
  `# fmt: skip/off`, a pytest skip. A loosened config does the same for more than a line: an
  ignore, exclude or per-file-ignores entry, a lower type-check report level, a pytest option that
  skips tests, a pre-commit or Makefile change that stops a tool from running or from failing
- Both are the last resort. First check whether skipping is really the only way. Read the current
  documentation: the rule's page in the tool's docs (ruff, basedpyright, bandit, pytest) and the
  docs of any library involved, since a newer version often adds a setting, an idiom or a typed
  API that makes the skip unnecessary. Then look for a cleaner approach: fix the code so the check
  passes, narrow the construct, restructure, or use the idiom the rule's docs give as its fix
  (such as `contextlib.suppress` for an expected exception). If one works, use it
- Keep the skip only if no approach leaves the project easier to maintain. Its reason then has
  three parts: the rule code (in the directive, or at the start of a config entry's comment, as in
  `# E402:`); why this is right here and the most maintainable option, answering what a reader of
  the line would ask, never why the tool flags it; and one `Tried <alternative>, but <why it was
  discarded>.` sentence per alternative, the rule's documented fix among them
- The reason goes after the directive, on the same line. When that line would pass 100 columns, it
  goes on the comment lines directly above, and the line keeps only the directive. `# fmt: off`
  and `# pyright:` file directives must stand alone, so their reason always goes above. A config
  entry's reason goes on its line or the comment lines above it; for a removed entry, in a comment
  where it was. For example:
  ```python
  # If one provider fails, carry on with the other providers.
  # Tried naming the errors, but the HTTP client, the parser and the database each raise their own.
  # Tried logging.exception, which BLE001 accepts, but async code logs with await log.aerror.
  except Exception as e:  # noqa: BLE001
  ```
- The practices hook (`.claude/hooks/practices/`) stops an edit that adds a skipped check or
  loosens a config without the rule code or without a reason in this form, and its message
  repeats these steps. The hook checks only the form; review judges whether the reason holds
