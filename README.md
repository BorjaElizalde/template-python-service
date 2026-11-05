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

`make gate` renders `template-agentic` (`AGENTIC_SRC`, a git URL or a local clone; its newest tag),
renders this template on top, and runs the rendered suites: the agentic practices protocol and the
Python practices. The `Gate` workflow runs it on every PR, and `Build` again on `main` before it
tags; both check out `template-agentic` with the read-only deploy key in the
`TEMPLATE_AGENTIC_DEPLOY_KEY` secret.
