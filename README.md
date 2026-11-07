# template-python-service

A [Copier](https://copier.readthedocs.io/) template for the Python half of an agentic coding setup,
layered on `template-agentic`. It fills the agentic layer's plug-in points for a Python service:
the practice checks and their registry, the ruff formatter hook, the Python rules and reviewer
agents, the review wave, and `make gate`. It also owns the tool settings every Python service
shares, so a project extends them instead of copying them.

## Apply and update

`template-agentic` goes first: this template fills its plug-in points. The template can't check
that the agentic layer is there, because Copier renders every update's old and new versions into
empty folders, where no other layer's files exist.

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
| `package_name` | The application's package directory: the project name in `pyproject.toml`, and the app paths that the docstring check and the rules name (the API and MCP surface, `config.py`) |

The practice checks read it from `.claude/hooks/practices/stack.json`, the only rendered file they
load, so they stay plain jq that the template's tests run directly.

## What the template fills in

| Plug-in point of `template-agentic` | Here |
|---|---|
| `.claude/hooks/practices/registry.jq` | `kind($path)` sorts Python, tool-config and data files; `practices($ctx; $kind)` runs the checks beside it: skipped checks, excepts, docstrings, comments, logs, tests, config |
| `.claude/hooks/stack/format.sh` | `ruff format` on every edited Python file |
| `.claude/review-wave.md` | The plan reviewer, the review wave, the last pass and the lint resolver |
| `make gate` | `python.mk`: ruff, basedpyright and bandit over every Python file in the repository but notebooks, and pytest over `tests/` |
| `.github/actions/stack-gate/action.yaml` | `gate.sh`: the same tools called directly, never `make gate`, with CI's own copy of the shared settings beside it |

## Shared tool settings

| File | Owner | Holds |
|---|---|---|
| `ruff.base.toml` | template | Line length, the preview setup, the rule selection, the reasoned ignores, the typed-exception check |
| `basedpyright.base.json` | template | The checking mode, the platform, and the strict `report*` settings |
| `python.mk` | template | The `lint`, `lint-check`, `typecheck`, `security`, `test` and `gate` targets |
| `.pre-commit-config.yaml` | template | The commit hooks: ruff, bandit (through `make security`) and the file checks, each running the project's own pinned tool through `uv run`, so the file holds no version |
| `.github/actions/stack-gate/` | template | The checks a project's CI runs, and CI's own copy of `ruff.base.toml` and `basedpyright.base.json` |
| `pyproject.toml` | project, seeded once | The project, its dependencies, and its own tool settings: it extends the two base files |
| `Makefile` | project, seeded once | The project's own targets, after `include python.mk` |
| `.gitignore` | project, seeded once | `.env` files, which hold secrets (`.env.example` stays tracked), and what the gate and the tools leave behind |

Every update rewrites the template's files; a project changes a shared setting in the template,
not in its copy. A project adds to the shared settings in its `pyproject.toml`:

- ruff (`[tool.ruff] extend = "ruff.base.toml"`): `extend-select` for more rules, `ignore` and
  `extend-per-file-ignores` for its own exceptions, each with the reason `skipped-checks.md`
  asks for. Never `select`: ruff takes a `select` as the whole rule list and drops the base's.
- basedpyright (`[tool.basedpyright] extends = "basedpyright.base.json"`): any setting it
  overrides, which applies to the local gate only: CI's basedpyright never reads `pyproject.toml`.
- pytest and coverage have no way to extend a shared file, so their settings stay the project's.

CI runs `.github/actions/stack-gate/gate.sh`, which the agentic `Gate` workflow calls on every PR.
It never runs `make gate`, so a change that relaxes the local gate can't relax CI:

- It fails when the project's `ruff.base.toml` or `basedpyright.base.json` differs from CI's copy,
  or when `pyproject.toml` stops extending ruff's.
- ruff reads `pyproject.toml`, so the project's own additions apply in CI as they do locally.
- basedpyright extends only the project's `basedpyright.base.json`, which must match CI's copy,
  and never reads `pyproject.toml`.

In this template, CI's copies are symlinks to the base files, so the two can't differ here; Copier
writes them into the project as plain files.

The `Makefile` is the project's own entry point, so updates never touch it; the shared targets
reach it through `include python.mk`. A project adds a leg to the gate by naming it as one more
prerequisite, `gate: my-check`, without redefining the target. A project that already has a
`Makefile` and a `pyproject.toml` keeps both: it adds the `include` line and the two `extend`
lines, then deletes the targets and settings the template's files now hold.

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
the version and the answers, `Build` as the deploy workflow among them. Renovate's Copier manager
brings each new `template-agentic` release as an update PR; an update that adds a question takes
its default, so check the new answer in the PR. Once per clone, run
`bash .claude/skills/task/scripts/task.sh point-memory`.

`make gate` renders the `template-agentic` version the answers file records, renders this template
on top, and runs the rendered suites: the agentic practices protocol and the Python practices.
`AGENTIC_SRC` and `AGENTIC_REF` override that source and version, to test an unreleased agentic
change from a local clone and its branch. It also checks that a fresh render of the repository's
own answers reproduces every file `template-agentic` owns here. The `Gate` workflow comes from
`template-agentic`, as in every project: on every PR into `develop`, `staging` or `main` it checks
where the PR comes from (`main` takes `staging`, and `staging` takes `develop` or a `bugfix/*` PR
of one commit, from this repository's own branches), then runs this repository's own
`.github/actions/stack-gate`, which runs `make gate`: a template repository's CI may. `Build` runs
the gate again on `main` before it tags.
