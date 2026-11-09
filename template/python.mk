# From the python-service template: change the template, not this copy.
# The local gate, included by the project's Makefile: /gate runs make gate. The project's CI runs
# its checks itself, never through make, so relaxing a target here can't relax CI.

.PHONY: lint lint-check typecheck security test gate

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

# No tests/ skips pytest. An empty tests/ still fails it, with exit 5: a mistake, not a choice.
test:
ifeq ($(wildcard tests),)
	@echo "pytest skipped: no tests/ folder"
else
	uv run pytest tests/ -v --cov
endif

gate: lint-check typecheck security test
	@echo "All gate checks passed!"
