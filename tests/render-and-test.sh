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

expect "refuses a project without the agentic layer" bash -c "
  ! uvx --quiet copier copy --quiet --defaults --data package_name=app '$OUT/src' '$OUT/alone' 2>'$OUT/alone.err' &&
  grep -q 'Apply template-agentic first' '$OUT/alone.err'"

D="$OUT/project"
uvx --quiet copier copy --quiet --defaults --vcs-ref "$AGENTIC_REF" --data issues_repo=acme/tasks "$AGENTIC_SRC" "$D"
uvx --quiet copier copy --quiet --defaults --data package_name=app --data 'test_boundaries=[release.run]' "$OUT/src" "$D"
expect "stack.json carries the test boundaries" bash -c "[ \"\$(jq -c .boundaries '$D/.claude/hooks/practices/stack.json')\" = '[\"release.run\"]' ]"
git -C "$D" init -q
git -C "$D" add -A
git -C "$D" -c user.name=t -c user.email=t@t commit -qm render

expect "answers land in .copier-answers.python-service.yaml" test -f "$D/.copier-answers.python-service.yaml"
expect "no Jinja left in rendered files" bash -c "! grep -rIl -e '{{' -e '{%' --exclude-dir=.git '$D'"
expect "stack.json names the package" bash -c "[ \"\$(jq -r .package '$D/.claude/hooks/practices/stack.json')\" = app ]"
expect "the Makefile includes python.mk" grep -qx 'include python.mk' "$D/Makefile"
expect "python.mk gates the package" grep -qx 'PACKAGE := app' "$D/python.mk"
expect "every script parses" bash -c "for f in \$(find '$D' -name '*.sh'); do bash -n \"\$f\" || exit 1; done"
expect "agentic practices protocol suite" bash "$D/.claude/hooks/practices/guard.test.sh"
expect "python practices suite" bash "$D/.claude/hooks/practices/python.test.sh"
expect "rules load for the package" grep -qxF '  - "app/**/*.py"' "$D/.claude/rules/python-conventions.md"
expect "the reviewers and their roster are rendered" bash -c "for a in plan code security test docstring; do [ -f '$D/.claude/agents/'\$a-reviewer.md ] || exit 1; done && [ -f '$D/.claude/agents/lint-problem-resolver.md' ] && [ -f '$D/.claude/review-wave.md' ]"
expect "the roster names only agents that exist" bash -c "for a in \$(grep -o -E '\\\\b[a-z]+-(reviewer|problem-resolver)\\\\b' '$D/.claude/review-wave.md' | sort -u); do [ -f '$D/.claude/agents/'\$a.md ] || { echo \"FAIL missing \$a\"; exit 1; }; done"
expect "no .yml file in the template or the project" bash -c "[ -z \"\$(find '$ROOT' '$D' -name '*.yml' -not -path '*/.git/*')\" ]"

# A fresh render of this repository's own answers must reproduce every file template-agentic owns
# here; the files it seeds once (_skip_if_exists) and the answers file are the project's. Every
# answer the file records goes in, so a question a release adds renders as answered, not default.
grep -v '^_' "$ROOT/.copier-answers.agentic.yaml" >"$OUT/self-answers.yaml"
uvx --quiet copier copy --quiet --defaults --vcs-ref "$AGENTIC_REF" --data-file "$OUT/self-answers.yaml" \
  "$AGENTIC_SRC" "$OUT/self"
expect "this repository's harness matches a render of its agentic answers" bash -c "cd '$OUT/self' &&
  find . -type f ! -name .copier-answers.agentic.yaml ! -path ./.claude/memory/MEMORY.md |
  while read -r f; do cmp -s \"\$f\" '$ROOT'/\"\$f\" || { echo \"FAIL \${f#./} differs from the render\"; exit 1; }; done"

# The product names the template was extracted from; bracketed so this line never matches itself.
expect "no product name in the template" bash -c "! grep -rIil -E 'fire[b]rain|monar[d]it|aer[i]s|truela[y]er|cloudwa[t]ch' --exclude-dir=.git --exclude=.git '$ROOT'"

exit "$fail"
