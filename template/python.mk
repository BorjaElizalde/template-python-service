# From the python-service template: change the template, not this copy.
# The local gate, included by the project's Makefile: /gate runs make gate. The project's CI runs
# its checks itself, never through make, so relaxing a target here can't relax CI.
# The include is here, not in the project's Makefile, which an update never changes.
include .claude/agentic.mk

.PHONY: lint lint-check typecheck security duplication test gate

lint: ## Fix what ruff can fix, and format every file.
	uv run ruff check . --fix
	uv run ruff format .

lint-check: ## Check ruff's rules and the format, and change no file.
	uv run ruff check .
	uv run ruff format --check .

typecheck: ## Check the types with basedpyright.
	uv run basedpyright

security: ## Scan for security issues with bandit.
	uv run bandit -r . -x ./.venv -ll -ii

# jscpd reads .jscpd.json. A failure prints the fix order that python-conventions.md gives.
duplication: ## Fail on a block of code written twice, with jscpd.
	@uv run jscpd . || { echo "For each copy jscpd lists: delete the copy that should not exist" \
	  "first; else call the code's existing owner; extract a shared function only last. A copy" \
	  "that must stay goes between # jscpd:ignore-start and # jscpd:ignore-end, with its reason" \
	  "(.claude/rules/skipped-checks.md). No jscpd? uv add --dev jscpd"; exit 1; }

# pytest-cov's --cov-fail-under replaces the fail_under that pyproject.toml sets, so the floor
# passed is the project's own when it sets one, else the template's, as in gate.sh and config.jq.
coverage_floor = $(or $(shell sed -n 's/^ *fail_under *= *\([0-9.]*\).*/\1/p' pyproject.toml),97)

# No tests/ skips pytest. An empty tests/ still fails it, with exit 5: a mistake, not a choice.
test: ## Run pytest with the coverage floor, or skip it when there is no tests/ folder.
ifeq ($(wildcard tests),)
	@echo "pytest skipped: no tests/ folder"
else
	uv run pytest tests/ -v --cov --cov-fail-under=$(coverage_floor)
endif

gate: lint-check typecheck security duplication test ## Run every local check.
	@echo "All gate checks passed!"
