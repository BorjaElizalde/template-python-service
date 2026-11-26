# From the python-service template: change the template, not this copy.
# The local gate and the commit hooks, included by the project's Makefile: /gate runs make gate,
# and make claude installs the hooks. The project's CI runs its checks itself, never through make,
# so relaxing a target here can't relax CI.
# The include is here, not in the project's Makefile, which an update never changes.
include .claude/agentic.mk

# The clone's commit hook, which its worktrees share; empty outside git.
COMMIT_HOOK := $(shell git rev-parse --git-path hooks/pre-commit 2>/dev/null)

.PHONY: commit-hooks lint lint-check typecheck security duplication test gate

# A Copier task would install the hooks on copy, but Copier then refuses each Renovate update:
# Mend's Renovate app never passes --trust. So the hooks come with the first make claude.
claude: $(COMMIT_HOOK)

$(COMMIT_HOOK):
	uv run pre-commit install

commit-hooks: ## Fail when this clone has no commit hooks, which make claude installs.
	@[ -f "$(COMMIT_HOOK)" ] || { echo "This clone has no commit hooks: install them with" \
	  "uv run pre-commit install"; exit 1; }

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

# No tests/ skips pytest. An empty tests/ still fails it, with exit 5: a mistake, not a choice.
test: ## Run pytest with coverage, or skip it when there is no tests/ folder.
ifeq ($(wildcard tests),)
	@echo "pytest skipped: no tests/ folder"
else
	uv run pytest tests/ -v --cov
endif

gate: commit-hooks lint-check typecheck security duplication test ## Run every local check.
	@echo "All gate checks passed!"
