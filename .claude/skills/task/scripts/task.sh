#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
# The task lifecycle behind /task:start and /task:finish: one issue, one worktree, one session. And
# the parking of an issue that must not start yet.
set -euo pipefail

usage="usage: task.sh start <issue> [type] | finish <issue> | park <issue> <reason> | cleanup | status | on-session-start | point-memory"

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

# The jq definitions every view of an issue's holds shares, so each rule lives in one place. Over an
# issue as gh gives it in JSON, blockers gives the open issues it is blocked by, and parked the
# reason it is parked for, from the last comment that starts with "Parked:"; each gives nothing
# where there is none.
ISSUE_JQ='
	def blockers: [.blockedBy.nodes[] | select(.state == "OPEN") | "#\(.number)"] | select(. != []) | join(", ");
	def parked: select(any(.labels[]; .name == "backlog"))
		| [.comments[].body | select(startswith("Parked:")) | sub("^Parked: *"; "")] | last // "no reason given";
'

# Why issue $1 must not start yet, one line per reason, else nothing.
issue_holds() {
	gh issue view "$1" -R "$ISSUES_REPO" --json number,labels,blockedBy,comments |
		jq -r "$ISSUE_JQ"'"issue \(.number) is " + ("blocked by " + blockers, "parked: " + parked)'
}

