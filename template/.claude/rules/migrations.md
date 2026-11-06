---
paths:
  - "database/**"
  - "tests/migrations/**"
---

# Migration conventions

Loads when you touch Alembic revisions, migration-owned helpers under `database/`, or their
tests.

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
