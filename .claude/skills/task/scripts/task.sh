#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
# The task lifecycle behind /task:start and /task:finish: one issue, one worktree, one session.
set -euo pipefail

usage="usage: task.sh start <issue> [type] | finish <issue> | sweep | status | attention | point-memory"

CALLER=$(pwd -P)
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
CHECKOUT=$(pwd -P)
# Worktree paths resolve from the main checkout, the first entry git lists, even when this runs in
# a worktree. Its folder name names this repository's worktree inside each issue's folder, so a
# cross-repository task's worktrees sit side by side.
MAIN=$(git worktree list --porcelain | sed -n '1s/^worktree //p')
REPO_NAME=$(basename "$MAIN")
cd "$MAIN"
# The render's answers: KEY=VALUE lines, with no code in them to check. Tried pointing shellcheck
# at the file with source= and -x, but it would then check data, not code.
# shellcheck disable=SC1091
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

# The folder Claude Code writes the transcripts of the sessions in folder $1 to.
transcript_dir() {
	printf '%s/projects/%s' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" "$(printf '%s' "$1" | tr -c 'a-zA-Z0-9' '-')"
}

has_session_transcript() {
	ls "$(transcript_dir "$1")"/*.jsonl >/dev/null 2>&1
}

# The interactive session running in folder $1, found in $SESSIONS: the output of
# `claude agents --json`, the supported way to read session state from outside Claude Code.
session() {
	jq -ce --arg cwd "$1" 'first(.[] | select(.kind == "interactive" and .cwd == $cwd))' <<<"$SESSIONS"
}

# The tty of the session running in folder $1.
session_tty() {
	local pid
	pid=$(session "$1" | jq .pid) || return 1
	echo "/dev/$(ps -o tty= -p "$pid" | tr -d ' ')"
}

# "session busy|idle|waiting" of the session running in folder $1, else "no session".
session_line() {
	session "$1" | jq -r '"session " + .status' || echo "no session"
}

# autoMemoryDirectory takes only an absolute or ~/ path, so each checkout's gitignored local
# settings point Claude at that checkout's own committed store.
point_memory() {
	local checkout=$1 settings=$1/.claude/settings.local.json
	[ -f "$settings" ] || printf '{}\n' >"$settings"
	jq --arg dir "$checkout/.claude/memory" '.autoMemoryDirectory = $dir' "$settings" >"$settings.tmp"
	mv "$settings.tmp" "$settings"
}

# open_session <worktree> <name> <issue> [--continue]
open_session() {
	# A session opened without a first prompt waits at an empty input, so this one sends it to its
	# issue. One prompt serves a new session and a resumed one.
	local first="Work on issue #$3 in $ISSUES_REPO. Read it with its comments: gh issue view $3 -R $ISSUES_REPO --comments. Carry it out until it is done as the issue says; if this session already worked on it, go on from where it stopped."
	# exec leaves claude the tab's only process, so the tab is empty once claude exits. The first
	# prompt comes after -n: --disallowed-tools takes every value up to the next option.
	osascript - "$1" "$2" "${4:-}" \
		"$MAIN/.claude/skills/task/session/settings.json" "$MAIN/.claude/skills/task/session/prompt.md" "$first" >/dev/null <<'APPLESCRIPT'
on run {worktree, sessionName, resumeFlag, settingsFile, promptFile, firstPrompt}
	tell application "Terminal"
		do script "cd " & quoted form of worktree & " && exec claude " & resumeFlag & " --settings " & quoted form of settingsFile & " --append-system-prompt-file " & quoted form of promptFile & " --disallowed-tools AskUserQuestion -n " & quoted form of sessionName & " " & quoted form of firstPrompt
		activate
	end tell
end run
APPLESCRIPT
}

# session_tab <tty> exit|focus: ends the session in that Terminal tab and closes its window, or brings
# the tab to the front.
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
						-- By id: w is the window's place in the front-to-back order, which can change.
						set sessionWindow to contents of w
						-- A profile that closes the window when its shell exits can close it between
						-- any two of these lines.
						repeat 30 times
							try
								if (count (processes of t)) is 0 then close sessionWindow
							end try
							if not (exists sessionWindow) then return
							delay 1
						end repeat
						error "the tab on " & sessionTty & " still runs a process after 30 seconds"
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
	sweep
	SESSIONS=$(claude agents --json)
	task_lines attention "$issue"
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
		open_session "$worktree" "$name" "$issue" --continue
		echo "✓ session resumed: $name"
	else
		open_session "$worktree" "$name" "$issue"
		echo "✓ session opened: $name"
	fi
}

finish_task() {
	local issue=$1 view worktree branches branch tty
	worktree=$(issue_worktree "$issue") || die "no worktree for issue $issue"
	case "$CALLER/" in "$worktree"/*)
		die "finish issue $issue from outside its worktree: from inside, it would close its own session and delete its own folder" ;;
	esac
	[ "$CHECKOUT" != "$worktree" ] || die "finish issue $issue with the main checkout's task.sh, not the copy in its worktree"
	view=$(issue_view "$issue") || die "no issue $issue in $ISSUES_REPO"
	[ "${view%% *}" = CLOSED ] || die "issue $issue is still open: deliver its result through the PR or the issue, then close it"
	# Every local branch of the issue, the worktree's among them: a task can open a second branch for
	# a follow-up PR. A branch name holds no space or glob character, so the list splits unquoted.
	branches=$(git for-each-ref --format='%(refname:lstrip=2)' "refs/heads/*/$issue-*")
	git fetch origin -q
	for branch in $branches; do
		if unshipped "$branch"; then
			die "branch $branch has commits on no remote branch and in no merged PR: push them first"
		fi
	done
	SESSIONS=$(claude agents --json)
	if tty=$(session_tty "$worktree"); then
		session_tab "$tty" exit || die "the session in $worktree did not exit; close it, then finish again"
	fi
	git worktree remove "$worktree" ||
		die "$worktree has uncommitted or untracked files: commit them, or move what matters to the PR or the issue"
	# The list splits unquoted, as its comment says. Tried an array, but bash 3.2, the macOS bash
	# that runs this, has no mapfile to fill one, and read -a needs IFS and -d set for a list.
	# shellcheck disable=SC2086
	git branch -D -q $branches
	rmdir "$(dirname "$worktree")" 2>/dev/null || true
	echo "✓ issue $issue finished: session closed, worktree removed, branches removed: ${branches//$'\n'/ }"
}

