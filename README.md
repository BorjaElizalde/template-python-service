# template-python-service

A [Copier](https://copier.readthedocs.io/) template for the Python half of an agentic coding setup,
layered on `template-agentic`. It fills the agentic layer's plug-in points for a Python service:
the practice checks and their registry, the ruff formatter hook, the Python rules and reviewer
agents, the review wave, and `make gate`.

## Apply and update

`template-agentic` goes first: this template reads its answers file and refuses to render without
it.

```bash
uvx copier copy <agentic-template-url> .   # writes .copier-answers.agentic.yaml
uvx copier copy <this-template-url> .      # writes .copier-answers.python-service.yaml
uvx copier update -a .copier-answers.python-service.yaml
```

Every merge to `main` is a release: `Build` re-runs `make gate` on the merged result, then tags the
next `YYYYMMDD.N` version. Projects take both layers' releases as one Renovate update PR. The
template uses no unsafe Copier feature, so an update runs without `--trust`.

## Questions

| Question | Used for |
|---|---|
| `package_name` | The application's package directory: where the practice checks look, which paths the rules load for, what `make gate` lints and type-checks |

The practice checks read it from `.claude/hooks/practices/stack.json`, the only rendered file they
load, so they stay plain jq that the template's tests run directly.

## What the template fills in

| Plug-in point of `template-agentic` | Here |
|---|---|
| `.claude/hooks/practices/registry.jq` | `kind($path)` sorts Python, tool-config and data files; `practices($ctx; $kind)` runs the checks beside it: skipped checks, excepts, docstrings, comments, logs, tests, config |
| `.claude/hooks/stack/format.sh` | `ruff format` on every edited Python file |
| `.claude/review-wave.md` | The plan reviewer, the review wave, the last pass and the lint resolver |
| `make gate` | `python.mk`: ruff, basedpyright, bandit and pytest over the package and `tests/` |

The project owns its `Makefile`, seeded once with `include python.mk`.

Tests that call no boundary, because they check a contract or shipped data, live in
`tests/contracts/`, `tests/migrations/` or `tests/config_integrity/`.

## Develop

This repository works on the same three branches as every project. Feature PRs squash into
`develop`; `/release` merges `develop` into `staging` and `staging` into `main`, where `Build`
tags the next version; a `bugfix/` branch of one commit merges into `staging`. `develop` is the
default branch, and rulesets hold each branch to PRs with a passing `gate`, `staging` and `main`
to merge commits and `develop` to squashes. Its own `.claude/skills/` carries `/commit`, `/gate`,
`/pull-request` and `/release` as rendered copies of `template-agentic`'s skills, with its own
issues as the issues repository, and `.claude/release.md` holds its release facts. Commits use
the GitHub noreply address set in the clone's git config.

`make gate` renders `template-agentic` (`AGENTIC_SRC`, a git URL or a local clone, by default the
`template-agentic` beside this repository's remote; its newest tag), renders this template on top,
and runs the rendered suites: the agentic practices protocol and the Python practices. It also
checks that the repository's own shared skills match a fresh render of `template-agentic`, so a
release there that changes them fails here until the copies are rendered again. The `Gate`
workflow runs the same target on every PR into `develop`, `staging` or `main`, after it checks
where the PR comes from: `main` takes `staging`, and `staging` takes `develop` or a `bugfix/*` PR
of one commit, from this repository's own branches. `Build` runs the gate again on `main` before
it tags.
