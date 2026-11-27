#!/usr/bin/env bash
# Releases this template the way Build does, template-agentic bundled in, copies it the way a
# project gets it, and runs the rendered harness's suites. Needs uv, git and jq.
# SC2329: each check below is a function passed to expect as its command, so expect prints the
# check's result and counts its failure. Tried calling each check directly, but then nothing
# reports or counts it. Tried a directive on each function, but that repeats this reason for
# every check. Tried ending without exit, which shellcheck accepts, but only because it then
# takes this script for one another script sources.
# shellcheck disable=SC2329
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# The real path: Copier compares the resolved answers path with the project path, so a project
# reached through a symlink (macOS /var -> /private/var) reads its own answers as outside it.
OUT="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$OUT"' EXIT
fail=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

expect() {  # expect <desc> <command...>; a failure prints the command's own lines that report it
  local out
  if out="$("${@:2}" 2>&1)"; then echo "PASS $1"
  else echo "FAIL $1"; { grep -E 'FAIL|rror' <<<"$out" || tail -n 3 <<<"$out"; } | head -20 | sed 's/^/    /'; fail=1; fi
}
commit() { git -C "$1" add -A && git -C "$1" commit -qm "$2"; }
git -c advice.detachedHead=false clone --quiet --branch "$AGENTIC_REF" "$AGENTIC_SRC" "$OUT/agentic"

# V is this repository: v0 a release from before the bundle, which had no guard, and main the
# working tree, committed or not.
V="$OUT/versions"
mkdir "$V"
(cd "$ROOT" && tar --exclude .git -cf - .) | tar -xf - -C "$V"
git -C "$V" init -q -b main
cp "$OUT/agentic/template/{{ _copier_conf.answers_file }}.jinja" "$V/template/"
sed "s/{% if 'issues_repo'[^%]*%}[^%]*{% elif /{% if /" "$ROOT/copier.yaml" >"$V/copier.yaml"
commit "$V" v0 && git -C "$V" tag v0
rm "$V/template/{{ _copier_conf.answers_file }}.jinja"
cp "$ROOT/copier.yaml" "$V/copier.yaml"
commit "$V" main
build() {  # build <tag> [<make variable>...]: what Build does on a merge to main
  rm -rf "$OUT/build"
  git clone --quiet --depth 1 --branch main "file://$V" "$OUT/build"
  make -s -C "$OUT/build" release-tag TAG="$1" "${@:2}"
}
build v1

AGENTIC_ANSWERS=(--data issues_repo=acme/tasks --data worktree_root=../trees)
PYTHON_ANSWERS=(--data package_name=app --data 'test_boundaries=[release.run]')
# A two-layer project on an earlier agentic release, which the README's first step brings forward.
TWO="$OUT/two-layers"
uvx --quiet copier copy --quiet --defaults --vcs-ref "$(git -C "$OUT/agentic" describe --tags --abbrev=0 HEAD~1)" \
  "${AGENTIC_ANSWERS[@]}" "$OUT/agentic" "$TWO"
uvx --quiet copier copy --quiet --defaults --vcs-ref v0 "${PYTHON_ANSWERS[@]}" "$V" "$TWO"
git -C "$TWO" init -q
commit "$TWO" two-layers
(cd "$TWO" && uvx --quiet copier update --quiet --defaults -a .copier-answers.agentic.yaml --vcs-ref HEAD)
commit "$TWO" agentic
D="$OUT/project"
uvx --quiet copier copy --quiet --defaults "${AGENTIC_ANSWERS[@]}" "${PYTHON_ANSWERS[@]}" "$V" "$D"
like_two_layers() {
  diff -rq --exclude .git --exclude '.copier-answers.*' --exclude renovate.json --exclude MEMORY.md "$TWO" "$D" &&
    [ "$(cd "$D" && ls -d .copier-answers.*)" = .copier-answers.python-service.yaml ] &&
    cmp "$OUT/agentic/template/renovate.json" "$D/renovate.json" &&
    cmp "$OUT/agentic/template/.claude/memory/MEMORY.md" "$D/.claude/memory/MEMORY.md" &&
    grep -qx '_commit: v1' "$D/.copier-answers.python-service.yaml" &&
    grep -qx 'worktree_root: ../trees' "$D/.copier-answers.python-service.yaml" &&
    grep -qx 'package_name: app' "$D/.copier-answers.python-service.yaml"
}
expect "a copy of this template's newest release gives the two layers' files, with one answers file" like_two_layers
branch_copy_fails() {
  local out
  ! out="$(uvx --quiet copier copy --quiet --defaults --vcs-ref main "${AGENTIC_ANSWERS[@]}" "${PYTHON_ANSWERS[@]}" \
    "$V" "$OUT/branch" 2>&1)" &&
    grep -q 'Copy a release tag' <<<"$out"
}
expect "a copy of a branch fails and says to copy a release, even given the agentic answers" branch_copy_fails

