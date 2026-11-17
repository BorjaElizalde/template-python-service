# template-python-service

A [Copier](https://copier.readthedocs.io/) template that sets up agentic coding in a Python
service. Each release bundles the Claude Code harness of `template-agentic` and adds the Python
layer: the Python rules and practice checks, a ruff format hook, `make gate`, the checks CI runs on
each PR, commit hooks, and the ruff, basedpyright and jscpd settings every Python service shares.

## Apply and update

Apply this template alone, never `template-agentic` beside it. Copy the newest release, then update
to each new one:

```bash
uvx copier copy https://github.com/BorjaElizalde/template-python-service.git .
uvx copier update -a .copier-answers.python-service.yaml
```

With Renovate, each release comes as an update PR.

A first copy keeps a `Makefile`, `pyproject.toml`, `.gitignore` or `renovate.json` the repository
already has. Merge into each what the template's copy holds, in `template/` at the release's tag:

- `Makefile`: `include python.mk`.
- `pyproject.toml`: `extend = "ruff.base.toml"` under `[tool.ruff]`,
  `extends = "basedpyright.base.json"` under `[tool.basedpyright]`, and the `dev` dependency group.
- `.gitignore` and `renovate.json`: their lines.

Then delete the targets and settings that `python.mk`, `ruff.base.toml` and
`basedpyright.base.json` hold.

Once per repository, create `main`, `staging` and `develop` on GitHub, with `develop` as the
default branch:

```bash
git push origin main main:staging main:develop
gh repo edit --default-branch develop
```

Once per clone, install the commit hooks:

```bash
uv run pre-commit install
```

### Move a project from two answers files to one

Pick a release of this template, then:

1. Update the agentic layer to the version the release bundles, which is the `_commit` of this
   repository's `.copier-answers.agentic.yaml` at the release's tag. Copier refuses a downgrade, so
   a project past that version uses a release that bundles its version or a newer one. Commit the
   update.

   ```bash
   uvx copier update --defaults -a .copier-answers.agentic.yaml --vcs-ref <agentic-version>
   ```

2. Move the agentic answers into this template's answers file, then update to the release:

   ```bash
   grep -v '^[_#]' .copier-answers.agentic.yaml >>.copier-answers.python-service.yaml
   git rm -q .copier-answers.agentic.yaml
   git commit -qam 'Keep one answers file'
   uvx copier update --defaults -a .copier-answers.python-service.yaml --vcs-ref <release>
   ```

## Extend

The project owns five files, which the template writes once and never updates: `Makefile`,
`pyproject.toml`, `.gitignore`, `renovate.json` and `.claude/memory/MEMORY.md`. Every other file
the template writes is the template's: change it there, not in the project.

- **ruff**, under `[tool.ruff.lint]` in `pyproject.toml`: add rules with `extend-select`, and the
  project's exceptions with `ignore` and `extend-per-file-ignores`, each with the reason
  `.claude/rules/skipped-checks.md` asks for. Never use `select`: it replaces the shared rule list.
- **basedpyright**, in `pyproject.toml`: an override applies to `make gate` only, not to CI.
- **jscpd**: a copy that must stay goes between `# jscpd:ignore-start` and `# jscpd:ignore-end`,
  with the reason `.claude/rules/skipped-checks.md` asks for.
- **The gate**, in the `Makefile`: add a check as one more prerequisite, `gate: my-check`, without
  redefining `gate`. It runs in `make gate` only, not in CI.
- **Tests**: with no `tests/` folder, `make gate` and CI skip pytest. An empty `tests/` fails both.
