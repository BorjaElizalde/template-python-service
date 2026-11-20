# The template-agentic version this repository applies to itself and a release bundles: the one its
# answers record, or AGENTIC_SRC at AGENTIC_REF, to test an unreleased change from a local clone.
answer = $(shell sed -n "s/^$(1): '\{0,1\}\([^']*\)'\{0,1\}$$/\1/p" .copier-answers.agentic.yaml)
export AGENTIC_SRC ?= $(call answer,_src_path)
export AGENTIC_REF ?= $(call answer,_commit)

include .claude/agentic.mk

.PHONY: gate release-tag
gate: ## Copy the template the way a project gets it, then run every rendered suite.
	@bash tests/render-and-test.sh

release-tag: ## Push TAG, a release of this tree with template-agentic bundled in.
	@clone="$$(mktemp -d)" && trap 'rm -rf "$$clone"' EXIT && \
	  git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$$AGENTIC_REF" "$$AGENTIC_SRC" "$$clone" && \
	  bash "$$clone/release.sh" "$(TAG)"