printf 'own:\n\t@echo own\n' >>"$TWO/Makefile"
printf '{}\n' >"$TWO/renovate.json"
commit "$TWO" own
moves_to_one() {
  (cd "$TWO" &&
    grep -v '^[_#]' .copier-answers.agentic.yaml >>.copier-answers.python-service.yaml &&
    git rm -q .copier-answers.agentic.yaml && git commit -qam 'Keep one answers file' &&
    uvx --quiet copier update --quiet --defaults -a .copier-answers.python-service.yaml --vcs-ref v1) &&
    diff -rq --exclude .git --exclude Makefile --exclude renovate.json --exclude MEMORY.md "$TWO" "$D" &&
    grep -qx 'own:' "$TWO/Makefile" && [ "$(cat "$TWO/renovate.json")" = '{}' ]
}
expect "the README's steps move a two-layer project to one answers file, keeping its answers and seeded files" moves_to_one

cp -R "$OUT/agentic" "$OUT/agentic-next"
printf 'probe\n' >"$OUT/agentic-next/template/update-probe.txt"
commit "$OUT/agentic-next" next && git -C "$OUT/agentic-next" tag next
build v2 AGENTIC_SRC="file://$OUT/agentic-next" AGENTIC_REF=next
expect "a release is a commit off main whose second parent is the release before it" bash -c "cd '$V' &&
  [ \"\$(git rev-parse v2^1 v2^2)\" = \"\$(git rev-parse main v1)\" ] && [ -z \"\$(git branch --contains v1)\" ]"
has_parts() {  # has_parts <project> [<part>...]: the project's rule folders and stack.json hold exactly these parts
  local folders parts
  folders="$(find "$1/.claude/rules" -mindepth 1 -type d -exec basename {} \; | sort | paste -sd ' ' -)"
  parts="$(jq -r '.parts | sort | join(" ")' "$1/.claude/hooks/practices/stack.json")"
  [ "$folders" = "${*:2}" ] && [ "$parts" = "${*:2}" ] ||
    { echo "FAIL rule folders: '$folders', stack.json's parts: '$parts'"; return 1; }
}
git -C "$D" init -q
# The answers of a project copied before the parts question hold none.
ANSWERS="$D/.copier-answers.python-service.yaml"
awk '/^parts:$/ { skip = 1; next } skip && /^- / { next } { skip = 0; print }' "$ANSWERS" >"$OUT/answers.yaml"
mv "$OUT/answers.yaml" "$ANSWERS"
commit "$D" copy
# Renovate's update PR runs copier update with --skip-answered --defaults, as this one does.
expect "copier update across a release that bundles an agentic change delivers it" bash -c "cd '$D' &&
  uvx --quiet copier update --quiet --skip-answered --defaults -a .copier-answers.python-service.yaml --vcs-ref v2 &&
  [ -f update-probe.txt ] && grep -qx '_commit: v2' .copier-answers.python-service.yaml"
expect "an update gives a project whose answers hold no parts every part" has_parts "$D" api batch database

expect "stack.json carries the test boundaries" bash -c "[ \"\$(jq -c .boundaries '$D/.claude/hooks/practices/stack.json')\" = '[\"release.run\"]' ]"
expect "stack.json names the package" bash -c "[ \"\$(jq -r .package '$D/.claude/hooks/practices/stack.json')\" = app ]"
expect "every script parses" bash -c "for f in \$(find '$D' -name '*.sh'); do bash -n \"\$f\" || exit 1; done"
expect "shellcheck passes this template's scripts and the tests'" bash -c "cd '$ROOT' &&
  find template tests -name '*.sh' -exec uvx --quiet --from shellcheck-py shellcheck -f gcc {} +"
expect "agentic practices protocol suite" bash "$D/.claude/hooks/practices/guard.test.sh"
expect "python practices suite" bash "$D/.claude/hooks/practices/python.test.sh"
expect "format hook suite" bash "$D/.claude/hooks/stack/format.test.sh"
rule_paths() {  # rule_paths <rule> <path...>: the rendered rule loads for exactly these paths
  local got
  got="$(sed -n '2,/^---$/s/^  - "\(.*\)"$/\1/p' "$D/.claude/rules/$1")"
  [ "$got" = "$(printf '%s\n' "${@:2}")" ] || { echo "FAIL $1 loads for: ${got//$'\n'/, }"; return 1; }
}
expect "the Python rules load for every Python file" rule_paths python-conventions.md '**/*.py'
# A part's rule file is in a project only when it picked the part: copier.yaml decides that, so its paths need not.
for rule in services.md api/endpoints.md api/mcp.md batch/tasks.md database/orm.md database/migrations.md; do
  expect "the part rules of $rule load for every Python file" rule_paths "$rule" '**/*.py'
done
expect "no rule file holds a Jinja condition: copier.yaml picks the rule files" \
  bash -c "! grep -rn '{%' '$ROOT/template/.claude/rules'"

# A copy for each answer to the parts question: no part, each part alone, and all three (the project
# above). Each gets the rules, hook checks and tool settings of its parts alone.
part_copy() {  # part_copy <project> <parts>: the newest release, copied with this parts answer into a git repository
  uvx --quiet copier copy --quiet --defaults "${AGENTIC_ANSWERS[@]}" --data package_name=app --data "parts=$2" \
    "$V" "$1" && git -C "$1" init -q
}
NONE="$OUT/no-part" API="$OUT/api" BATCH="$OUT/batch" DATABASE="$OUT/database"
part_copy "$NONE" '[]'
part_copy "$API" '[api]'
part_copy "$BATCH" '[batch]'
part_copy "$DATABASE" '[database]'
names_only_rules_it_has() {  # names_only_rules_it_has <project>: each rule file a file names by its path is there
  local ref
  while read -r ref; do
    [ -f "$1/$ref" ] || { echo "FAIL a file names $ref, which the project does not have"; return 1; }
  done < <(grep -rhoE '\.claude/rules/[A-Za-z0-9_/-]+\.md' --exclude-dir=.git "$1" | sort -u)
}
no_jinja_in() { ! grep -rIl -E '(^|[^$])\{\{|\{%' --exclude-dir=.git "$1"; }
has_settings_of() {  # has_settings_of <project> [<part>...]: each part's tool settings are there exactly when it is picked
  local pyright want="" got=""
  # basedpyright's settings are JSON with comments, each on a line of its own.
  pyright="$(sed '/^ *\/\//d' "$1/basedpyright.base.json")"
  if ! jq -e . "$1/.jscpd.json" >/dev/null || ! jq -e . >/dev/null <<<"$pyright"; then
    echo "FAIL a JSON settings file does not parse"
    return 1
  fi
  [[ " ${*:2} " == *" api "* ]] && want+=" FAST"
  [[ " ${*:2} " == *" database "* ]] && want+=" revisions jscpd"
  grep -q '"FAST"' "$1/ruff.base.toml" && got+=" FAST"
  jq -e 'has("executionEnvironments")' >/dev/null <<<"$pyright" && got+=" revisions"
  jq -e 'any(.ignore[]; . == "database/**")' "$1/.jscpd.json" >/dev/null && got+=" jscpd"
  [ "$got" = "$want" ] || { echo "FAIL settings:$got; want:$want"; return 1; }
}
has_services_rule() {  # has_services_rule <project> [<part>...]: services.md is there exactly with api or batch
  local want=no got=no
  [[ " ${*:2} " == *" api "* || " ${*:2} " == *" batch "* ]] && want=yes
  [ -f "$1/.claude/rules/services.md" ] && got=yes
  [ "$got" = "$want" ] || { echo "FAIL services.md is there: $got; want: $want"; return 1; }
}
# has_boundary_check <project> <boundary|no-boundary>: the guard stops a new direct test exactly
# when the project has a boundary.
has_boundary_check() {
  local status=0 stops=no want=no
  [ "$2" = boundary ] && want=yes
  jq -n --arg p "$1/tests/test_new.py" --arg c $'def test_x():\n    assert double(2) == 4\n' \
    '{tool_input: {file_path: $p, content: $c}}' | bash "$1/.claude/hooks/practices/guard.sh" >/dev/null 2>&1 ||
    status=$?
  [ "$status" -eq 2 ] && stops=yes
  [ "$stops" = "$want" ] || { echo "FAIL the guard stops a new direct test: $stops; want: $want"; return 1; }
}
part_copy_holds() {  # part_copy_holds <project> <boundary|no-boundary> [<part>...]
  has_parts "$1" "${@:3}" && has_services_rule "$1" "${@:3}" && names_only_rules_it_has "$1" && no_jinja_in "$1" &&
    has_settings_of "$1" "${@:3}" && has_boundary_check "$1" "$2"
}
expect "a copy with no part gets the Python layer alone, and a new direct test goes through" \
  part_copy_holds "$NONE" no-boundary
expect "a copy with the API gets its rules, checks and settings alone" part_copy_holds "$API" boundary api
expect "a copy with batch tasks gets their rules and checks alone" part_copy_holds "$BATCH" boundary batch
expect "a copy with a database gets its rules, checks and settings alone, and no boundary" \
  part_copy_holds "$DATABASE" no-boundary database
expect "a copy with every part gets every part's rules, checks and settings" \
  part_copy_holds "$D" boundary api batch database
changes_parts() {
  commit "$API" copy &&
    (cd "$API" && uvx --quiet copier update --quiet --defaults -a .copier-answers.python-service.yaml \
      --data 'parts=[database]') &&
    has_parts "$API" database && has_services_rule "$API" database && has_settings_of "$API" database
}
expect "an update that changes the parts adds the files of the part added and deletes those of the part dropped" \
  changes_parts
expect "no .yml file in the template or the project" bash -c "[ -z \"\$(find '$ROOT' '$D' -name '*.yml' -not -path '*/.git/*')\" ]"

# The seeded pyproject.toml extends the template's base files, so a new project's package and test
# pass the whole gate, and each shared setting reaches the project through it.
mkdir -p "$D/app" "$D/tests"
: >"$D/app/__init__.py"
printf 'def double(x: int) -> int:\n    return x * 2\n' >"$D/app/core.py"
printf 'from app.core import double\n\n\ndef test_double():\n    assert double(2) == 4\n' >"$D/tests/test_core.py"
expect "a new project passes make gate, its untyped test exempt from ANN" make -s -C "$D" gate
# Stand-ins for claude and tmux let make claude run here without starting either.
mkdir "$OUT/stand-ins"
for tool in claude tmux; do printf '#!/bin/sh\n' >"$OUT/stand-ins/$tool" && chmod +x "$OUT/stand-ins/$tool"; done
HOOK="$D/.git/hooks/pre-commit"
installs_hooks() {  # installs_hooks <checkout>: make claude there installs the clone's missing hook
  rm -f "$HOOK" && PATH="$OUT/stand-ins:$PATH" make -s -C "$1" claude && [ -f "$HOOK" ]
}
expect "make claude installs the commit hooks in a clone that has none" installs_hooks "$D"
worktree_installs_from_main_checkout() {
  git -C "$D" worktree add -q --detach "$OUT/worktree" && installs_hooks "$OUT/worktree" &&
    git -C "$D" worktree remove "$OUT/worktree" && grep -qF "$D/.venv/" "$HOOK"
}
expect "make claude in a worktree installs hooks that run the main checkout's .venv" worktree_installs_from_main_checkout
# uv sees only the Pythons it installs, and none is installed, as on a new CI runner: it downloads
# the newest one the project allows, whatever this machine has. The environment goes outside the
# project, so the checks below keep make gate's.
runs_python_314() {
  (cd "$D" && UV_PYTHON_INSTALL_DIR="$OUT/pythons" UV_PYTHON_PREFERENCE=only-managed UV_PROJECT_ENVIRONMENT="$OUT/venv" \
    uv run --quiet python -c 'import sys; assert sys.version_info[:2] == (3, 14), sys.version')
}
expect "a new project's environment runs Python 3.14, even where uv can download a newer one" runs_python_314
printf 'own: ## Check what only this project checks.\n\t@echo own ran\n\ngate: own\n' >>"$D/Makefile"
help_lists_each_layer() {  # each target bare make lists, after the file it is listed under
  local owners
  owners="$(make -s -C "$D" | awk '/^[^ ]/ { f = $0 } /^  / { print f, $1 }')"
  [[ "$owners" == *'Makefile own'*'python.mk gate'*'.claude/agentic.mk claude'* ]] ||
    { echo "FAIL bare make listed: ${owners//$'\n'/, }"; return 1; }
}
expect "bare make lists the project's own target, then python.mk's gate, and claude from the agentic fragment" help_lists_each_layer
expect "make gate runs the check a project's Makefile adds as its prerequisite" \
  bash -o pipefail -c "make -s -C '$D' gate | grep -x 'own ran'"
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
expect "lint-check reads a stub file" fails_with app/untyped.pyi "$UNTYPED" lint-check
# Ruff takes any module path as a banned-api key, so only a banned call shows that the key is right.
CAST='from typing import cast\n\n\ndef k(x: int) -> int:\n    return cast(int, x)\n'
expect "lint-check applies the base's ban on typing.cast" fails_with app/cast.py "$CAST" lint-check
# Strict mode passes an explicit Any; recommended warns, and a warning fails the check.
EXPLICIT_ANY='from typing import Any\n\n\ndef echo(x: Any) -> Any:\n    return x\n'
expect "make typecheck checks types in basedpyright's recommended mode" \
  fails_with app/explicit_any.py "$EXPLICIT_ANY" typecheck
expect "a call made only for its effect passes make gate" \
  make_with app/effect.py 'def first(d: dict[str, int]) -> None:\n    d.setdefault("a", 0)\n' gate
with_file() {  # with_file <file> <content> <command...>: runs the command while the file holds the content
  printf '%b' "$2" >"$D/$1"
  "${@:3}"
  local status=$?
  rm "$D/$1"
  return "$status"
}
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
fails_committed() {  # fails_committed <target> <file> <content>: make <target> fails the file while git holds it
  local fails=no
  printf '%b' "$3" >"$D/$2" && git -C "$D" add -f "$2"
  make -s -C "$D" "$1" >/dev/null 2>&1 || fails=yes
  git -C "$D" rm -qf "$2"
  [ "$fails" = yes ]
}
expect "lint-check checks a committed file that .gitignore lists" \
  with_file app/.gitignore 'untyped.py\n' fails_committed lint-check app/untyped.py "$UNTYPED"
expect "lint-check checks a committed file that .ignore lists" \
  with_file .ignore 'app/untyped.py\n' fails_committed lint-check app/untyped.py "$UNTYPED"
expect "lint-check skips a file that .gitignore lists and git holds no copy of" \
  with_file app/.gitignore 'untyped.py\n' make_with app/untyped.py "$UNTYPED" lint-check
# ruff takes the Python version from pyproject.toml's requires-python, and UP040 applies from 3.12.
TYPE_ALIAS='from typing import TypeAlias\n\nNumber: TypeAlias = int\n'
expect "make lint-check checks ruff's rules for the project's Python version" \
  fails_with app/alias.py "$TYPE_ALIAS" lint-check

# make gate checks every Python file in the repository, not only the package: in a second
# top-level folder, each tool fails the file that breaks its rule.
mkdir -p "$D/commons"
ISINSTANCE='def k(x: int) -> bool:\n    return isinstance(x, int)\n'
INSECURE='import hashlib\n\n\ndef digest(data: bytes) -> str:\n    return hashlib.md5(data).hexdigest()\n'
expect "ruff checks a second top-level folder" fails_with commons/untyped.py "$UNTYPED" lint-check
expect "basedpyright checks a second top-level folder" fails_with commons/isinstance.py "$ISINSTANCE" typecheck
expect "bandit checks a second top-level folder" fails_with commons/insecure.py "$INSECURE" security
# The one exclusion: a notebook that breaks ruff's and basedpyright's rules passes make gate.
NOTEBOOK='{"cells": [{"cell_type": "code", "execution_count": null, "metadata": {}, "outputs": [],
  "source": ["import os\\n", "x: int = None\\n"]}], "metadata": {}, "nbformat": 4, "nbformat_minor": 5}\n'
