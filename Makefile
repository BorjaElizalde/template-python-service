# The template's gate: render it on top of template-agentic, then run every rendered suite.
.PHONY: gate
gate:
	@bash tests/render-and-test.sh
