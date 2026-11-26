---
paths:
  - "tests/**/*.py"
---

# Testing the API

Loads when you read or edit tests, with `.claude/rules/testing.md`.

- For nearly every test the boundary is an endpoint, called through the `client` fixture; a few
  call an MCP tool with `call_tool`
- A read checks the response against the case's data. After a write, a GET is not the check: it
  shows only what the API exposes
- The check of the OpenAPI document lives in `tests/contracts/`

Two harness behaviours produce a green test for the wrong reason:
- **Cookie jar.** A cookie set via `client.cookies.set` lands under a different domain entry from
  the server's `Set-Cookie`, so within one test both may be sent and the stale one can win. Delete
  the cookie before a raw set and at the start of login helpers.
- **Identity.** Tokens identify the authentication subject (a user), so a login helper takes that
  id; never treat the id of what the subject belongs to (a tenant) as the authentication subject.
  Autoincrement can give a lone user the same numeric id as its tenant, so scoping and
  authorization tests must add a user to an existing tenant to make the ids differ — otherwise
  passing the wrong id type still passes.
