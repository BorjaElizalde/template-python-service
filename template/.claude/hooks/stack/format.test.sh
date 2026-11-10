#!/usr/bin/env bash
# From the python-service template: change the template, not this copy.
# Table-driven regression suite for format.sh, the after-edit hook beside it. Run from any
# checkout: bash .claude/hooks/stack/format.test.sh
# Each case writes a file, then feeds the hook an edit of it. Expect F = formatted, U = left as
# written. The hook must exit 0 in every case; a case where it does not fails.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# The hook formats with the ruff of the project three levels above it. It runs from a copy in a
# throwaway project whose only tool is ruff, so the cases never depend on this project.
PROJECT="$(mktemp -d)"; TREE="$(mktemp -d)"; OTHER="$(mktemp -d)"; NOGIT="$(mktemp -d)"
trap 'rm -rf "$PROJECT" "$TREE" "$OTHER" "$NOGIT"' EXIT
mkdir -p "$PROJECT/.claude/hooks/stack"
cp "$HERE/format.sh" "$PROJECT/.claude/hooks/stack/"
HOOK="$PROJECT/.claude/hooks/stack/format.sh"
printf '[dependency-groups]\ndev = ["ruff"]\n' >"$PROJECT/pyproject.toml"
git -C "$PROJECT" init -q
git -C "$PROJECT" add -A
git -C "$PROJECT" -c user.name=t -c user.email=t@t commit -qm project
git -C "$PROJECT" worktree add -q --detach "$TREE"
git -C "$OTHER" init -q
pass=0; fail=0
NOTEBOOK='{"cells": [{"cell_type": "code", "execution_count": null, "metadata": {}, "outputs": [],
  "source": ["x=1"]}], "metadata": {}, "nbformat": 4, "nbformat_minor": 5}'

check() {  # check <want> <desc> <path> [content]: <content>, unformatted Python by default
  local content="${4:-x=1}" code got=U
  printf '%s\n' "$content" >"$3"
  jq -n --arg p "$3" '{tool_input:{file_path:$p}}' | bash "$HOOK" >/dev/null 2>&1; code=$?
  [ "$(cat "$3")" = "$content" ] || got=F
  [ "$code" -eq 0 ] || got="exit $code"
  if [ "$got" = "$1" ]; then pass=$((pass+1)); echo "PASS ($got) $2"
  else fail=$((fail+1)); echo "FAIL (want $1, got $got) $2"; fi
}

echo "-- a Python file or stub of the project (formats it)"
check F "in the project's checkout"        "$PROJECT/case.py"
check F "in a linked worktree"             "$TREE/case.py"
check F "a stub"                           "$PROJECT/case.pyi"

echo "-- any other file (leaves it as written)"
check U "a file that is not Python"        "$PROJECT/case.txt"
check U "a notebook, which the gate skips" "$PROJECT/case.ipynb" "$NOTEBOOK"
check U "a Python file in another repo"    "$OTHER/case.py"
check U "a Python file outside any repo"   "$NOGIT/case.py"
check U "a Python file ruff cannot parse"  "$PROJECT/broken.py" 'x=('

echo "== $pass passed, $fail failed"
[ "$fail" -eq 0 ]