# The issue of each task worktree of this checkout.
task_issues() {
	git worktree list --porcelain | sed -En 's|^branch refs/heads/[^/]+/([0-9]+)-.*|\1|p'
}

# Finishes every task worktree of this checkout whose issue is closed: a PR merged on GitHub closes
# its issue, but nothing finishes its task. Open issues are skipped without a word.
sweep() {
	local issue view
	# A worktree whose folder was deleted by hand still holds its branch until git forgets it.
	git worktree prune
	for issue in $(task_issues); do
		view=$(issue_view "$issue") || continue
		[ "${view%% *}" = CLOSED ] || continue
		# A refusal exits, so each finish runs as a task.sh of its own: a refusal is reported and the
		# sweep goes on. From the caller's folder, $0 resolves and finish sees a sweep from inside
		# the worktree it would remove.
		(cd "$CALLER" && bash "$0" finish "$issue") || true
	done
}

# "PR #<n> <state>, checks <result>" of the newest PR from branch $1, else "no PR". A check has
# passed once it succeeded, or was neutral or skipped, as the merge guard reads it; a failure
# outweighs a pending check.
pr_line() {
	gh pr list --head "$1" --state all --json number,state,isDraft,statusCheckRollup | jq -r '
		if length == 0 then "no PR" else .[0]
		| [.statusCheckRollup[]? | if .__typename == "StatusContext" then .state
			elif .status == "COMPLETED" then .conclusion else "PENDING" end] as $c
		| "PR #\(.number) \(if .isDraft then "draft" else .state | ascii_downcase end), "
			+ if $c == [] then "no checks"
			elif any($c[]; IN("SUCCESS", "NEUTRAL", "SKIPPED", "PENDING", "EXPECTED") | not) then "checks failed"
			elif any($c[]; IN("PENDING", "EXPECTED")) then "checks pending"
			else "checks passed" end
		end'
}

