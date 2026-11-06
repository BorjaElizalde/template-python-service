#!/usr/bin/env bash
# From the python-service template: change the template, not this copy.
# The checks a project's CI runs, from the repository root. Each tool is called here, never through
# make gate, so a change that relaxes the local gate (python.mk, the Makefile) can't relax CI. CI
# holds its own copy of the shared settings, beside this script: the project's copies must match
# it, ruff reaches it through pyproject.toml's extend, and basedpyright reads only CI's copy.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
fail() { echo "::error file=$1::$2"; exit 1; }

for f in ruff.base.toml basedpyright.base.json; do
  cmp -s "$f" "$HERE/$f" ||
    fail "$f" "$f differs from CI's copy in .github/actions/stack-gate: change the template, not this copy."
done
grep -Eq "^[[:space:]]*extend[[:space:]]*=[[:space:]]*[\"']ruff\\.base\\.toml[\"']" pyproject.toml ||
  fail pyproject.toml "[tool.ruff] no longer extends ruff.base.toml, the rules CI checks."

pkg="$(jq -r .package .claude/hooks/practices/stack.json)"
uv sync --all-groups
uv run ruff check "$pkg" tests
uv run ruff format --check "$pkg" tests
# basedpyright resolves include from its config file's folder, so CI's config sits at the root.
trap 'rm -f .basedpyright-ci.json' EXIT
printf '{"extends": "%s", "include": ["%s", "tests"]}\n' "$HERE/basedpyright.base.json" "$pkg" >.basedpyright-ci.json
uv run basedpyright --project .basedpyright-ci.json
uv run bandit -r "$pkg" -ll -ii
uv run pytest tests --cov
