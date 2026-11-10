#!/usr/bin/env bash
# From the python-service template: change the template, not this copy.
# The agentic layer's after-edit hook point: format a Python file or stub after Claude edits it. A
# file left unformatted fails `ruff format --check` when `make gate` runs mid-turn.

set -u
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Project root holds pyproject.toml; it is three levels up from .claude/hooks/stack/.
PROJECT_DIR="$(cd "${HOOK_DIR}/../../.." && pwd)"

FILE_PATH=$(jq -r '.tool_input.file_path // ""' 2>/dev/null || true)
[ -n "$FILE_PATH" ] && [ -f "$FILE_PATH" ] || exit 0
# Only the files the gate formats: ruff formats any path it is given, even a file that is not
# Python, or a notebook, which ruff.base.toml keeps out of the gate.
case "$FILE_PATH" in *.py|*.pyi) ;; *) exit 0 ;; esac
# A path-prefix test would miss linked worktrees, where all feature work happens.
# Formatting is never worth blocking an edit; always exit 0.
REPO="$(git -C "$PROJECT_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
FILE_REPO="$(git -C "$(dirname "$FILE_PATH")" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
[ -n "$REPO" ] && [ "$FILE_REPO" = "$REPO" ] || exit 0

( cd "${PROJECT_DIR}" && uv run ruff format "$FILE_PATH" >/dev/null 2>&1 ) || true
exit 0
