---
paths:
  - "**/*.py"
  - "pyproject.toml"
  - ".gitleaksignore"
  - ".gitleaks.toml"
---

# Skipped checks
These load when you read or edit Python, `pyproject.toml` or gitleaks's files, and add this
stack's part to the skipped-check rules in `conventions.md`.

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
- The secret scan, gitleaks, skips a finding whose line holds `gitleaks:allow`, in a file of any
  type, and one whose fingerprint `.gitleaksignore` lists. In `.gitleaks.toml`, an entry under
  `commits`, `paths`, `regexes` or `stopwords` skips the findings it matches, one under
  `disabledRules` skips a rule, and a file without `useDefault = true` under `[extend]` drops
  gitleaks's own rules. The docs to read first are gitleaks's. Skip only a value that is not a
  secret: revoke a real secret and take it out of the code
- gitleaks reads `gitleaks:allow` only on the finding's own line, so its reason goes after it
  there, or on the comment lines above when that line would pass 100 columns. gitleaks reads a
  whole `.gitleaksignore` line as the fingerprint, so a fingerprint's reason goes on the comment
  lines above it
- The practices hook (`.claude/hooks/practices/`) stops an edit that adds a skipped check or
  loosens a config without the rule code or without a reason in the form `conventions.md` gives,
  and its message repeats that rule's steps. The hook checks only the form; review judges whether
  the reason holds
