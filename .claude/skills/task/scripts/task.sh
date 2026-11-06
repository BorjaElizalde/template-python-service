#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
# The task lifecycle behind /task:start and /task:finish: one issue, one worktree, one session.
set -euo pipefail

usage="usage: task.sh start <issue> [type] | finish <issue> | point-memory"

CALLER=$(pwd -P)
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
CHECKOUT=$(pwd -P)
# Worktree paths resolve from the main checkout, the first entry git lists, even when this runs in
# a worktree. Its folder name names this repository's worktree inside each issue's folder, so a
# cross-repository task's worktrees sit side by side.
MAIN=$(git worktree list --porcelain | sed -n '1s/^worktree //p')
REPO_NAME=$(basename "$MAIN")
cd "$MAIN"
. .claude/agentic.conf

die() {
	echo "$*" >&2
	exit 1
}

# "<STATE> <title>" of an issue in the issues repository.
issue_view() {
	gh issue view "$1" -R "$ISSUES_REPO" --json state,title -q '.state + " " + .title'
}

# A title cut at a word boundary to 40 characters.
short_title() {
	awk 'length > 40 { $0 = substr($0, 1, 41); sub(/ [^ ]*$/, "") } 1' <<<"$1"
}

issue_worktree() {
	git worktree list --porcelain | awk -v issue="$1" '
		/^worktree / { worktree = substr($0, 10) }
		!found && $0 ~ "^branch refs/heads/[^/]+/" issue "-" { print worktree; found = 1 }
		END { exit !found }'
}

# The <type>/<issue>-<slug> branch an earlier start made: a local one first, else one only on origin.
issue_branch() {
	git for-each-ref --format='%(refname:lstrip=-2)' "refs/heads/*/$1-*" "refs/remotes/origin/*/$1-*" |
		awk 'NR == 1 { print } END { exit NR == 0 }'
}

