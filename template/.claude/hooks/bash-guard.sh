#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
# PreToolUse Bash guard — language-agnostic git/shell policy:
#   * block rm -rf  / | ~ | $HOME
#   * block git reset --hard onto origin|upstream main/staging/develop (protects local work)
#   * block switching to an EXISTING branch (allow `-c/-b` new branch + file restore)
#   * block direct push to a protected branch, forced or not
#   * block merging a PR in any form but the two the skills write, and into a protected branch
#     except the promotion hops develop→staging and staging→main as merge commits and, in a project
#     that answered agent_merges, its own PR into develop as a squash pinned to a head whose every
#     check has passed; block the API merge routes
#   * block committing in the primary working tree / main checkout (any branch) — worktree workflow
#   * block skipping the commit hooks: --no-verify, commit -n, SKIP=/HUSKY= env, core.hooksPath
#   * check the command that bash -c, sh -c or eval runs, as if it were sent on its own
# Protected branches: develop, staging, main. Nothing lands on them without the owner.
# PR creation (gh pr create) is unrestricted — PRs may target any base branch.
# Pure bash 3.2 regex via [[ =~ ]] — NO grep (grep can be a ugrep shim, which
# mis-parses flags like --force-with-lease). jq reads the command from the stdin payload; gh
# looks up the base branch of a PR being merged.
# Fails OPEN (exit 0) on an empty/unparseable command. A PR merge whose base cannot be looked up
# is blocked.
# Every function here runs: any_segment calls each segment_* check by the name it is given, and the
# checks call the rest. Tried one directive on each segment_* check, but their helpers stay flagged.
# shellcheck disable=SC2329
set -u

COMMAND="$(jq -r '.tool_input.command // empty' 2>/dev/null || true)"

# The project's agent_merges answer, from the agentic.conf beside .claude/hooks. Read line by line,
# never sourced, so the guard runs no code but its own.
HERE="$(cd "$(dirname "$0")" && pwd)"
AGENT_MERGES=false
if [ -f "$HERE/../agentic.conf" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in AGENT_MERGES=*) AGENT_MERGES="${line#AGENT_MERGES=}" ;; esac
  done <"$HERE/../agentic.conf"
fi

