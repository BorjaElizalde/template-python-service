#!/usr/bin/env bash
# From the python-service template: change the template, not this copy.
# The checks a project's CI runs, from the repository root. Each tool is called here, never through
# make gate, so a change that relaxes the local gate (python.mk, the Makefile) can't relax CI. CI
# holds its own copy of the shared settings, beside this script: the project's copies must match
# it, ruff reaches them through pyproject.toml's extend, and basedpyright through CI's own config,
# never pyproject.toml's [tool.basedpyright].
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
fail() { echo "::error file=$1::$2"; exit 1; }

for f in ruff.base.toml basedpyright.base.json; do
  cmp -s "$f" "$HERE/$f" ||
    fail "$f" "$f differs from CI's copy in .github/actions/stack-gate: change the template, not this copy."
done
grep -Eq "^[[:space:]]*extend[[:space:]]*=[[:space:]]*[\"']ruff\\.base\\.toml[\"']" pyproject.toml ||
  fail pyproject.toml "[tool.ruff] no longer extends ruff.base.toml, the rules CI checks."

uv sync --all-groups
uv run ruff check .
uv run ruff format --check .
# basedpyright resolves a config's paths from that file's folder, so CI's config sits at the root
# and extends the root copy of the base, which the check above holds to CI's copy.
trap 'rm -f .basedpyright-ci.json' EXIT
printf '{"extends": "basedpyright.base.json"}\n' >.basedpyright-ci.json
uv run basedpyright --project .basedpyright-ci.json
uv run bandit -r . -x ./.venv -ll -ii
# As in python.mk: no tests/ skips pytest, an empty tests/ fails it.
if [ -d tests ]; then
  uv run pytest tests --cov
else
  echo "::notice::pytest skipped: no tests/ folder"
fi