expect "a bad notebook leaves make gate green" make_with explore.ipynb "$NOTEBOOK" gate
expect "ruff.base.toml's exclude is what keeps the notebook out of lint-check" \
  relaxed ruff.base.toml 'extend-exclude = ["*.ipynb"]' '' fails_with explore.ipynb "$NOTEBOOK" lint-check
expect "basedpyright.base.json's exclude is what keeps the notebook out of typecheck" \
  relaxed basedpyright.base.json '"exclude": ["**/*.ipynb"],' '' fails_with explore.ipynb "$NOTEBOOK" typecheck

# make gate checks an Alembic revision against the SQLAlchemy and Alembic the project installs. The
# revision is as Alembic writes it once ruff has fixed it, and its sa.Double() is Double[Unknown].
cp "$D/pyproject.toml" "$D/uv.lock" "$OUT/"
(cd "$D" && uv add --quiet sqlalchemy alembic)
mkdir -p "$D/database/versions"
REVISION='"""add a price

Revision ID: b2c3
Revises:
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "b2c3"
down_revision: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table("price", sa.Column("amount", sa.Double(), nullable=False))


def downgrade() -> None:
    op.drop_table("price")
'
expect "an Alembic revision passes make gate" make_with database/versions/b2c3_add_a_price.py "$REVISION" gate
expect "basedpyright checks an Alembic revision" \
  fails_with database/versions/b2c3_add_a_price.py "${REVISION/drop_table/drop_tabel}" typecheck