RE_PUSH='(^|[[:space:]&;|])git[[:space:]]+([^&|;]*[[:space:]])?push([[:space:]]|$)'
# git's -c <key=value> and -C <dir> before a subcommand. Push reads any words there, a shape that
# for switch, reset or commit would also match `git help checkout`.
RE_GIT_OPTS='(-[Cc][[:space:]]+[^[:space:]]+[[:space:]]+)*'
RE_SWITCH="(^|[[:space:]&;|])git[[:space:]]+$RE_GIT_OPTS(switch|checkout)([[:space:]]|$)"
RE_NEWBRANCH='(switch|checkout)[[:space:]]+(-[a-zA-Z]*[[:space:]]+)*(-c|-b|-C|-B)([[:space:]]|$)'
RE_FILEISH='checkout[[:space:]]+(--([[:space:]]|$)|\.([[:space:]]|$)|--[[:space:]])'
RE_PROT_TOKEN='(^|[[:space:]:=])(develop|staging|main)([[:space:]:]|$)'
RE_PROT_BRANCH='^(develop|staging|main)$'
RE_RMRF='(^|[[:space:]&;|])rm[[:space:]]+(-[a-zA-Z]*[rR][a-zA-Z]*[fF]|-[a-zA-Z]*[fF][a-zA-Z]*[rR])([[:space:]]+--)?[[:space:]]+"?(/|~|[$]HOME|[$][{]HOME[}])"?/?[*]?"?([[:space:]]|$)'
RE_RESET="git[[:space:]]+${RE_GIT_OPTS}reset[[:space:]]+--hard[[:space:]]+(origin|upstream)/(main|staging|develop)"
RE_DIR_C='git[[:space:]]+-C[[:space:]]+([^[:space:]]+)'
RE_DIR_CD='(^|[;&|])[[:space:]]*cd[[:space:]]+([^[:space:];&|]+)'
RE_TWOTOKENS='[[:space:]]+[^[:space:]-][^[:space:]]*[[:space:]]+[^[:space:]-][^[:space:]]*'
RE_COMMIT="(^|[[:space:]&;|])git[[:space:]]+${RE_GIT_OPTS}commit([[:space:]]|$)"
RE_NO_VERIFY='(^|[[:space:]])--no-verify([[:space:]=]|$)'
RE_SHORT_N='(^|[[:space:]])-[a-zA-Z]*n[a-zA-Z]*([[:space:]]|$)'
RE_HOOK_ENV='(^|[[:space:]])(SKIP|HUSKY)=[^[:space:]]'
RE_HOOK_ENV_EXPORT='(^|[[:space:];&|])export[[:space:]]+(SKIP|HUSKY)='
RE_HOOKS_PATH='(^|[[:space:]&;|])git[[:space:]].*core\.hooksPath'
RE_PR_MERGE='(^|[[:space:]&;|])gh[[:space:]]+([^&|;]*[[:space:]])?pr[[:space:]]+merge([[:space:]]|$)'
RE_MERGE_COMMIT='^[[:space:]]*gh[[:space:]]+pr[[:space:]]+merge[[:space:]]+([^[:space:]-][^[:space:]]*)[[:space:]]+--merge[[:space:]]*$'
RE_MERGE_SQUASH='^[[:space:]]*gh[[:space:]]+pr[[:space:]]+merge[[:space:]]+([^[:space:]-][^[:space:]]*)[[:space:]]+--squash[[:space:]]+--match-head-commit[[:space:]]+([^[:space:]]+)[[:space:]]*$'
RE_GH_API='(^|[[:space:]&;|])gh[[:space:]]+api([[:space:]]|$)'
RE_API_REST_MERGE='pulls/[^[:space:]/]+/merge([^a-zA-Z_-]|$)'
RE_API_PUT='(-X|--method)[[:space:]=]*(PUT|put)'
RE_API_GRAPHQL_MERGE='mergePullRequest|enablePullRequestAutoMerge'
RE_GH_URL='github\.com[:/]+([^/]+/[^/]+)$'
RE_WRAPPER='(^|[[:space:]])((ba)?sh[[:space:]]+-c|eval)[[:space:]]+'

# One PR lookup answers every merge question: "<base> <head> <head sha> <owner/name> <verdict>".
# The verdict is green when every check on the head has passed (succeeded, or was neutral or
# skipped) and a `gate / <job>` check of the Gate workflow succeeded, as the rulesets require. Its
# read-draft check does not count, since it passes on a draft too. A check counts by its newest
# run, as in `gh pr checks`: the head keeps the checks of every run, a run cancelled by a later one
# included. A CheckRun counts only once COMPLETED; a StatusContext reads its state.
# $c and $repo are jq's variables. Tried double quotes, but then every " and $ of the program
# needs a backslash.
# shellcheck disable=SC2016
JQ_PR='[.statusCheckRollup // [] | group_by([.workflowName, .name, .context])[] | max_by(.startedAt)
    | if .__typename == "StatusContext" then {gate: false, conclusion: .state}
    else {gate: (.workflowName == "Gate" and (.name | startswith("gate / "))),
      conclusion: (if .status == "COMPLETED" then .conclusion else "PENDING" end)} end] as $c
  | (.url | capture("github\\.com/(?<r>[^/]+/[^/]+)/pull/").r | ascii_downcase) as $repo
  | (if any($c[]; .gate and .conclusion == "SUCCESS") | not then "no-passed-gate"
     elif all($c[]; .conclusion == "SUCCESS" or .conclusion == "NEUTRAL" or .conclusion == "SKIPPED") then "green"
     else "a-check-not-passed" end) as $verdict
  | [.baseRefName, .headRefName, .headRefOid, $repo, $verdict] | join(" ")'

block() { echo "Blocked: $1" >&2; exit 2; }

# Does ONE shell segment push to a protected branch? `bare` has each quoted span replaced by a `_`
# word, so prose can never qualify a segment as a push; `lit` keeps that content with only the
# quote delimiters dropped, so a quoted target still shows. Refs are normalized first:
# `refs/heads/` dropped and the force-prefix `+` made a boundary, else `refs/heads/main` and
# `+main` read as unprotected.
segment_targets_protected() {
  local bare="$1" lit="$2" tail
  [[ "$bare" =~ $RE_PUSH ]] || return 1
  tail="${lit#*push}"
  tail="${tail//refs\/heads\//}"
  tail="${tail//+/ }"
  [[ "$tail" =~ $RE_PROT_TOKEN ]]
}

