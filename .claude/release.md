# Release facts

The release skill reads this file before it promotes. Keep it to what CI and the deploy do.

## Checks on each promotion PR

- `develop` → `staging`: `gate`, which checks the PR comes from `develop`, then runs `make gate`
  on the merge result: this template rendered on top of `template-agentic`'s newest tag, the
  rendered suites, and the copy check.
- `staging` → `main`: `gate`, the same, with the PR from `staging`.

## A promotion PR with no check

None: `Gate` runs on every PR into `staging` or `main`, and the rulesets require it, so a missing
check is a red.

## Deploy

`Build`, on the merge into `main`: it runs the gate suite again, then pushes the next `YYYYMMDD.N`
tag. It takes a few minutes.