rm -r "$D/database"
cp "$OUT/pyproject.toml" "$OUT/uv.lock" "$D/"

# make gate fails a block of 10 lines or more written twice, and only that: every other check
# passes the same file once its copy sits between the ignore markers. The two returns differ, so
# each copy ends inside its return line: jscpd at times counts the blank lines after a copy too.
copy() {  # copy <name> <lines> <returned>: a block of <lines> lines, from the def to the return
  local adds=(amount tax fee tip)
  printf 'def %s(orders: list[dict[str, int]]) -> dict[int, int]:\n' "$1"
  printf '    totals: dict[int, int] = {}\n    for order in orders:\n'
  printf '        key = order["customer"]\n        totals.setdefault(key, 0)\n'
  printf '        totals[key] += order["%s"]\n' "${adds[@]:0:$(($2 - 6))}"
  printf '    return %s\n' "$3"
}
twice() {  # twice <lines>: the block written twice in one file
  copy total_a "$1" totals; printf '\n\n'; copy total_b "$1" 'dict(totals)'
}
COPIES="$(twice 10)\n"
MARKED="$(copy total_a 10 totals
  printf '\n\n# jscpd:ignore-start the totals change apart. Tried calling total_a, but its fees differ.\n'
  copy total_b 10 'dict(totals)'; printf '\n\n# jscpd:ignore-end')\n"