# Does ONE shell segment commit or push past the commit hooks? Read on `bare`, so a commit message
# that only mentions --no-verify never qualifies. `-n` is --no-verify for commit only; for push
# it is --dry-run.
segment_skips_hooks() {
  local bare="$1"
  [[ "$bare" =~ $RE_HOOKS_PATH ]] && return 0
  if [[ "$bare" =~ $RE_COMMIT ]]; then
    [[ "${bare#*commit}" =~ $RE_NO_VERIFY ]] || [[ "${bare#*commit}" =~ $RE_SHORT_N ]] ||
      [[ "$bare" =~ $RE_HOOK_ENV ]]
  else
    [[ "$bare" =~ $RE_PUSH ]] && [[ "${bare#*push}" =~ $RE_NO_VERIFY ]]
  fi
}

# The owner/name this guard's own checkout pushes to, lowercased, from its origin URL; empty when
# there is none.
own_repo() {
  local url
  url="$(git -C "$HERE" remote get-url origin 2>/dev/null)" || return 0
  url="${url%/}"
  url="${url%.git}"
  [[ "$url" =~ $RE_GH_URL ]] || return 0
  printf '%s\n' "${BASH_REMATCH[1]}" | tr '[:upper:]' '[:lower:]'
}

# In a project that answered agent_merges, may the agent merge this PR into develop? It reads the
# caller's lookup and form. Every condition must hold, else MERGE_WHY names the first that fails.
agent_may_merge() {
  local own
  own="$(own_repo)"
  if [ -z "$own" ] || [ "$prrepo" != "$own" ]; then
    MERGE_WHY="merging a PR of '$prrepo' into develop. This project lets the agent merge only its own repository's PRs${own:+ ($own)}: leave this merge to the owner."
  elif [ "$strategy" != squash ]; then
    MERGE_WHY="merging into develop as a merge commit: develop takes squash merges."
  elif [ "$match" != "$oid" ]; then
    MERGE_WHY="merging into develop without pinning the head the checks ran on: pass --match-head-commit $oid, the PR's head, so a later push cannot land unchecked."
  elif [ "$verdict" != green ]; then
    MERGE_WHY="merging into develop before every check on $oid has passed with a gate / … check of the Gate workflow among them ($verdict). Wait with 'gh pr checks <n> --watch', then merge."
  else
    return 0
  fi
  return 1
}

# Does ONE shell segment merge a PR into a protected branch? The guard reads a merge only in the
# two forms the skills write, word for word, and blocks any other form. Only GitHub knows the
# base, so the PR is looked up, and a failed lookup blocks. A promotion passes only as a merge
# commit: a squash gives the target commits the source never had. With agent_merges,
# agent_may_merge decides a PR into develop.
segment_merges_protected() {
  local bare="$1" pr strategy match="" out base head oid prrepo verdict
  [[ "$bare" =~ $RE_PR_MERGE ]] || return 1
  if [[ "$bare" =~ $RE_MERGE_COMMIT ]]; then
    pr="${BASH_REMATCH[1]}" strategy=merge
  elif [[ "$bare" =~ $RE_MERGE_SQUASH ]]; then
    pr="${BASH_REMATCH[1]}" strategy=squash match="${BASH_REMATCH[2]}"
  else
    MERGE_WHY="merging a PR in a form the guard does not read. Merge as 'gh pr merge <pr> --merge' or 'gh pr merge <n> --squash --match-head-commit <sha>', word for word."
    return 0
  fi
  out="$(cd "$DIR" 2>/dev/null && gh pr view "$pr" --json baseRefName,headRefName,headRefOid,url,statusCheckRollup \
    2>/dev/null | jq -r "$JQ_PR" 2>/dev/null)" || out=""
  read -r base head oid prrepo verdict <<<"$out"
  if [ -z "$base" ]; then
    MERGE_WHY="merging a PR whose base branch could not be looked up; it may be develop, staging or main. Leave the merge to the owner."
    return 0
  fi
  [[ "$base" =~ $RE_PROT_BRANCH ]] || return 1
  case "$head>$base" in
    "develop>staging"|"staging>main")
      [ "$strategy" = merge ] && return 1
      MERGE_WHY="merging the promotion $head → $base as a squash. A squash gives $base commits $head never had, so the branches drift apart and the next promotion conflicts: merge it with --merge."
      return 0
      ;;
  esac
  if [ "$base" = develop ] && [ "$AGENT_MERGES" = true ]; then
    agent_may_merge && return 1
    return 0
  fi
  MERGE_WHY="merging a PR into '$base'. Nothing lands on develop, staging or main without the owner: leave the merge to them."
}