has_session_transcript() {
	ls "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects/$(printf '%s' "$1" | tr -c 'a-zA-Z0-9' '-')"/*.jsonl >/dev/null 2>&1
}

# The tty of a claude process whose working directory is $1.
session_tty() {
	local pid tty
	while read -r pid tty; do
		if [ "$(lsof -a -p "$pid" -d cwd -Fn | sed -n 's/^n//p')" = "$1" ]; then
			echo "/dev/$tty"
			return
		fi
	done < <(ps -axo pid=,tty=,comm= | awk '$2 != "??" && $3 ~ /(^|\/)claude$/ { print $1, $2 }')
	return 1
}

# autoMemoryDirectory takes only an absolute or ~/ path, so each checkout's gitignored local
# settings point Claude at that checkout's own committed store.
point_memory() {
	local checkout=$1 settings=$1/.claude/settings.local.json
	[ -f "$settings" ] || printf '{}\n' >"$settings"
	jq --arg dir "$checkout/.claude/memory" '.autoMemoryDirectory = $dir' "$settings" >"$settings.tmp"
	mv "$settings.tmp" "$settings"
}

# open_session <worktree> <name> [--continue]
open_session() {
	# exec: claude replaces the window's shell, so Terminal can close the window when claude exits.
	osascript - "$1" "$2" "${3:-}" \
		"$MAIN/.claude/subagent-session-settings.json" "$MAIN/.claude/subagent-session-prompt.md" >/dev/null <<'APPLESCRIPT'
on run {worktree, sessionName, resumeFlag, settingsFile, promptFile}
	tell application "Terminal"
		do script "cd " & quoted form of worktree & " && exec claude " & resumeFlag & " --settings " & quoted form of settingsFile & " --append-system-prompt-file " & quoted form of promptFile & " --disallowed-tools AskUserQuestion -n " & quoted form of sessionName
		activate
	end tell
end run
APPLESCRIPT
}

# session_tab <tty> exit|focus: ends the session in that Terminal tab, or brings the tab to the front.
session_tab() {
	osascript - "$1" "$2" >/dev/null <<'APPLESCRIPT'
on run {sessionTty, action}
	tell application "Terminal"
		-- claude sets the window title itself, so the tab is found by its tty.
		repeat with w in windows
			set windowTabs to {}
			-- Terminal can list a window whose tabs can't be read.
			try
				set windowTabs to tabs of w
			end try
			repeat with t in windowTabs
				if tty of t is sessionTty then
					if action is "exit" then
						-- do script ends the text with the carriage return that Enter sends.
						do script "/exit" in t
					else
						set selected of t to true
						set index of w to 1
						activate
					end if
					return
				end if
			end repeat
		end repeat
	end tell
	error "no Terminal tab on " & sessionTty
end run
APPLESCRIPT
}

# Whether the session in worktree $1 exits within 30 seconds.
session_exits() {
	local _
	for _ in $(seq 30); do
		session_tty "$1" >/dev/null || return 0
		sleep 1
	done
	return 1
}

# Whether branch $1 holds commits that exist nowhere else. They are safe when there are none beyond
# develop, when its remote branch has them all, or when a PR from it merged: a squash merge leaves
# the branch's own commits off develop.
unshipped() {
	[ "$(git rev-list --count "origin/develop..$1")" -eq 0 ] && return 1
	git rev-parse -q --verify "refs/remotes/origin/$1" >/dev/null &&
		[ "$(git rev-list --count "origin/$1..$1")" -eq 0 ] && return 1
	[ -n "$(gh pr list --head "$1" --state merged --json number -q '.[0].number')" ] && return 1
	return 0
}

# Picks up whatever the issue already has: its worktree, else its branch, and its session.
start_task() {
	local issue=$1 type=$2 view title short slug worktree branch name tty
	view=$(issue_view "$issue") || die "no issue $issue in $ISSUES_REPO"
	title=${view#* }
	[ "${view%% *}" = OPEN ] || die "issue $issue is ${view%% *}: a task starts from an open issue"
	short=$(short_title "$title")
	# A worktree whose folder was deleted by hand still holds its branch until git forgets it.
	git worktree prune
	if worktree=$(issue_worktree "$issue"); then
		echo "✓ worktree exists: $worktree"
	else
		git fetch origin -q
		if branch=$(issue_branch "$issue"); then
			worktree=$WORKTREE_ROOT/${branch#*/}/$REPO_NAME
			mkdir -p "$(dirname "$worktree")"
			# A branch only on origin comes back as a local branch tracking it.
			git worktree add -q "$worktree" "$branch"
		else
			slug=$(tr '[:upper:]' '[:lower:]' <<<"$short" | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//')
			branch=$type/$issue-$slug
			worktree=$WORKTREE_ROOT/$issue-$slug/$REPO_NAME
			mkdir -p "$(dirname "$worktree")"
			git worktree add -q -b "$branch" "$worktree" origin/develop
		fi
		worktree=$(cd "$worktree" && pwd -P)
		# Seed the gitignored files git worktree add can't carry, never overwriting one.
		cp -n .env* "$worktree"/ 2>/dev/null || true
		cp -n .claude/settings.local.json "$worktree/.claude/settings.local.json" 2>/dev/null || true
		echo "✓ worktree created: $worktree (branch $branch)"
	fi
	point_memory "$MAIN"
	point_memory "$worktree"
	name="#$issue $REPO_NAME: $short"
	if tty=$(session_tty "$worktree"); then
		session_tab "$tty" focus
		echo "✓ session already running, brought to the front: $name"
	elif has_session_transcript "$worktree"; then
		# claude --continue refuses to start where no session exists yet.
		open_session "$worktree" "$name" --continue
		echo "✓ session resumed: $name"
	else
		open_session "$worktree" "$name"
		echo "✓ session opened: $name"
	fi
}

finish_task() {
	local issue=$1 view worktree branch tty
	worktree=$(issue_worktree "$issue") || die "no worktree for issue $issue"
	case "$CALLER/" in "$worktree"/*)
		die "finish issue $issue from outside its worktree: from inside, it would close its own session and delete its own folder" ;;
	esac
	[ "$CHECKOUT" != "$worktree" ] || die "finish issue $issue with the main checkout's task.sh, not the copy in its worktree"
	view=$(issue_view "$issue") || die "no issue $issue in $ISSUES_REPO"
	[ "${view%% *}" = CLOSED ] || die "issue $issue is still open: deliver its result through the PR or the issue, then close it"
	branch=$(git -C "$worktree" branch --show-current)
	git fetch origin -q
	if unshipped "$branch"; then
		die "branch $branch has commits on no remote branch and in no merged PR: push them first"
	fi
	if tty=$(session_tty "$worktree"); then
		session_tab "$tty" exit
		session_exits "$worktree" || die "the session in $worktree did not exit; close it, then finish again"
	fi
	git worktree remove "$worktree" ||
		die "$worktree has uncommitted or untracked files: commit them, or move what matters to the PR or the issue"
	git branch -D -q "$branch"
	rmdir "$(dirname "$worktree")" 2>/dev/null || true
	echo "✓ issue $issue finished: session closed, worktree and branch $branch removed"
}

case ${1:-} in
start) [ $# -ge 2 ] || die "$usage"; start_task "$2" "${3:-feat}" ;;
finish) [ $# -ge 2 ] || die "$usage"; finish_task "$2" ;;
point-memory) point_memory "$CHECKOUT" && echo "✓ auto memory points at $CHECKOUT/.claude/memory" ;;
*) die "$usage" ;;
esac
