# From the python-service template: change the template, not this copy.
# The local gate, included by the project's Makefile: /gate runs make gate. The project's CI runs
# its checks itself, never through make, so relaxing a target here can't relax CI.

.PHONY: lint lint-check typecheck security duplication test gate

lint:
	uv run ruff check . --fix
	uv run ruff format .

lint-check:
	uv run ruff check .
	uv run ruff format --check .

typecheck:
	uv run basedpyright

security:
	uv run bandit -r . -x ./.venv -ll -ii

# jscpd reads .jscpd.json. A failure prints the fix order that python-conventions.md gives.
duplication:
	@uv run jscpd . || { echo "For each copy jscpd lists: delete the copy that should not exist" \
	  "first; else call the code's existing owner; extract a shared function only last. A copy" \
	  "that must stay goes between # jscpd:ignore-start and # jscpd:ignore-end, with its reason" \
	  "(.claude/rules/skipped-checks.md). No jscpd? uv add --dev jscpd"; exit 1; }

# No tests/ skips pytest. An empty tests/ still fails it, with exit 5: a mistake, not a choice.
test:
ifeq ($(wildcard tests),)
	@echo "pytest skipped: no tests/ folder"
else
	uv run pytest tests/ -v --cov
endif

gate: lint-check typecheck security duplication test
	@echo "All gate checks passed!"