# Does ONE shell segment merge through the GitHub API? Read on `lit`: the route is usually quoted.
segment_api_merges() {
  local bare="$1" lit="$2"
  [[ "$bare" =~ $RE_GH_API ]] || return 1
  [[ "$lit" =~ $RE_API_GRAPHQL_MERGE ]] ||
    { [[ "$lit" =~ $RE_API_REST_MERGE ]] && [[ "$lit" =~ $RE_API_PUT ]]; }
}

# Does ONE shell segment hand a blocked command to bash -c, sh -c or eval? `bare` hides the quoted
# command, so the guard runs itself on `lit` after the wrapper: the text the shell passes on.
segment_wraps_blocked() {
  local bare="$1" lit="$2"
  [[ "$bare" =~ $RE_WRAPPER ]] || return 1
  jq -n --arg c "${lit#*"${BASH_REMATCH[0]}"}" '{tool_input:{command:$c}}' | bash "$0"
  [ $? = 2 ]
}

# Run the segment check named by $1 on every shell segment, via a single left-to-right pass that
# CARRIES QUOTE STATE. Two invariants any rewrite must preserve:
#   * quote state is tracked, never paired by regex: a `"` inside single quotes (or `'` inside
#     double quotes) is literal, and blind pairing shifts every later span — enough for an
#     UNQUOTED `git push origin main` to read as quoted and skip the check;
#   * the pass stays linear: a guard killed at the hook timeout cannot emit exit 2, and this file
#     fails OPEN, so anything superlinear in command length silently disables the check.
# Segments split only on UNQUOTED separators; `\` escapes the next character.
NL=$'\n'
BS="\\"
BRK_NONE="[\"'|;&${BS}${BS}${NL}]"
BRK_DQ="[\"${BS}${BS}]"
BRK_SQ="[']"
any_segment() {
  local check="$1" rest="$COMMAND" state=none bare="" lit="" chunk ch nx
  while [ -n "$rest" ]; do
    # Each BRK_* is a bracket pattern, unquoted so it matches any one of its characters. Tried
    # quoting it, the rule's fix, but then it matches only its own text.
    # shellcheck disable=SC2295
    case "$state" in
      none) chunk="${rest%%$BRK_NONE*}" ;;
      dq) chunk="${rest%%$BRK_DQ*}" ;;
      *) chunk="${rest%%$BRK_SQ*}" ;;
    esac
    if [ "$chunk" = "$rest" ]; then
      if [ "$state" = none ]; then bare+="$chunk"; else bare+="_"; fi
      lit+="$chunk"
      break
    fi
    ch="${rest:${#chunk}:1}"
    rest="${rest:${#chunk}+1}"
    if [ "$state" = none ]; then
      bare+="$chunk"
      lit+="$chunk"
      case "$ch" in
        '"') state=dq ;;
        "'") state=sq ;;
        "$BS") nx="${rest:0:1}"; rest="${rest:1}"; bare+="$nx"; lit+="$nx" ;;
        *)
          "$check" "$bare" "$lit" && return 0
          bare=""
          lit=""
          ;;
      esac
    else
      bare+="_"
      lit+="$chunk"
      if [ "$state" = dq ] && [ "$ch" = "$BS" ]; then
        nx="${rest:0:1}"; rest="${rest:1}"; lit+="$nx"
      else
        state=none
      fi
    fi
  done
  "$check" "$bare" "$lit"
}

