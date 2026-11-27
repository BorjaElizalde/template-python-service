---
paths:
  - "tests/**/*.py"
---

# Testing conventions

- Every test has three steps: build the case's data (an edge case lives in the data), call the
  boundary a consumer uses, then check the result. That is how internal code gets covered: to
  reach a branch, give the data that makes the boundary reach it; never call the internal
  function. If no data can make a boundary reach a branch, the branch is dead code: remove it
  rather than test it
- The contract and shipped-data checks need no boundary. They live in their own folders:
  `tests/contracts/` (public contracts) and `tests/config_integrity/` (the config files)
- External APIs mocked (third-party providers, OAuth), internal services real
- Never test an internal function: the boundary that uses it covers its behaviour. A test that
  calls a helper pins how the code works, so a refactor breaks it even when nothing a consumer
  sees changes
- A test earns its keep only when it checks something a consumer sees (a response, stored data, a
  sent email, a log line operators act on) and no other test already covers it. Coverage comes
  from behaviour at the boundaries, never from one test per function
- Tests must be synchronous (no async operations)
- A test that needs a fixture only for what it sets up (a patch, rows it never reads) names it in
  `@pytest.mark.usefixtures(...)`, not as a parameter: ruff's ARG fails a parameter nothing reads,
  and a leading underscore makes pytest look for a fixture of that name. pytest rejects marks on
  fixtures, so a fixture that needs another to run first keeps it as a parameter, with
  `# noqa: ARG001` and its reason
