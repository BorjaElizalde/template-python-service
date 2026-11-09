#!/usr/bin/env bash
# Renders template-agentic, then this template on top, the way a project gets them, and runs the
# rendered harness's suites. Needs uv, git and jq.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# This repository applies template-agentic to itself, and every render here uses the source and
# version its answers record, so a new agentic release reaches this gate through its update PR.
# AGENTIC_SRC and AGENTIC_REF override them to test an unreleased change: a local clone and a branch.
answer() { sed -n "s/^$1: '\{0,1\}\([^']*\)'\{0,1\}\$/\1/p" "$ROOT/.copier-answers.agentic.yaml"; }
AGENTIC_SRC="${AGENTIC_SRC:-$(answer _src_path)}"
AGENTIC_REF="${AGENTIC_REF:-$(answer _commit)}"
# The real path: Copier compares the resolved answers path with the project path, so a project
# reached through a symlink (macOS /var -> /private/var) reads its own answers as outside it.
OUT="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$OUT"' EXIT
fail=0

# A plain copy, so the render is the working tree whether or not it is committed or tagged.
mkdir -p "$OUT/src"
(cd "$ROOT" && tar --exclude .git -cf - .) | tar -xf - -C "$OUT/src"

expect() {  # expect <desc> <command...>; a failure prints the command's own lines that report it
  local out
  if out="$("${@:2}" 2>&1)"; then echo "PASS $1"
  else echo "FAIL $1"; { grep -E 'FAIL|rror' <<<"$out" || tail -n 3 <<<"$out"; } | head -20 | sed 's/^/    /'; fail=1; fi
}

# A project takes the next release with copier update. Copier renders the old version and the new
# one into empty folders, so a question that reads another layer's files fails the update.
V="$OUT/versions"
U="$OUT/updated"
mkdir -p "$V"
(cd "$OUT/src" && tar -cf - .) | tar -xf - -C "$V"
git -C "$V" init -q
git -C "$V" add -A
git -C "$V" -c user.name=t -c user.email=t@t commit -qm v1
git -C "$V" tag v1
printf 'probe\n' >"$V/template/update-probe.txt"
git -C "$V" add -A
git -C "$V" -c user.name=t -c user.email=t@t commit -qm v2
git -C "$V" tag v2
uvx --quiet copier copy --quiet --defaults --vcs-ref "$AGENTIC_REF" --data issues_repo=acme/tasks "$AGENTIC_SRC" "$U"
uvx --quiet copier copy --quiet --defaults --vcs-ref v1 --data package_name=app "$V" "$U"
git -C "$U" init -q
git -C "$U" add -A
git -C "$U" -c user.name=t -c user.email=t@t commit -qm copy
expect "a project takes the next release with copier update" bash -c "cd '$U' &&
  GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
    uvx --quiet copier update --quiet --skip-answered --defaults -a .copier-answers.python-service.yaml --vcs-ref v2 &&
  [ -f update-probe.txt ] && grep -qx '_commit: v2' .copier-answers.python-service.yaml"

D="$OUT/project"
uvx --quiet copier copy --quiet --defaults --vcs-ref "$AGENTIC_REF" --data issues_repo=acme/tasks "$AGENTIC_SRC" "$D"
uvx --quiet copier copy --quiet --defaults --data package_name=app --data 'test_boundaries=[release.run]' "$OUT/src" "$D"
expect "stack.json carries the test boundaries" bash -c "[ \"\$(jq -c .boundaries '$D/.claude/hooks/practices/stack.json')\" = '[\"release.run\"]' ]"
git -C "$D" init -q
git -C "$D" add -A
git -C "$D" -c user.name=t -c user.email=t@t commit -qm render

