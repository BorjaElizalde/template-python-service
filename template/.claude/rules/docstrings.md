---
paths:
  - "**/*.py"
---

# Docstrings
These load when you read or edit Python, and add Python's docstrings to the comment rules in
`conventions.md`.

- Outside-facing docstrings, for a reader outside the code: FastAPI endpoints and the models in the
  OpenAPI schema (they become the SDK's hover text), MCP tools and the MCP response models (the
  LLM reads them), and the `batch/main.py` CLI command (`--help`). Write them for that reader, in
  one to three sentences: what it does for them, what to send, what comes back, and which errors
  come back by their ``ERR_...`` code. No internals (tables, sessions, transactions, internal
  steps, other modules, history). An endpoint with `include_in_schema=False` has no outside reader
- Functions, methods, classes and tests may have a docstring, at a very high bar: one or two
  sentences on why it exists or how a caller must use it (a contract to respect, a required order
  of calls, a side effect to expect), and only when a reader can't tell that from the code and the
  name. Nothing the code or the name already says, and no history. A contract callers must respect
  goes in the function's or class's docstring
- No docstring lists parameters, return values or exceptions (`Args:`, `Returns:`, `Raises:`,
  `:param`): the signature and its types already say that. The exception is an `Args:` section on
  an MCP tool: fastmcp writes it into the tool's schema as the parameter descriptions the LLM
  reads. It goes last, because fastmcp keeps only the text before it as the tool's description
  and drops the `Returns:` and `Raises:` sections
- No module docstrings, except an Alembic migration's in `database/versions/` (`alembic history`
  shows it as the revision message)
- A docstring that fails its bar keeps only what passes it, as a docstring or a one-line comment
  where it applies. A body left empty gets `pass`, or `...` in a Protocol or abstract stub
