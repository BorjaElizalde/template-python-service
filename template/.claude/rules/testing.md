---
paths:
  - "tests/**/*.py"
---

# Testing conventions

Loads when you read or edit tests. (`python-conventions.md`, `comments-and-docstrings.md` and
`skipped-checks.md` also apply here.)

- Every test has three steps: build the case's data with the `mock_*` helpers (an edge case lives
  in the data), call the boundary a consumer uses, then check the result. For nearly every test
  the boundary is an endpoint through the `client` fixture; the few others are an MCP tool with
  `call_tool`, a batch task's entry function or the batch CLI. That is how internal code gets
  covered: to reach a branch, give the data that makes the boundary reach it; never call the
  internal function. If no data can make a boundary reach a branch, the branch is dead code:
  remove it rather than test it
- The check in step 3 depends on the call. A write reads the database through `db_session` after
  the call and checks the specific changed result. A refused write checks that nothing changed in
  the database. A read checks the response against the mock data. A GET after a write is not the
  check: it shows only what the API exposes. Call `db_session.expire_all()` before the read: the
  session keeps the objects the `mock_*` helpers built and hands them back with their old values,
  so a "nothing changed" check passes whatever the endpoint did
- The contract and shipped-data checks need no boundary. They live in their own folders:
  `tests/contracts/` (public contracts, such as the OpenAPI document), `tests/migrations/` and
  `tests/config_integrity/` (the config files)
- Functional tests with real PostgreSQL (testcontainer) - no DB mocking
- External APIs mocked (third-party providers, OAuth), internal services real
- Never test an internal function: the boundary that uses it covers its behaviour. A test that
  calls a helper pins how the code works, so a refactor breaks it even when nothing a consumer
  sees changes
- A test earns its keep only when it checks something a consumer sees (a response, stored data, a
  sent email, a log line operators act on) and no other test already covers it. Coverage comes
  from behaviour at the boundaries, never from one test per function
- The practices hook (`.claude/hooks/practices/`) stops a new test that goes through no boundary,
  outside the contract and shipped-data folders (`tests/contracts/`, `tests/migrations/`,
  `tests/config_integrity/`). It also stops a new test that calls a write endpoint
  (`client.post`, `put`, `patch` or `delete`) and does not use `db_session` after it. It reminds on
  the others
- Tests must be synchronous (no async operations)
- **Test data pattern**: Use `mock_*` high-level functions from `tests/helpers/data_factory/`. The `_create_*` row builders beside them are private to their module (the type check rejects one used outside it); a new one gets the leading underscore too. Create test data in fixtures at the top of the file and reuse the fixtures across test functions. Each test runs on its own copy of a database that holds only the schema and seed data, so keep data fixtures function-scoped: rows built by a wider-scoped fixture are gone after its first test.
- A test that needs a fixture only for what it sets up (a patch, rows it never reads) names it in
  `@pytest.mark.usefixtures(...)`, not as a parameter: ruff's ARG fails a parameter nothing reads,
  and a leading underscore makes pytest look for a fixture of that name. pytest rejects marks on
  fixtures, so a fixture that needs another to run first keeps it as a parameter, with
  `# noqa: ARG001` and the reason `skipped-checks.md` asks for

Three harness behaviours produce a green test for the wrong reason:
- **Event loop.** The async sessionmaker resets between tests, not between phases of one test. Do
  not mix TestClient DB work with `asyncio.run` DB work, or make two `asyncio.run` DB calls in one
  test — the pooled asyncpg connection stays bound to the first loop. Split them into separate tests.
- **Cookie jar.** A cookie set via `client.cookies.set` lands under a different domain entry from
  the server's `Set-Cookie`, so within one test both may be sent and the stale one can win. Delete
  the cookie before a raw set and at the start of login helpers.
- **Identity.** Tokens identify the authentication subject (a user), so a login helper takes that
  id; never treat the id of what the subject belongs to (a tenant) as the authentication subject.
  Autoincrement can give a lone user the same numeric id as its tenant, so scoping and
  authorization tests must add a user to an existing tenant to make the ids differ — otherwise
  passing the wrong id type still passes.