expect "answers land in .copier-answers.python-service.yaml" test -f "$D/.copier-answers.python-service.yaml"
expect "no Jinja left in rendered files" bash -c "! grep -rIl -E '(^|[^\$])\\{\\{|\\{%' --exclude-dir=.git '$D'"
expect "stack.json names the package" bash -c "[ \"\$(jq -r .package '$D/.claude/hooks/practices/stack.json')\" = app ]"
expect "the Makefile includes python.mk" grep -qx 'include python.mk' "$D/Makefile"
expect "every script parses" bash -c "for f in \$(find '$D' -name '*.sh'); do bash -n \"\$f\" || exit 1; done"
expect "agentic practices protocol suite" bash "$D/.claude/hooks/practices/guard.test.sh"
expect "python practices suite" bash "$D/.claude/hooks/practices/python.test.sh"
rule_paths() {  # rule_paths <rule> <path...>: the rendered rule loads for exactly these paths
  local got
  got="$(sed -n '2,/^---$/s/^  - "\(.*\)"$/\1/p' "$D/.claude/rules/$1")"
  [ "$got" = "$(printf '%s\n' "${@:2}")" ] || { echo "FAIL $1 loads for: ${got//$'\n'/, }"; return 1; }
}
expect "the Python rules load for every Python file" rule_paths python-conventions.md '**/*.py'
expect "the service rules load only for a service's parts" rule_paths service-conventions.md \
  'app/api/**' 'app/batch/**' 'app/database.py' 'app/models/**' 'app/queries/**' 'app/services.py' 'database/**'
expect "the reviewers and their roster are rendered" bash -c "for a in plan code security test docstring; do [ -f '$D/.claude/agents/'\$a-reviewer.md ] || exit 1; done && [ -f '$D/.claude/agents/lint-problem-resolver.md' ] && [ -f '$D/.claude/review-wave.md' ]"
expect "the roster names only agents that exist" bash -c "for a in \$(grep -o -E '\\\\b[a-z]+-(reviewer|problem-resolver)\\\\b' '$D/.claude/review-wave.md' | sort -u); do [ -f '$D/.claude/agents/'\$a.md ] || { echo \"FAIL missing \$a\"; exit 1; }; done"
expect "no .yml file in the template or the project" bash -c "[ -z \"\$(find '$ROOT' '$D' -name '*.yml' -not -path '*/.git/*')\" ]"

# The seeded pyproject.toml extends the template's base files, so a new project's package and test
# pass the whole gate, and each shared setting reaches the project through it.
mkdir -p "$D/app" "$D/tests"
: >"$D/app/__init__.py"
printf 'def double(x: int) -> int:\n    return x * 2\n' >"$D/app/core.py"
printf 'from app.core import double\n\n\ndef test_double():\n    assert double(2) == 4\n' >"$D/tests/test_core.py"
expect "a new project passes make gate, its untyped test exempt from ANN" make -s -C "$D" gate
make_with() {  # make_with <file> <content> <target>: runs the target while the file holds the content
  printf '%b' "$2" >"$D/$1"
  make -s -C "$D" "$3" >/dev/null 2>&1
  local status=$?
  rm "$D/$1"
  return "$status"
}
fails_with() { ! make_with "$@"; }
UNTYPED='def f(x):\n    return x\n'
expect "lint-check applies the base's rules" fails_with app/untyped.py "$UNTYPED" lint-check
# basedpyright's own default mode is stricter than the base's and rejects an unannotated parameter.
expect "typecheck applies the base's checking mode" make_with app/untyped.py "$UNTYPED" typecheck
CAST='from typing import cast\n\n\ndef k(x: int) -> int:\n    return cast(int, x)\n'
expect "typecheck applies the base's added errors" fails_with app/cast.py "$CAST" typecheck

# CI's checks call each tool directly with CI's own copy of the shared settings, so a change that
# relaxes the local gate, or the project's copies of the settings, can't relax them.
CI="$D/.github/actions/stack-gate"
expect "the CI action is a valid action" uvx --quiet check-jsonschema --builtin-schema vendor.github-actions "$CI/action.yaml"
expect "CI's copies of the shared settings match the project's" bash -c "
  cmp -s '$D/ruff.base.toml' '$CI/ruff.base.toml' && cmp -s '$D/basedpyright.base.json' '$CI/basedpyright.base.json'"