expect "a 10-line block written twice fails make duplication" fails_with app/copies.py "$COPIES" duplication
expect "the same file passes make gate with its copy between the markers" make_with app/copies.py "$MARKED" gate
expect "a 9-line block written twice passes make gate" make_with app/copies.py "$(twice 9)\n" gate
expect "a block written twice in tests/ passes make gate" make_with tests/copies.py "$COPIES" gate
mkdir "$D/database"
expect "a block written twice in database/ passes make gate" make_with database/copies.py "$COPIES" gate
rmdir "$D/database"
expect "duplication checks a committed file that .gitignore lists" \
  with_file app/.gitignore 'copies.py\n' fails_committed duplication app/copies.py "$COPIES"
expect "duplication checks a committed file that .ignore lists" \
  with_file .ignore 'app/copies.py\n' fails_committed duplication app/copies.py "$COPIES"
duplication_skips_deleted_files() {  # make duplication passes while git holds a Python file gone from disk
  printf 'x = 1\n' >"$D/app/gone.py" && git -C "$D" add app/gone.py && rm "$D/app/gone.py"
  make -s -C "$D" duplication >/dev/null 2>&1
  local status=$?
  git -C "$D" rm -q --cached app/gone.py
  return "$status"
}
expect "duplication passes while git holds a Python file that is gone from disk" duplication_skips_deleted_files
expect "ruff.base.toml's jscpd task tag is what keeps the markers out of ERA001" \
  relaxed ruff.base.toml ', "jscpd"]' ']' fails_with app/copies.py "$MARKED" lint-check

