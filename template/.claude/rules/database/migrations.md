---
paths:
  - "**/*.py"
---

# Migration conventions

- A revision must emit the same SQL forever: hardcode value lists, name maps, and timestamps
  as literals; never import the live enum, config, or seed YAML.
- Migration-owned helper modules under `database/` (e.g. `order_backfill.py`) are append-only:
  already-merged revisions depend on them behaving as they did at merge time, so a behavioral
  change means a NEW function, never an edit to an existing one.
- Data remaps of user-mutable columns must key on the value being RETIRED (state you can
  prove), never on seed-assumed current values — runtime curation drifts rows away from the
  seed and silently no-ops the remap.
- Seeded migration tests must seed DRIFTED rows (user-curated values), not only the
  seed-shaped state: the plain chain replay seeds no rows, and a fresh-seed test satisfies the
  migration's assumptions by construction.
- PostgreSQL refuses `ALTER COLUMN ... TYPE` on a column any view selects from — a revision
  changing such a column's type must inline `DROP VIEW IF EXISTS <view>` first.
- A revision in `database/versions/` has a module docstring, the one exception to the rule on
  module docstrings (`.claude/rules/python-conventions.md`, Docstrings): `alembic history` shows it
  as the revision message.
- The duplication check skips `database/` (`.jscpd.json`): a revision keeps its own copy of the
  code it runs.