ci_with() {  # ci_with <file> <content>: runs CI's checks while the file holds the content
  printf '%b' "$2" >"$D/$1"
  (cd "$D" && bash .github/actions/stack-gate/gate.sh) >/dev/null 2>&1
  local status=$?
  rm "$D/$1"
  return "$status"
}
expect "CI's checks pass a new project" ci_with app/typed.py 'def g(x: int) -> int:\n    return x\n'
relaxed() {  # relaxed <file> <text> <replacement> <command...>: runs the command while the file reads so
  local f="$D/$1" status
  cp "$f" "$OUT/relaxed.bak"
  awk -v a="$2" -v b="$3" '{ i = index($0, a); if (i) $0 = substr($0, 1, i - 1) b substr($0, i + length(a)); print }' \
    "$OUT/relaxed.bak" >"$f"
  "${@:4}"
  status=$?
  cp "$OUT/relaxed.bak" "$f"
  return "$status"
}
local_only() {  # local_only <target> <file> <content>: make <target> passes the file, CI's checks fail it
  make_with "$2" "$3" "$1" && ! ci_with "$2" "$3"
}
expect "a no-op typecheck target in python.mk relaxes make gate, not CI" \
  relaxed python.mk 'uv run basedpyright' 'true' local_only gate app/cast.py "$CAST"
expect "a rule dropped from the project's ruff.base.toml relaxes lint-check, not CI" \
  relaxed ruff.base.toml '"ANN",' '' local_only lint-check app/untyped.py "$UNTYPED"
expect "pyproject.toml that stops extending ruff's base relaxes lint-check, not CI" \
  relaxed pyproject.toml 'extend = "ruff.base.toml"' '' local_only lint-check app/untyped.py "$UNTYPED"
expect "a basedpyright override in pyproject.toml relaxes typecheck, not CI" \
  relaxed pyproject.toml 'extends = "basedpyright.base.json"' 'extends = "basedpyright.base.json"\nreportUnnecessaryCast = false' \
  local_only typecheck app/cast.py "$CAST"

# Both gates check every Python file in the repository, not only the package: in a second
# top-level folder, each tool fails the file that breaks its rule, and only its rule.
mkdir -p "$D/commons"
fails_both() {  # fails_both <target> <file> <content>: make <target> and CI's checks each fail the file
  fails_with "$2" "$3" "$1" && ! ci_with "$2" "$3"
}
INSECURE='def run(code: str) -> object:\n    return eval(code)\n'
expect "ruff checks a second top-level folder, locally and in CI" fails_both lint-check commons/untyped.py "$UNTYPED"
expect "basedpyright checks a second top-level folder, locally and in CI" fails_both typecheck commons/cast.py "$CAST"
expect "bandit checks a second top-level folder, locally and in CI" fails_both security commons/insecure.py "$INSECURE"
# The one exclusion: a notebook that breaks ruff's and basedpyright's rules passes both gates.
NOTEBOOK='{"cells": [{"cell_type": "code", "execution_count": null, "metadata": {}, "outputs": [],
  "source": ["import os\\n", "x: int = None\\n"]}], "metadata": {}, "nbformat": 4, "nbformat_minor": 5}\n'
passes_both() {  # passes_both <file> <content>: make gate and CI's checks each pass the file
  make_with "$1" "$2" gate && ci_with "$1" "$2"
}
expect "a bad notebook leaves make gate and CI green" passes_both explore.ipynb "$NOTEBOOK"
expect "ruff.base.toml's exclude is what keeps the notebook out of lint-check" \
  relaxed ruff.base.toml 'extend-exclude = ["*.ipynb"]' '' fails_with explore.ipynb "$NOTEBOOK" lint-check
expect "basedpyright.base.json's exclude is what keeps the notebook out of typecheck" \
  relaxed basedpyright.base.json '"exclude": ["**/*.ipynb"],' '' fails_with explore.ipynb "$NOTEBOOK" typecheck

