---
paths:
  - "**/*.py"
---

# Python conventions
These load when you read or edit any Python file, and expand on the simplicity principle in the
Design Philosophy (`.claude/rules/agentic.md`). `service-conventions.md` adds the rules for a
service's own parts.

## Error Handling
- Let exceptions propagate naturally - catch at boundaries only: the entry points where a call
  comes in from outside the code (a request handler, a CLI command, a job's entry function)
- A try earns its keep only when the failure can really happen (bad user input, a provider or
  network error, a race) and the handler does better than letting it reach the boundary (a clearer
  API error, one item failing without stopping the rest, a fallback that is the intended
  behaviour). Never guard what our own code guarantees: input a model has validated, a value the
  database forbids, data another of our services always produces. The same goes for an `if` that
  checks for such a case, like a zero or an empty dataframe our own code never passes
- Every except outside `tests/` says why it earns its keep in a one-line comment, on the except
  line or directly above or below it: the failure that can really happen there and why handling
  it beats the boundary. If no such sentence holds, remove the except

## Logging
- Boundary-only logging: log at the boundaries and in exception handlers. Not inside business
  logic, utilities, or hot paths
- Success is silent — don't log successful bulk operations or happy-path completions
- A log line fires per event an operator would act on (a request's outcome, a batch run, a
  failure), never per data item, and never for an outcome already saved in the database or
  returned to the caller

## Docstrings
- Outside-facing docstrings, for a reader outside the code: FastAPI endpoints and the models in the
  OpenAPI schema (they become the SDK's hover text), MCP tools and the MCP response models (the
  LLM reads them), and the `batch/main.py` CLI command (`--help`). Write them for that reader, in
  one to three sentences: what it does for them, what to send, what comes back, and which errors
  come back by their ``ERR_...`` code. No internals (tables, sessions, transactions, internal
  steps, other modules, history). An endpoint with `include_in_schema=False` has no outside reader
- Functions, methods, classes and tests may have a docstring, at a very high bar: one or two
  sentences on why it exists or how a caller must use it (a contract to respect, a required order
  of calls, a side effect to expect), and only when a reader can't tell that from the code and the
  name. Nothing the code or the name already says. A contract callers must respect goes in the
  function's or class's docstring
- No docstring lists parameters, return values or exceptions (`Args:`, `Returns:`, `Raises:`,
  `:param`): the signature and its types already say that. The exception is an `Args:` section on
  an MCP tool: fastmcp writes it into the tool's schema as the parameter descriptions the LLM
  reads. It goes last, because fastmcp keeps only the text before it as the tool's description
  and drops the `Returns:` and `Raises:` sections
- No module docstrings, except an Alembic migration's in `database/versions/` (`alembic history`
  shows it as the revision message)
- A docstring that fails its bar keeps only what passes it, as a docstring or a one-line comment
  where it applies. A body left empty gets `pass`, or `...` in a Protocol or abstract stub

## Duplicated Code
- The gate fails on a block of 10 lines or more written twice outside `tests/` and `database/`,
  imports aside (jscpd, set in `.jscpd.json`). Fix each copy in this order: first delete the copy
  that should not exist; else call the code's existing owner; extract a shared function only last.
  Never extract a helper only to pass the check: that is the premature abstraction the Design
  Philosophy forbids
- Keep both copies only when they look alike but change for different reasons. Then the copy goes
  between `# jscpd:ignore-start` and `# jscpd:ignore-end`, with its reason in the form
  `conventions.md` gives

## Module Imports
- Importing a module must not execute work: modules define and export, nothing runs