# Parks issue $1 for reason $2: a comment that gives the reason, then the backlog label, so the label
# never stands without its reason. The label is created on its first use in the issues repository;
# --force updates one that exists.
park() {
	gh label create backlog -R "$ISSUES_REPO" --force --color ededed \
		--description "Parked: no agent starts it until the owner releases it" >/dev/null
	gh issue comment "$1" -R "$ISSUES_REPO" --body "Parked: $2" >/dev/null
	gh issue edit "$1" -R "$ISSUES_REPO" --add-label backlog >/dev/null
	echo "✓ issue $1 parked: $2"
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

# The mode of the task on branch $1, from its type: design, whose session works the task out with
# the owner, else execution, whose session works alone. Nothing else stores the mode, so a task
# keeps it for life.
task_mode() {
	case $1 in
	design/*) echo design ;;
	*) echo execution ;;
	esac
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

# A word quoted for a shell.
quoted() {
	local quote="'" escaped="'\\''"
	printf "'%s'" "${1//$quote/$escaped}"
}

# open_session <worktree> <name> <issue> <mode> [--continue]: returns once the session runs.
open_session() {
	# A session opened without a first prompt waits at an empty input, so this one sends it to its
	# issue. One prompt serves a new session and a resumed one.
	local first="Work on issue #$3 in $ISSUES_REPO. Read its title, body and comments: gh issue view $3 -R $ISSUES_REPO --json title,body,comments. Carry it out until it is done as the issue says; if this session already worked on it, go on from where it stopped."
	local files=$MAIN/.claude/skills/task/session settings tools=" --disallowed-tools AskUserQuestion" command launcher
	settings=$files/settings.json
	# Every session has its permission prompts denied. An execution session never waits for a
	# person: it has no question tool, and its Stop hook sends it back to work when it ends its turn
	# on a question. A design session asks the owner, so it keeps the tool and drops the hook:
	# claude --settings takes one file or JSON string, so it gets the settings less the hook as JSON.
	if [ "$4" = design ]; then
		settings=$(jq -c 'del(.hooks.Stop)' "$settings")
		tools=
	fi
	# claude takes one appended system prompt, so the launcher joins the words both modes share and
	# the mode's own. The first prompt comes after -n: --disallowed-tools takes every value up to the
	# next option.
	command="cd $(quoted "$1") && exec claude ${5:+$5 }--settings $(quoted "$settings")"
	command+=" --append-system-prompt \"\$(cat $(quoted "$files/prompt.md") $(quoted "$files/$4.md"))\""
	command+="$tools -n $(quoted "$2") $(quoted "$first")"
	# The tty drops a typed line past 1024 bytes (MAX_CANON), so Terminal types only the line that
	# runs a launcher. The launcher sits in the worktree's git dir, out of the work tree that a
	# finish needs clean. exec leaves claude the tab's only process, so the tab is empty once it exits.
	launcher=$(git -C "$1" rev-parse --absolute-git-dir)/task-session.sh
	printf '%s\n' "$command" >"$launcher"
	osascript - "exec bash $(quoted "$launcher")" >/dev/null <<'APPLESCRIPT'
on run {command}
	tell application "Terminal"
		do script command
		activate
	end tell
end run
APPLESCRIPT
	# The tab's shell, then claude, take seconds to start.
	for _ in {1..30}; do
		SESSIONS=$(claude agents --json)
		session "$1" >/dev/null && return
		sleep 1
	done
	die "no session runs in $1 30 seconds after its launch: its Terminal tab shows why"
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

# Picks up whatever the issue already has: its worktree, else its branch, and its session, in the
# mode of its branch. A mistyped type would fix the wrong mode for the task's life, so an unknown one
# is refused before anything else.
start_task() {
	local issue=$1 type=$2 view title holds short slug worktree branch mode name tty
	case $type in
	feat | fix | refactor | chore | research | design) ;;
	*) die "unknown type $type: a task is feat, fix, refactor, chore or research, in execution mode, or design, in design mode" ;;
	esac
	view=$(issue_view "$issue") || die "no issue $issue in $ISSUES_REPO"
	title=${view#* }
	[ "${view%% *}" = OPEN ] || die "issue $issue is ${view%% *}: a task starts from an open issue"
	holds=$(issue_holds "$issue")
	[ -z "$holds" ] || die "$holds"
	short=$(short_title "$title")
	cleanup
	SESSIONS=$(claude agents --json)
	task_lines "$issue"
	if worktree=$(issue_worktree "$issue"); then
		branch=$(git -C "$worktree" branch --show-current)
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
	mode=$(task_mode "$branch")
	name="#$issue $REPO_NAME: $short"
	if tty=$(session_tty "$worktree"); then
		session_tab "$tty" focus
		echo "✓ session already running in $mode mode, brought to the front: $name"
	elif has_session_transcript "$worktree"; then
		# claude --continue refuses to start where no session exists yet.
		open_session "$worktree" "$name" "$issue" "$mode" --continue
		echo "✓ session resumed in $mode mode: $name"
	else
		open_session "$worktree" "$name" "$issue" "$mode"
		echo "✓ session opened in $mode mode: $name"
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
# its issue, but nothing finishes its task. One line per task it finished or refused to finish;
# open issues are skipped without a word.
cleanup() {
	local issue view out
	# A worktree whose folder was deleted by hand still holds its branch until git forgets it.
	git worktree prune
	for issue in $(task_issues); do
		view=$(issue_view "$issue") || continue
		[ "${view%% *}" = CLOSED ] || continue
		# A refusal exits, so each finish runs as a task.sh of its own, whose last line says what it
		# did or why it refused, and the cleanup goes on. From the caller's folder, $0 resolves and
		# finish sees a cleanup from inside the worktree it would remove.
		if out=$(cd "$CALLER" && bash "$0" finish "$issue" 2>&1); then
			tail -n 1 <<<"$out"
		else
			echo "✗ issue $issue not finished: $(tail -n 1 <<<"$out")"
		fi
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

# Every open issue, under the first heading that fits: In progress, one task line per task worktree
# of this checkout, then the backlog. It only reads, and where there is no task it calls no claude.
status() {
	if [ -n "$(task_issues)" ]; then
		echo "In progress:"
		SESSIONS=$(claude agents --json)
		task_lines
	fi
	backlog_lines
}

# The open issues with no task worktree of this checkout, under Ready, Blocked and Parked, one line
# each, lowest number first; a heading with no issue is left out. Each issue goes under the first
# that fits: Parked, then Blocked, then Ready, so a parked line also names its open blockers. A line
# keeps the whole title, so the reply can say what the issue is: the backlog never goes through the
# hook, whose bound the task lines' cut is for. gh lists 30 issues unless told more.
backlog_lines() {
	gh issue list -R "$ISSUES_REPO" --state open --limit 1000 --json number,title,labels,blockedBy,comments |
		jq -r --argjson tasks "[$(task_issues | paste -sd , -)]" "$ISSUE_JQ"'
		[sort_by(.number)[] | select(.number | IN($tasks[]) | not)
			| [parked] as $parked | ($parked + ["blocked by " + blockers]) as $holds
			| {heading: (if $parked != [] then "Parked" elif $holds != [] then "Blocked" else "Ready" end),
				line: (["#\(.number) \(.title)", ($holds | select(. != []) | join("; "))] | join(": "))}]
		| ("Ready", "Blocked", "Parked") as $heading | map(select(.heading == $heading) | .line)
		| select(. != []) | "\($heading):", .[]'
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

# task_lines [<issue>]: one line per task worktree of this checkout, with "design mode" for a design
# task, its session, its PR and when its session last wrote, ending in "needs attention" when it
# does; the issue given is left out.
task_lines() {
	local issue worktree session age view branch pr mode mark
	for issue in $(task_issues); do
		[ "$issue" != "${1:-}" ] || continue
		worktree=$(issue_worktree "$issue")
		session=$(session_line "$worktree")
		age=$(transcript_age "$worktree")
		view=$(issue_view "$issue")
		branch=$(git -C "$worktree" branch --show-current)
		pr=$(pr_line "$branch")
		mode=
		if [ "$(task_mode "$branch")" = design ]; then mode="design mode, "; fi
		mark=
		if needs_attention "$session" "$age"; then mark=", needs attention"; fi
		echo "#$issue $(short_title "${view#* }"): $mode$session, $pr, $(active_line "$age")$mark"
	done
}

# The SessionStart hook: a cleanup, then the task lines, in the context of a session that starts or
# resumes in the main checkout, ending with the line that sends it to /task:status for the reply.
# A hook can't call a skill, only add to the context. It says nothing in a task worktree, so task
# sessions start untouched, nor where there is no task, and it never fails a session start.
# Claude Code passes on 10,000 characters of a hook's output, and only a preview of the first 2,000
# when there are more. A line is at most about 250, so 40 tasks fit; the backlog has no such bound,
# so it is left to /task:status.
on_session_start() {
	[ "$(git -C "$CHECKOUT" rev-parse --absolute-git-dir)" = \
		"$(git -C "$CHECKOUT" rev-parse --path-format=absolute --git-common-dir)" ] || return 0
	[ -n "$(task_issues)" ] || return 0
	trap '[ $? -eq 0 ] || { echo "The tasks are unknown: gh or claude agents did not answer. Report the status through /task:status once they do."; exit 0; }' EXIT
	cleanup
	SESSIONS=$(claude agents --json)
	task_lines
	echo "In your first reply, report the status to the owner through /task:status."
}

case ${1:-} in
start) [ $# -ge 2 ] || die "$usage"; start_task "$2" "${3:-feat}" ;;
finish) [ $# -ge 2 ] || die "$usage"; finish_task "$2" ;;
park) [ $# -ge 3 ] || die "$usage"; park "$2" "$3" ;;
cleanup) cleanup ;;
status) status ;;
on-session-start) on_session_start ;;
point-memory) point_memory "$CHECKOUT" && echo "✓ auto memory points at $CHECKOUT/.claude/memory" ;;
*) die "$usage" ;;
esac