# A project may have no tests/: make gate skips pytest, with the seeded pyproject.toml unchanged.
# An empty tests/ fails it; the passing run before it shows that pytest is what fails it.
mv "$D/tests" "$OUT/tests"
expect "a project with no tests/ passes make gate, which says it skipped pytest" \
  bash -o pipefail -c "make -s -C '$D' gate | grep 'pytest skipped'"
mkdir "$D/tests"
expect "make gate fails a project with an empty tests/" bash -c "! make -s -C '$D' gate"
rm -r "$D/tests"
mv "$OUT/tests" "$D/tests"

# The shared pre-commit hooks run the project's own tools, so they read the same base settings.
git -C "$D" add -A
expect "pre-commit passes on a new project" bash -c "cd '$D' && uv run pre-commit run --all-files"
hook_with() {  # hook_with <file> <content> [<pre-commit run argument>...]: runs pre-commit on the file while it holds the content
  printf '%b' "$2" >"$D/$1"
  git -C "$D" add "$1"  # as a commit would: gitleaks reads only what is staged
  (cd "$D" && uv run pre-commit run "${@:3}" --files "$1") >/dev/null 2>&1
  local status=$?
  git -C "$D" rm -qf "$1"
  return "$status"
}
fails_hook() { ! hook_with "$@"; }
# Each template hook passes a clean file first: a hook id that names no hook fails too.
BASE=(--config pre-commit.base.yaml)
expect "pre-commit's ruff passes a typed file" hook_with app/typed.py 'def g(x: int) -> int:\n    return x\n' "${BASE[@]}" ruff-check
expect "pre-commit's ruff applies the base's rules" fails_hook app/untyped.py "$UNTYPED" "${BASE[@]}" ruff-check
expect "pre-commit passes a trimmed file" hook_with app/trimmed.py 'x = 1\n' "${BASE[@]}" trailing-whitespace
expect "pre-commit trims trailing whitespace" fails_hook app/spaced.py 'x = 1   \n' "${BASE[@]}" trailing-whitespace
# The secrets are made at run time, so this file holds none for a scanner to find.
TOKEN="ghp_$(od -An -tx1 -N18 /dev/urandom | tr -d ' \n')"
PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----\n$(head -c 900 /dev/urandom | base64)\n-----END RSA PRIVATE KEY-----\n"
expect "pre-commit's gitleaks passes a file with no secret" hook_with app/typed.py 'def g(x: int) -> int:\n    return x\n' "${BASE[@]}" gitleaks
expect "pre-commit's gitleaks stops a token in a Python file" fails_hook app/settings.py "TOKEN = \"$TOKEN\"\n" "${BASE[@]}" gitleaks
expect "pre-commit's gitleaks stops a private key in a file of another type" fails_hook deploy.pem "$PRIVATE_KEY" "${BASE[@]}" gitleaks
# The practices hook asks for a skip's reason in these places, so gitleaks must still skip there.
REASON='A fixture GitHub never issued. Tried a stub, but it hides the token format.'
expect "pre-commit's gitleaks skips a line that holds gitleaks:allow and its reason" hook_with app/fixture.py \
  "TOKEN = \"$TOKEN\"  # gitleaks:allow $REASON\n" "${BASE[@]}" gitleaks
