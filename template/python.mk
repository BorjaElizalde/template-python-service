# From the python-service template: change the template, not this copy.
# The gate, included by the project's Makefile: /gate and CI run make gate.
# The include is here, not in the project's Makefile, which an update never changes.
include .claude/agentic.mk

# The clone's commit hook, which its worktrees share, and its main checkout; empty outside git.
COMMIT_HOOK := $(shell git rev-parse --git-path hooks/pre-commit 2>/dev/null)
MAIN_CHECKOUT := $(shell git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')

.PHONY: lint lint-check typecheck security duplication test gate

# A Copier task would install the hooks on copy, but Copier then refuses each Renovate update:
# Mend's Renovate app never passes --trust. The hook runs the .venv of the checkout it was
# installed from, and a worktree's goes with it.
$(COMMIT_HOOK):
	uv run --directory '$(MAIN_CHECKOUT)' pre-commit install

claude: $(COMMIT_HOOK)

# The files git holds or would add, of the kinds ruff reads, and that are on disk. ruff and jscpd
# take them by name: in a folder it walks, each skips a file that a .gitignore or .ignore lists.
# --force-exclude keeps ruff's excludes, such as notebooks, for a named file.
PYTHON_FILES = $(wildcard $(shell git ls-files --cached --others --exclude-standard \
  -- '*.py' '*.pyi' '*.ipynb'))

lint: ## Fix what ruff can fix, and format every file.
	uv run ruff check --fix --force-exclude $(PYTHON_FILES)
	uv run ruff format --force-exclude $(PYTHON_FILES)

lint-check: ## Check ruff's rules and the format, and change no file.
	uv run ruff check --force-exclude $(PYTHON_FILES)
	uv run ruff format --check --force-exclude $(PYTHON_FILES)

typecheck: ## Check the types with basedpyright.
	uv run basedpyright

security: ## Scan for security issues with bandit.
	uv run bandit -r . -x ./.venv -ll -ii

# jscpd reads .jscpd.json. A failure prints the fix order that python-conventions.md gives.
duplication: ## Fail on a block of code written twice, with jscpd.
	@uv run jscpd $(PYTHON_FILES) || { echo "For each copy jscpd lists: delete the copy that should not exist" \
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

gate: lint-check typecheck security duplication test ## Run every local check.
	@echo "All gate checks passed!"
