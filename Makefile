# The template-agentic version this repository applies to itself and bundles in template/: the one
# its answers record, or AGENTIC_SRC at AGENTIC_REF, to test an unreleased change from a local clone.
answer = $(shell sed -n "s/^$(1): '\{0,1\}\([^']*\)'\{0,1\}$$/\1/p" .copier-answers.agentic.yaml)
export AGENTIC_SRC ?= $(call answer,_src_path)
export AGENTIC_REF ?= $(call answer,_commit)

.PHONY: gate bundle
# The template's gate: copy it, then run every rendered suite.
gate:
	@bash tests/render-and-test.sh

# Writes that version's bundle into template/ and agentic/, which its update PR needs.
bundle:
	@clone="$$(mktemp -d)" && trap 'rm -rf "$$clone"' EXIT && \
	  git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$$AGENTIC_REF" "$$AGENTIC_SRC" "$$clone" && \
	  bash "$$clone/bundle.sh" .
