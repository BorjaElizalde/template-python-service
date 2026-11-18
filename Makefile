# The template-agentic version this repository applies to itself and a release bundles: the one its
# answers record, or AGENTIC_SRC at AGENTIC_REF, to test an unreleased change from a local clone.
answer = $(shell sed -n "s/^$(1): '\{0,1\}\([^']*\)'\{0,1\}$$/\1/p" .copier-answers.agentic.yaml)
export AGENTIC_SRC ?= $(call answer,_src_path)
export AGENTIC_REF ?= $(call answer,_commit)

include .claude/agentic.mk

.PHONY: gate release-tag
gate: ## Copy the template the way a project gets it, then run every rendered suite.
	@bash tests/render-and-test.sh

# The release is this tree plus the bundled version's files, a commit no branch holds. Its second
# parent is origin's newest tag, so a compare of two releases shows only what changed.
release-tag: ## Tag TAG as a release that bundles template-agentic; Build runs it.
	@previous="$$(git ls-remote --tags --refs --sort=-v:refname origin | sed -n '1s#.*refs/tags/##p')" && \
	  git fetch --quiet --depth 1 origin tag "$$previous" && \
	  clone="$$(mktemp -d)" && trap 'rm -rf "$$clone"' EXIT && \
	  git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$$AGENTIC_REF" "$$AGENTIC_SRC" "$$clone" && \
	  bash "$$clone/bundle.sh" . && git add --force -- agentic template && \
	  git tag "$(TAG)" "$$(git commit-tree "$$(git write-tree)" -p HEAD -p "$$previous" \
	    -m "Release $(TAG), with template-agentic $$AGENTIC_REF")"
