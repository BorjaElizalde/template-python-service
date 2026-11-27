---
paths:
  - "**/*.py"
  - "pyproject.toml"
  - ".gitleaksignore"
  - ".gitleaks.toml"
  - "**/.bandit"
  - "**/pytest.ini"
  - "**/.pytest.ini"
  - "**/pytest.toml"
  - "**/.pytest.toml"
  - "**/ruff.toml"
  - "**/.ruff.toml"
---

# Skipped checks

- Python's skipped checks are `# noqa`, `# type: ignore`, `# pyright: ignore`, `# nosec`,
  `# pragma: no cover`, `# fmt: skip/off`, a pytest skip, a warning filter other than `error`
  set in Python (a `pytest.mark.filterwarnings` mark, or a conftest's
  `config.addinivalue_line("filterwarnings", ...)`), and `# jscpd:ignore-start` through
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
- bandit can read its settings from `.bandit`, pytest from `pytest.ini`, `.pytest.ini`,
  `pytest.toml` and `.pytest.toml`, and ruff from `ruff.toml` and `.ruff.toml`. pytest and ruff
  then ignore their settings in `pyproject.toml`. So any edit to one of these files can switch a
  check off, and it gives a reason, whatever it changes. The reason goes on `#` comment lines of
  their own: bandit and pytest read a `#` after an INI entry as part of its value
