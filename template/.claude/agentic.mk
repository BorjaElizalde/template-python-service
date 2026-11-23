# From the agentic template: change the template, not this copy.
# The project's Makefile, or the stack template's fragment it includes, includes this file. A
# project extends it with its own targets, prerequisites and variables set after the include,
# never with a second recipe for a target here.
.DEFAULT_GOAL := help

# Claude Code keeps a Mac awake only while a session is busy, and never against system sleep.
KEEP_AWAKE ?= $(if $(shell command -v caffeinate 2>/dev/null),caffeinate -is)
CLAUDE_FLAGS ?= --remote-control
# The socket of this repository's own tmux server, which task.sh opens the task windows in.
TMUX_SOCKET := $(notdir $(CURDIR))
# tmux reads a dot in a session name as a target's separator, and -A looks the name up as a target.
TMUX_SESSION := $(subst .,_,$(TMUX_SOCKET))
# The main session's command. The shell reads prompt, which make exports; -- stops a flag like
# --remote-control [name] taking it.
MAIN_SESSION = $(KEEP_AWAKE) claude $(CLAUDE_FLAGS) $(args) $${prompt:+-- "$$prompt"}
comma := ,
# Inside tmux, TMUX holds "<socket path>,<pid>,<session>".
TMUX_SOCKET_IN := $(firstword $(subst $(comma), ,$(TMUX)))

.PHONY: help claude
help: ## List every target, under the file that defines it.
	@awk -F ':.*## ' '/^[a-zA-Z0-9_-]+:.*## / { if (FILENAME != f) { f = FILENAME; printf "\n%s\n", f } printf "  %-14s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

# The repository's tmux server starts from this shell, so claude in its first window has this
# shell's environment; a closed terminal window only detaches tmux, so it stops neither claude nor
# the keep-awake that wraps it. tmux refuses a client nested into its own server, so inside the
# repository's tmux claude runs in place.
claude: ## Start Claude in this repository's tmux, or attach to it, kept awake until Claude exits; inside that tmux, start it in place: args="--continue" prompt="/loop ..."
	@$(if $(filter %/$(TMUX_SOCKET),$(TMUX_SOCKET_IN)),$(MAIN_SESSION),tmux -L '$(TMUX_SOCKET)' source-file .claude/tmux.conf \; new-session -A -s '$(TMUX_SESSION)' -n main $(MAIN_SESSION))
