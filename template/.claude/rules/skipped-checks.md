---
paths:
  - "**/*.py"
  - "pyproject.toml"
---

# Skipped checks
These load when you read or edit Python or `pyproject.toml`, and add Python's part to the
skipped-check rules in `conventions.md`.

- Python's skipped checks are `# noqa`, `# type: ignore`, `# pyright: ignore`, `# nosec`,
  `# pragma: no cover`, `# fmt: skip/off`, a pytest skip, and `# jscpd:ignore-start` through
  `# jscpd:ignore-end` around a copy. The docs to read first are those of ruff, basedpyright,
  bandit, pytest and jscpd. A rule's documented fix is often a Python idiom, such as
  `contextlib.suppress` for an expected exception
- The line length is 100 columns. `# fmt: off` and `# pyright:` file directives must stand alone.
  For example, a reason too long for its line:
  ```python
  # If one provider fails, carry on with the other providers.
  # Tried naming the errors, but the HTTP client, the parser and the database each raise their own.
  # Tried logging.exception, which BLE001 accepts, but async code logs with await log.aerror.
  except Exception as e:  # noqa: BLE001
  ```
- The practices hook (`.claude/hooks/practices/`) stops an edit that adds a skipped check or
  loosens a config without the rule code or without a reason in the form `conventions.md` gives,
  and its message repeats that rule's steps. The hook checks only the form; review judges whether
  the reason holds