# --- Block rm -rf of / or home, and a hard reset onto a protected remote ref ---
[[ "$COMMAND" =~ $RE_RMRF ]] && block "'rm -rf' targeting filesystem root or home directory."
[[ "$COMMAND" =~ $RE_RESET ]] && block "'git reset --hard' against a protected remote ref. Use 'git revert' or run it manually outside Claude."

# --- Block a blocked command that bash -c, sh -c or eval runs ---
any_segment segment_wraps_blocked && exit 2

# --- Block switching to an EXISTING branch (allow new-branch -c/-b and file restore) ---
if [[ "$COMMAND" =~ $RE_SWITCH ]] && ! [[ "$COMMAND" =~ $RE_NEWBRANCH ]] && ! [[ "$COMMAND" =~ $RE_FILEISH ]]; then
  block "switching to an existing branch is disabled in this worktree workflow. Use 'git switch -c <new>' to branch, or 'git restore' / 'git checkout -- <file>' for files."
fi

# --- Block direct push to a protected branch ---
if [[ "$COMMAND" =~ $RE_PUSH ]]; then
  any_segment segment_targets_protected && block "direct push to a protected branch (develop/staging/main). Open a PR instead."
  AFTER="${COMMAND#*push}"
  if ! [[ "$AFTER" =~ $RE_TWOTOKENS ]]; then
    DIR="."
    if   [[ "$COMMAND" =~ $RE_DIR_C ]];  then DIR="${BASH_REMATCH[1]}"
    elif [[ "$COMMAND" =~ $RE_DIR_CD ]]; then DIR="${BASH_REMATCH[2]}"
    fi
    BR="$(git -C "$DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    [[ "$BR" =~ $RE_PROT_BRANCH ]] && block "current branch '$BR' is protected; direct push is disabled. Open a PR instead."
  fi
fi

# --- Block merging a PR in another form or into a protected branch, and the API merge routes ---
if [[ "$COMMAND" =~ $RE_PR_MERGE ]]; then
  DIR="."
  [[ "$COMMAND" =~ $RE_DIR_CD ]] && DIR="${BASH_REMATCH[2]}"
  MERGE_WHY=""
  any_segment segment_merges_protected && block "$MERGE_WHY"
fi
if [[ "$COMMAND" =~ $RE_GH_API ]]; then
  any_segment segment_api_merges &&
    block "merging through the GitHub API. Use 'gh pr merge', which checks the PR's base branch."
fi

# --- Block skipping the commit hooks ---
# The commit hooks are the only check some files get before CI, so a skipped hook lands unchecked
# code. An exported SKIP/HUSKY reaches a later segment's commit, hence the whole-command test
# beside the per-segment one.
if any_segment segment_skips_hooks ||
  { [[ "$COMMAND" =~ $RE_COMMIT ]] && [[ "$COMMAND" =~ $RE_HOOK_ENV_EXPORT ]]; }; then
  block "skipping the commit hooks (--no-verify, commit -n, SKIP=/HUSKY=, core.hooksPath). Fix what the hook reports; if a hook itself is broken, tell the user."
fi

# --- Block committing in the PRIMARY working tree (main checkout), on any branch ---
# Complements worktree-guard.sh (Edit/Write): catches changes that reached the main
# checkout another way (hand-edits, stash pop, merge) OR a feature branch created in the
# main checkout instead of a worktree. Linked worktrees are unaffected — git-dir equals
# git-common-dir only in the primary checkout.
if [[ "$COMMAND" =~ $RE_COMMIT ]]; then
  DIR="."
  if   [[ "$COMMAND" =~ $RE_DIR_C ]];  then DIR="${BASH_REMATCH[1]}"
  elif [[ "$COMMAND" =~ $RE_DIR_CD ]]; then DIR="${BASH_REMATCH[2]}"
  fi
  GD="$(git -C "$DIR" rev-parse --absolute-git-dir 2>/dev/null || true)"
  CD="$(git -C "$DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [ -n "$GD" ] && [ "$GD" = "$CD" ]; then
    CB="$(git -C "$DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    block "committing in the main checkout (branch '$CB'). Feature work belongs in a linked worktree — start the task with /task:start (.claude/rules/agentic.md)."
  fi
fi

exit 0