printf '# %s\napp/fixture.py:github-pat:1\n' "$REASON" >"$D/.gitleaksignore"
expect "pre-commit's gitleaks skips a fingerprint listed under its reason" hook_with app/fixture.py "TOKEN = \"$TOKEN\"\n" \
  "${BASE[@]}" gitleaks
rm "$D/.gitleaksignore"

# A commit runs every hook in .pre-commit-config.yaml: the template's, through template-hooks, then
# the project's own, which go after it.
OWN_HOOK=('      - id: no-forbidden' '        name: no forbidden word' '        entry: forbidden'
  '        language: pygrep' '        types: [python]')
printf '%s\n' "${OWN_HOOK[@]}" >>"$D/.pre-commit-config.yaml"
expect "a commit's hooks pass a file that none of them rejects" hook_with app/allowed.py 'x = "allowed"\n'
expect "a commit runs the template's hooks" fails_hook app/untyped.py "$UNTYPED"
expect "a commit runs the project's own hook" fails_hook app/word.py 'x = "forbidden"\n'

# Copier updates .pre-commit-config.yaml, so a service made while every template hook sat there
# moves them to pre-commit.base.yaml on its next update. RELEASES holds three releases of the
# Python layer: v1 with that layout, v2 the current tree, v3 a change to a template hook.
RELEASES="$OUT/releases"
mkdir "$RELEASES"
git -C "$V" archive v0 | tar -xf - -C "$RELEASES"
git -C "$RELEASES" init -q -b main
mv "$RELEASES/template/pre-commit.base.yaml" "$RELEASES/template/.pre-commit-config.yaml"
commit "$RELEASES" v1 && git -C "$RELEASES" tag v1
git -C "$V" archive v0 template/.pre-commit-config.yaml template/pre-commit.base.yaml | tar -xf - -C "$RELEASES"
commit "$RELEASES" v2 && git -C "$RELEASES" tag v2
SERVICE="$OUT/service"
uvx --quiet copier copy --quiet --defaults --vcs-ref v1 "${PYTHON_ANSWERS[@]}" "$RELEASES" "$SERVICE"
git -C "$SERVICE" init -q
# update_with_no_conflict <release>: commits the service as it is, since Copier updates only a clean
# tree, updates it to the release, and fails if a file holds a conflict marker.
update_with_no_conflict() {
  commit "$SERVICE" "before $1" &&
    (cd "$SERVICE" && uvx --quiet copier update --quiet --defaults -a .copier-answers.python-service.yaml --vcs-ref "$1") &&
    ! grep -rIl --exclude-dir=.git '^<<<<<<< ' "$SERVICE"
}
moves_template_hooks() {
  update_with_no_conflict v2 && cmp -s "$RELEASES/template/.pre-commit-config.yaml" "$SERVICE/.pre-commit-config.yaml" &&
    cmp -s "$RELEASES/template/pre-commit.base.yaml" "$SERVICE/pre-commit.base.yaml"
}
expect "an update moves an older service's template hooks to pre-commit.base.yaml" moves_template_hooks
BASE_HOOKS="$RELEASES/template/pre-commit.base.yaml"
sed 's/trailing-whitespace-fixer$/& --markdown-linebreak-ext=md/' "$BASE_HOOKS" >"$OUT/base.yaml"
mv "$OUT/base.yaml" "$BASE_HOOKS"
commit "$RELEASES" v3 && git -C "$RELEASES" tag v3
keeps_own_hook() {
  printf '%s\n' "${OWN_HOOK[@]}" >>"$SERVICE/.pre-commit-config.yaml" &&
    update_with_no_conflict v3 && git -C "$SERVICE" diff --quiet HEAD -- .pre-commit-config.yaml &&
    grep -q 'trailing-whitespace-fixer --markdown-linebreak-ext=md$' "$SERVICE/pre-commit.base.yaml"
}
expect "an update that changes a template hook keeps the project's own hook, with no conflict" keeps_own_hook

