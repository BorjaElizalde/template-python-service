# The template-agentic version this repository applies to itself and a release bundles: the one its
# answers record, or AGENTIC_SRC at AGENTIC_REF, to test an unreleased change from a local clone.
answer = $(shell sed -n "s/^$(1): '\{0,1\}\([^']*\)'\{0,1\}$$/\1/p" .copier-answers.agentic.yaml)
export AGENTIC_SRC ?= $(call answer,_src_path)
export AGENTIC_REF ?= $(call answer,_commit)

.PHONY: gate release-tag
# The template's gate: copy it, then run every rendered suite.
gate:
	@bash tests/render-and-test.sh

# Tags TAG on this tree plus that version's files, a commit no branch holds. Its second parent is
# origin's newest tag, so a compare of two releases shows only what changed. Build runs it.
release-tag:
	@previous="$$(git ls-remote --tags --refs --sort=-v:refname origin | sed -n '1s#.*refs/tags/##p')" && \
	  git fetch --quiet --depth 1 origin tag "$$previous" && \
	  clone="$$(mktemp -d)" && trap 'rm -rf "$$clone"' EXIT && \
	  git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$$AGENTIC_REF" "$$AGENTIC_SRC" "$$clone" && \
	  bash "$$clone/bundle.sh" . && git add --force -- agentic template && \
	  git tag "$(TAG)" "$$(git commit-tree "$$(git write-tree)" -p HEAD -p "$$previous" \
	    -m "Release $(TAG), with template-agentic $$AGENTIC_REF")"
