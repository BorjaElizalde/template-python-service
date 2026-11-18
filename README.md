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

The template writes five files once and never updates them, so they are the project's: `Makefile`,
`pyproject.toml`, `.gitignore`, `renovate.json` and `.claude/memory/MEMORY.md`. A first copy keeps
the ones the repository already has. Merge the template's copy into each, from `template/` at the
release's tag; for `pyproject.toml`, that is its `[tool.ruff]` and `[tool.basedpyright]` tables and
its `dev` dependency group. Then delete the targets and settings that `python.mk`,
`.claude/agentic.mk`, `ruff.base.toml` and `basedpyright.base.json` hold.

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

Apart from the project's five files, every file the template writes is the template's: change it
there, not in the project.

- **ruff**, under `[tool.ruff.lint]` in `pyproject.toml`: add rules with `extend-select`, and the
  project's exceptions with `ignore` and `extend-per-file-ignores`, each with the reason
  `.claude/rules/skipped-checks.md` asks for. Never use `select`: it replaces the shared rule list.
- **basedpyright**, in `pyproject.toml`: an override applies to `make gate` only, not to CI.
- **jscpd**: a copy that must stay goes between `# jscpd:ignore-start` and `# jscpd:ignore-end`,
  with the reason `.claude/rules/skipped-checks.md` asks for.
- **make**, in the `Makefile`: its `include python.mk` brings the checks and `make gate`, and
  `python.mk` includes `.claude/agentic.mk`, which brings `make claude` and `make help`. Bare `make`
  runs `make help`, which lists each target that has a description on its rule line, as
  `run: ## Serve the app.`, under the file that defines it. Extend the two fragments in three ways:
  - Add the project's own targets.
  - Give a target of theirs one more prerequisite, as `gate: my-check`. That check runs in
    `make gate` only, not in CI.
  - Set a variable of theirs after the include, as `CLAUDE_FLAGS =`, which starts Claude without
    Remote Control.

  Never write a second recipe for a target of theirs: every `make` call then warns that it
  overrides the target's commands. A project that has its own `claude` or `help` target deletes it
  when an update brings the template's.
- **Tests**: with no `tests/` folder, `make gate` and CI skip pytest. An empty `tests/` fails both.