# The seeded .gitignore keeps secrets and the gate's output out of git; the gate above left both.
expect "git ignores .env files and what the gate leaves" bash -c "cd '$D' &&
  for p in .env .env.local .coverage app/__pycache__/core.pyc; do git check-ignore -q \"\$p\" || { echo \"FAIL \$p is not ignored\"; exit 1; }; done"
expect "git still tracks .env.example" bash -c "cd '$D' && ! git check-ignore -q .env.example"
expect "git add -A staged none of what the gate left" bash -c "cd '$D' && [ -f .coverage ] && [ -d app/__pycache__ ] &&
  ! git status --porcelain --untracked-files=all | grep -E '__pycache__|\\.py[cod]\$|\\.coverage\$'"

# A first copy into a project that has its own Makefile, pyproject.toml and .gitignore keeps them.
E="$OUT/existing"
mkdir "$E"
printf 'run:\n\t@echo run\n' >"$E/Makefile"
printf '[project]\nname = "svc"\n' >"$E/pyproject.toml"
printf '.idea/\n' >"$E/.gitignore"
uvx --quiet copier copy --quiet --defaults --data issues_repo=acme/tasks --data package_name=svc "$V" "$E"
expect "a first copy keeps the project's Makefile, pyproject.toml and .gitignore" bash -c "
  [ \"\$(cat '$E/Makefile')\" = \"\$(printf 'run:\n\t@echo run')\" ] && [ \"\$(cat '$E/pyproject.toml')\" = \"\$(printf '[project]\nname = \"svc\"')\" ] &&
  [ \"\$(cat '$E/.gitignore')\" = .idea/ ] &&
  [ -f '$E/python.mk' ] && [ -f '$E/ruff.base.toml' ] && [ -f '$E/basedpyright.base.json' ]"

ignores_environment_version() {
  local got
  got="$(AGENTIC_SRC=stale AGENTIC_REF=stale make -s -C "$ROOT" -f Makefile -f - agentic-version \
    <<<"agentic-version: ; @echo \$(AGENTIC_SRC) \$(AGENTIC_REF)")"
  [ "$got" = "$AGENTIC_SRC $AGENTIC_REF" ] || { echo "FAIL make resolved $got"; return 1; }
}
expect "make takes the agentic version from the answers or its command line, never from a session's environment" \
  ignores_environment_version

# A fresh render of this repository's own answers must reproduce every file template-agentic owns
# here; the files it seeds once (_skip_if_exists) and the answers file are the project's. Every
# answer the file records goes in, so a question a release adds renders as answered, not default.
grep -v '^_' "$ROOT/.copier-answers.agentic.yaml" >"$OUT/self-answers.yaml"
uvx --quiet copier copy --quiet --defaults --vcs-ref HEAD --data-file "$OUT/self-answers.yaml" "$OUT/agentic" "$OUT/self"
expect "this repository's harness matches a render of its agentic answers" bash -c "cd '$OUT/self' &&
  find . -type f ! -name .copier-answers.agentic.yaml ! -path ./.claude/memory/MEMORY.md ! -path ./renovate.json |
  while read -r f; do cmp -s \"\$f\" '$ROOT'/\"\$f\" || { echo \"FAIL \${f#./} differs from the render\"; exit 1; }; done"

# The product names the template was extracted from; bracketed so this line never matches itself.
expect "no product name in the template" bash -c "! grep -rIil -E 'fire[b]rain|monar[d]it|aer[i]s|truela[y]er|cloudwa[t]ch' --exclude-dir=.git --exclude=.git '$ROOT'"

exit "$fail"