# The shared pre-commit hooks run the project's own tools, so they read the same base settings.
git -C "$D" add -A
expect "pre-commit passes on a new project" bash -c "cd '$D' && uv run pre-commit run --all-files"
hook_with() {  # hook_with <file> <content> <hook>: runs one hook on the file while it holds the content
  printf '%b' "$2" >"$D/$1"
  (cd "$D" && uv run pre-commit run "$3" --files "$1") >/dev/null 2>&1
  local status=$?
  rm "$D/$1"
  return "$status"
}
fails_hook() { ! hook_with "$@"; }
# Each hook passes a clean file first: a hook id that names no hook fails too.
expect "pre-commit's ruff passes a typed file" hook_with app/typed.py 'def g(x: int) -> int:\n    return x\n' ruff-check
expect "pre-commit's ruff applies the base's rules" fails_hook app/untyped.py "$UNTYPED" ruff-check
expect "pre-commit passes a trimmed file" hook_with app/trimmed.py 'x = 1\n' trailing-whitespace
expect "pre-commit trims trailing whitespace" fails_hook app/spaced.py 'x = 1   \n' trailing-whitespace

# The seeded .gitignore keeps secrets and the gate's output out of git; the gate above left both.
expect "git ignores .env files and what the gate leaves" bash -c "cd '$D' &&
  for p in .env .env.local .coverage app/__pycache__/core.pyc; do git check-ignore -q \"\$p\" || { echo \"FAIL \$p is not ignored\"; exit 1; }; done"
expect "git still tracks .env.example" bash -c "cd '$D' && ! git check-ignore -q .env.example"
expect "git add -A staged none of what the gate left" bash -c "cd '$D' && [ -f .coverage ] && [ -d app/__pycache__ ] &&
  ! git status --porcelain --untracked-files=all | grep -E '__pycache__|\\.py[cod]\$|\\.coverage\$'"

# A first copy into a project that has its own Makefile, pyproject.toml and .gitignore keeps them.
E="$OUT/existing"
uvx --quiet copier copy --quiet --defaults --vcs-ref "$AGENTIC_REF" --data issues_repo=acme/tasks "$AGENTIC_SRC" "$E"
printf 'run:\n\t@echo run\n' >"$E/Makefile"
printf '[project]\nname = "svc"\n' >"$E/pyproject.toml"
printf '.idea/\n' >"$E/.gitignore"
uvx --quiet copier copy --quiet --defaults --data package_name=svc "$OUT/src" "$E"
expect "a first copy keeps the project's Makefile, pyproject.toml and .gitignore" bash -c "
  [ \"\$(cat '$E/Makefile')\" = \"\$(printf 'run:\n\t@echo run')\" ] && [ \"\$(cat '$E/pyproject.toml')\" = \"\$(printf '[project]\nname = \"svc\"')\" ] &&
  [ \"\$(cat '$E/.gitignore')\" = .idea/ ] &&
  [ -f '$E/python.mk' ] && [ -f '$E/ruff.base.toml' ] && [ -f '$E/basedpyright.base.json' ]"

# A fresh render of this repository's own answers must reproduce every file template-agentic owns
# here; the files it seeds once (_skip_if_exists) and the answers file are the project's. Every
# answer the file records goes in, so a question a release adds renders as answered, not default.
grep -v '^_' "$ROOT/.copier-answers.agentic.yaml" >"$OUT/self-answers.yaml"
uvx --quiet copier copy --quiet --defaults --vcs-ref "$AGENTIC_REF" --data-file "$OUT/self-answers.yaml" \
  "$AGENTIC_SRC" "$OUT/self"
expect "this repository's harness matches a render of its agentic answers" bash -c "cd '$OUT/self' &&
  find . -type f ! -name .copier-answers.agentic.yaml ! -path ./.claude/memory/MEMORY.md ! -path ./renovate.json |
  while read -r f; do cmp -s \"\$f\" '$ROOT'/\"\$f\" || { echo \"FAIL \${f#./} differs from the render\"; exit 1; }; done"

# The product names the template was extracted from; bracketed so this line never matches itself.
expect "no product name in the template" bash -c "! grep -rIil -E 'fire[b]rain|monar[d]it|aer[i]s|truela[y]er|cloudwa[t]ch' --exclude-dir=.git --exclude=.git '$ROOT'"

exit "$fail"
