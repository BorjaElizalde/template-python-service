# template-python-service

A [Copier](https://copier.readthedocs.io/) template that sets up agentic coding in a Python
service. Each release bundles the Claude Code harness of `template-agentic` and adds the Python
layer: the Python rules and practice checks, a ruff format hook, `make gate`, the checks CI runs on
each PR, commit hooks, and the ruff, basedpyright and jscpd settings every Python service shares.

## Set up the machine

Set up each machine once, before the first copy. Windows works through WSL2 only.

On a Mac, install [Homebrew](https://brew.sh), which also installs Apple's command line tools with
git and make, then:

```bash
brew install jq gh tmux
```

On Windows, install WSL2 with Ubuntu from a PowerShell run as administrator, then restart:

```powershell
wsl --install
```

On Ubuntu, or in WSL2's Ubuntu, install these, with tmux 3.2 or later, then gh from
[GitHub's apt repository](https://github.com/cli/cli/blob/trunk/docs/install_linux.md#debian):
Ubuntu's own `gh` package is too old.

```bash
sudo apt update && sudo apt install -y git make jq tmux
```

In WSL2, keep repositories in the Linux home folder, such as `~/projects`: under `/mnt/c` every
tool is slow. Keep Windows awake while sessions run: in Settings > System > Power & battery >
Screen, sleep & hibernate timeouts, set it never to sleep when plugged in, or use
[PowerToys Awake](https://learn.microsoft.com/windows/powertoys/awake).

Then, on every machine, install uv and Claude Code, give git your name and email, and sign in to
GitHub:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
curl -fsSL https://claude.ai/install.sh | bash
git config --global user.name "Your Name"
git config --global user.email you@example.com
gh auth login
```

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
`.claude/agentic.mk`, `ruff.base.toml` and `basedpyright.base.json` hold. Do the same when an
update brings a target the `Makefile` already has, such as `claude` or `help`. A first copy writes
the template's `.pre-commit-config.yaml`: put the repository's own hooks back after
`template-hooks`, and leave out those that `pre-commit.base.yaml` already runs.

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

## Run the sessions

Start the main session with `make claude` in the repository. It runs in the repository's own tmux,
and each task's session runs in another window of it. Press `Ctrl-b`, then `w` to pick any window
from a list, or `n` and `p` for the next and the previous one.

Closing the terminal stops no session: `make claude` in the repository brings them back. On WSL2,
if they stop anyway, set `instanceIdleTimeout=-1` under `[general]` in `%UserProfile%\.wslconfig`.
If the main session exits while task windows remain, open a window with `Ctrl-b`, then `c`, and
run `make claude` in the repository.

## Extend

Apart from the project's five files and its own hooks in `.pre-commit-config.yaml`, every file the
template writes is the template's: change it there, not in the project.

- **ruff**, under `[tool.ruff.lint]` in `pyproject.toml`: add rules with `extend-select`, and the
  project's exceptions with `ignore` and `extend-per-file-ignores`, each with the reason
  `.claude/rules/skipped-checks.md` asks for. Never use `select`: it replaces the shared rule list.
- **basedpyright**, in `pyproject.toml`: an override applies to `make gate` only, not to CI.
- **jscpd**: a copy that must stay goes between `# jscpd:ignore-start` and `# jscpd:ignore-end`,
  with the reason `.claude/rules/skipped-checks.md` asks for.
- **gitleaks**: a finding that holds no secret goes in `.gitleaksignore` as the fingerprint gitleaks
  prints, with the reason `.claude/rules/skipped-checks.md` asks for on the comment lines above it.
  Revoke a real secret first: once committed, it stays in the history, which CI scans, even after
  the code no longer holds it.
- **The gate**, in the `Makefile`: add a check as one more prerequisite, `gate: my-check`, without
  redefining `gate`. It runs in `make gate` only, not in CI.
- **Commit hooks**, in `.pre-commit-config.yaml`: add the project's own hooks after
  `template-hooks`, which runs the template's hooks from `pre-commit.base.yaml`.
- **Tests**: with no `tests/` folder, `make gate` and CI skip pytest. An empty `tests/` fails both.
