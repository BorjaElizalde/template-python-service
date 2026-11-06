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

Every merge to `main` is a release: `Build` re-runs the gate suite on the merged result, then tags
the next `YYYYMMDD.N` version. Projects take both layers' releases as one Renovate update PR. The
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
to merge commits and `develop` to squashes. Commits use the GitHub noreply address set in the
clone's git config.

The repository applies `template-agentic` to itself, as a project does, with its own issues as the
issues repository: `.claude/` holds the whole harness, and `.copier-answers.agentic.yaml` records
the version. Renovate's Copier manager brings each new `template-agentic` release as an update PR.
`.claude/release.md` holds this repository's release facts. Once per clone, run
`bash .claude/skills/task/scripts/task.sh point-memory`.

`make gate` runs `tests/render-and-test.sh`: it renders the `template-agentic` version the answers
file records, renders this template on top, and runs the rendered suites: the agentic practices
protocol and the Python practices. `AGENTIC_SRC` and `AGENTIC_REF` override that source and
version, to test an unreleased agentic change from a local clone and its branch. It also checks
that a fresh render of the repository's own answers reproduces every file `template-agentic` owns
here. The `Gate` workflow runs the same script on every PR into `develop`, `staging` or `main`,
after it checks where the PR comes from: `main` takes `staging`, and `staging` takes `develop` or
a `bugfix/*` PR of one commit, from this repository's own branches. `Build` runs it again on
`main` before it tags. CI runs the script itself, never `make gate`, so a change that relaxes the
local gate can't relax CI.