# The seconds since a session in folder $1 last wrote its transcript; nothing when none did.
transcript_age() {
	local transcript newest=
	# Any file is newer than no file. In a folder with no transcript, the pattern stays as it is and
	# names no file.
	for transcript in "$(transcript_dir "$1")"/*.jsonl; do
		if [ "$transcript" -nt "$newest" ]; then newest=$transcript; fi
	done
	[ -n "$newest" ] || return 0
	echo $(($(date +%s) - $(date -r "$newest" +%s)))
}

# "active <age> ago" from a transcript_age, else "no transcript".
active_line() {
	local age=$1
	if [ -z "$age" ]; then
		echo "no transcript"
	elif [ "$age" -lt 3600 ]; then
		echo "active $((age / 60)) min ago"
	elif [ "$age" -lt 86400 ]; then
		echo "active $((age / 3600)) h ago"
	else
		echo "active $((age / 86400)) d ago"
	fi
}

# Sweeps first, so a look also finishes what is done. Then one line per task worktree of this
# checkout, and nothing else: the backlog is gh issue list's.
status() {
	sweep
	SESSIONS=$(claude agents --json)
	task_lines all
}

# A session idle or gone for less than this many minutes since it last wrote is left alone: one
# that ends its turn on a background check is woken when the check finishes.
QUIET_MINUTES=10

# needs_attention <session_line> <transcript_age>: a session waiting for an answer, or idle or
# gone for QUIET_MINUTES. A busy one is working.
needs_attention() {
	case $1 in
	"session busy") return 1 ;;
	"session waiting") return 0 ;;
	*) [ -z "$2" ] || [ "$2" -ge $((QUIET_MINUTES * 60)) ] ;;
	esac
}

# task_lines all|attention [<issue>]: one line per task worktree of this checkout, with its session,
# its PR and when its session last wrote; the issue given is left out. With attention, only the
# tasks that need it.
task_lines() {
	local issue worktree session age view pr
	for issue in $(task_issues); do
		[ "$issue" != "${2:-}" ] || continue
		worktree=$(issue_worktree "$issue")
		session=$(session_line "$worktree")
		age=$(transcript_age "$worktree")
		[ "$1" = all ] || needs_attention "$session" "$age" || continue
		view=$(issue_view "$issue")
		pr=$(pr_line "$(git -C "$worktree" branch --show-current)")
		echo "#$issue $(short_title "${view#* }"): $session, $pr, $(active_line "$age")"
	done
}

# The tasks that need attention, read only so it is fast: the SessionStart hook puts them in the
# context of a session in the main checkout, and a /loop can print them on each round. It says
# nothing in a task worktree, nor when no task needs attention, and it never fails a session start.
attention() {
	[ "$(git -C "$CHECKOUT" rev-parse --absolute-git-dir)" = \
		"$(git -C "$CHECKOUT" rev-parse --path-format=absolute --git-common-dir)" ] || return 0
	[ -n "$(task_issues)" ] || return 0
	trap '[ $? -eq 0 ] || { echo "task.sh attention failed, so the tasks are unknown: run it again once gh and claude agents answer."; exit 0; }' EXIT
	SESSIONS=$(claude agents --json)
	task_lines attention
}

case ${1:-} in
start) [ $# -ge 2 ] || die "$usage"; start_task "$2" "${3:-feat}" ;;
finish) [ $# -ge 2 ] || die "$usage"; finish_task "$2" ;;
sweep) sweep ;;
status) status ;;
attention) attention ;;
point-memory) point_memory "$CHECKOUT" && echo "✓ auto memory points at $CHECKOUT/.claude/memory" ;;
*) die "$usage" ;;
esac
