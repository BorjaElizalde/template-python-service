#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
# Table-driven regression suite for bash-guard.sh (the copy sitting next to this file).
# Run from any repo checkout: bash .claude/hooks/bash-guard.test.sh
# Exit 2 = guard blocked, 0 = guard allowed. Every case documents a policy decision or a class
# that once regressed or bypassed.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
pass=0; fail=0

check_run() {  # check_run <name> <workflow> <status> <conclusion> [<started at>]
  printf '{"__typename":"CheckRun","name":"%s","workflowName":"%s","status":"%s","conclusion":"%s","startedAt":"%s"}' \
    "$1" "$2" "$3" "$4" "${5:-}"
}
status_context() { printf '{"__typename":"StatusContext","context":"%s","state":"%s"}' "$1" "$2"; }
GATE_NAME=gate
GATE="$(check_run "$GATE_NAME" Gate COMPLETED SUCCESS)"
FAILED="$(check_run test Test COMPLETED FAILURE)"

# A stub gh answers the guard's PR lookup with the PR's JSON in the shape gh prints.
STUB="$(mktemp -d)"
trap 'rm -rf "$STUB"' EXIT
H=1111111111111111111111111111111111111111
{ echo '#!/usr/bin/env bash'; declare -p H GATE FAILED; } >"$STUB/gh"
cat >>"$STUB/gh" <<'EOF'
[ "$1 $2" = "pr view" ] || exit 1
shift 2
pr="" repo=""
while [ $# -gt 0 ]; do
  case "$1" in
    -R|--repo) repo="$2"; shift ;;
    --json|--jq) shift ;;
    -*) ;;
    *) [ -n "$pr" ] || pr="${1##*/}" ;;
  esac
  shift
done
if [ -z "$repo" ]; then
  url="$(git remote get-url origin 2>/dev/null)" && repo="${url#https://github.com/}" && repo="${repo%.git}"
fi
pr_json() {  # pr_json <base> <head> <checks>
  printf '{"baseRefName":"%s","headRefName":"%s","headRefOid":"%s","url":"https://github.com/%s/pull/%s","statusCheckRollup":[%s]}\n' \
    "$1" "$2" "$H" "${repo:-acme/app}" "${pr:-1}" "$3"
}
case "$pr" in
  11) pr_json develop feat/x "$GATE" ;;
  12) pr_json staging develop "$GATE" ;;
  13) pr_json main staging "$GATE" ;;
  14) pr_json feat/x fix/y "$GATE" ;;
  15) pr_json main feat/x "$GATE" ;;
  16) pr_json staging bugfix/x "$GATE" ;;
  17) pr_json develop feat/x "$GATE,$FAILED" ;;
  "") pr_json feat/x fix/y "$GATE" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$STUB/gh"
export PATH="$STUB:$PATH"

# Each guard copy below runs beside a fixture answer and origin, so the cases never depend on the
# answers this project was rendered with.
fixture() {  # fixture <dir> <agent_merges> [<origin>]
  mkdir -p "$1/.claude/hooks"
  cp "$HERE/bash-guard.sh" "$HERE/pr-checks.jq" "$1/.claude/hooks/"
  printf 'AGENT_MERGES=%s\n' "$2" >"$1/.claude/agentic.conf"
  git init -q "$1"
  [ -z "${3:-}" ] || git -C "$1" remote add origin "$3"
}
fixture "$STUB/off" false https://github.com/Acme/App.git
fixture "$STUB/on" true https://github.com/Acme/App.git
fixture "$STUB/on-ssh" true git@github.com:acme/app.git
fixture "$STUB/on-no-origin" true
git init -q "$STUB/other"
git -C "$STUB/other" remote add origin https://github.com/other/app.git
GUARD="$STUB/off/.claude/hooks/bash-guard.sh"

# The guard blocks a commit in a main checkout, so the folder a case runs in decides its verdict.
# Every case runs in $STUB, which is no repo; the main-checkout cases name their repo with cd.
git init -q "$STUB/repo"
git -C "$STUB/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$STUB/repo" worktree add -q --detach "$STUB/worktree"

guard_case() {  # guard_case <guard> <want> <desc> <command>
  local guard="$1" exp="$2" desc="$3" cmd="$4" got
  (cd "$STUB" && jq -n --arg c "$cmd" '{tool_input:{command:$c}}' | bash "$guard" >/dev/null 2>&1)
  got=$?
  if [ "$got" -eq "$exp" ]; then pass=$((pass+1)); echo "PASS ($got) $desc"
  else fail=$((fail+1)); echo "FAIL (want $exp, got $got) $desc :: $cmd"; fi
}
t() { guard_case "$GUARD" "$@"; }
t_on() { guard_case "$STUB/on/.claude/hooks/bash-guard.sh" "$@"; }
says() {  # says <phrase> <desc> <command>: the opt-in guard blocks, naming <phrase>
  local out
  out="$(cd "$STUB" && jq -n --arg c "$3" '{tool_input:{command:$c}}' | bash "$STUB/on/.claude/hooks/bash-guard.sh" 2>&1)"
  if [[ "$out" == *"$1"* ]]; then pass=$((pass+1)); echo "PASS (says) $2"
  else fail=$((fail+1)); echo "FAIL (want '$1') $2 :: $out"; fi
}
verdict_is() {  # verdict_is <verdict> <desc> <checks>: the verdict on a PR with those checks
  local got
  got="$(jq -r -L "$HERE" 'import "pr-checks" as checks; checks::verdict' <<<"{\"statusCheckRollup\": [$3]}")"
  if [ "$got" = "$1" ]; then pass=$((pass+1)); echo "PASS ($got) $2"
  else fail=$((fail+1)); echo "FAIL (want $1, got $got) $2 :: [$3]"; fi
}

echo "-- protected pushes (must block)"
t 2 "push main"                        'git push origin main'
t 2 "push staging"                     'git push origin staging'
t 2 "push develop"                     'git push origin develop'
t 2 "push quoted main"                 'git push origin "main"'
t 2 "push single-quoted staging"       "git push origin 'staging'"
t 2 "push full ref"                    'git push origin refs/heads/main'
t 2 "push refspec to full ref"         'git push origin HEAD:refs/heads/main'
t 2 "push quoted full ref"             'git push origin "refs/heads/staging"'
t 2 "force refspec"                    'git push origin +main'
t 2 "deletion refspec"                 'git push origin :main'
t 2 "refspec to main"                  'git push origin HEAD:main'
t 2 "quoted refspec to main"           'git push origin "HEAD:main"'
t 2 "force push main"                  'git push --force origin main'
t 2 "lease still direct-push-blocked"  'git push --force-with-lease origin main'

echo "-- mixed quoting (a stray quote must not shift span pairing and hide a real push)"
t 2 "inch mark in commit msg"          'git commit -m '"'"'fix: 5" gap'"'"' && git push origin main && echo "done"'
t 2 "inch mark + force push"           'git commit -m '"'"'5" gap'"'"' && git push --force origin main && echo "x"'
t 2 "inch mark + -u staging"           'git commit -m '"'"'the 5" screen'"'"' && git push -u origin staging && echo "shipped"'
t 2 "double quote inside single"       'echo '"'"'a"b'"'"' ; git push origin main ; echo "c"'
t 2 "escaped quote inside double"      'git commit -m "say \"x" && git push origin main && echo "ok"'

echo "-- other reliable blocks"
t 2 "rm -rf root"                      'rm -rf /'
t 2 "rm -rf home"                      'rm -rf ~'
t 2 "rm -rf \$HOME"                    "rm -rf \$HOME"
t 2 "rm -rf quoted \$HOME"             "rm -rf \"\$HOME\""
t 2 "rm -rf \${HOME}"                  "rm -rf \${HOME}"
t 2 "rm -rf everything under root"     'rm -rf /*'
t 2 "rm -rf everything under home"     'rm -rf ~/*'
t 0 "rm -rf a folder under \$HOME"     "rm -rf \$HOME/build"
t 0 "rm -rf a quoted folder under \$HOME" "rm -rf \"\$HOME/build\""
t 2 "reset hard origin main"           'git reset --hard origin/main'
t 2 "reset hard after -C"              'git -C x reset --hard origin/main'
t 2 "switch existing branch"           'git switch develop'
t 2 "switch after -c"                  'git -c x=y switch main'

echo "-- a command that bash -c, sh -c or eval runs is checked as if sent on its own"
t 2 "bash -c merge"                    'bash -c "gh pr merge 12 --squash"'
t 2 "sh -c push"                       'sh -c "git push origin main"'
t 2 "eval push"                        'eval "git push origin main"'
t 2 "bash -c in bash -c"               "bash -c \"bash -c 'git push origin main'\""
t 0 "bash -c of an allowed command"    'bash -c "git status"'
t 0 "bash -c commit whose msg names a push" 'bash -c "git commit -m \"a; git push origin main\""'

echo "-- merges: only 'gh pr merge <pr> --merge' and 'gh pr merge <n> --squash --match-head-commit <sha>'"
t 2 "feature PR into develop"          'gh pr merge 11 --merge'
t 2 "feature PR into main"             "gh pr merge 15 --squash --match-head-commit $H"
t 2 "after cd"                         'cd /tmp && gh pr merge 11 --merge'
t 2 "promotion squashed"               "gh pr merge 12 --squash --match-head-commit $H"
t 2 "PR not found"                     'gh pr merge 99 --merge'
t 2 "another form, into a feature branch" 'gh pr merge 14 --squash -d'
t 2 "another form, no strategy"        'gh pr merge 12'
t 2 "another form, a flag before pr"   'gh -R o/r pr merge 12 --merge'
t 2 "REST merge route"                 'gh api -X PUT repos/o/r/pulls/14/merge'
t 2 "GraphQL merge mutation"           "gh api graphql -f query='mutation { mergePullRequest(input: {pullRequestId: \"x\"}) { clientMutationId } }'"
t 0 "promotion develop→staging"        'gh pr merge 12 --merge'
t 0 "promotion staging→main"           'gh pr merge 13 --merge'
t 0 "promotion named by its URL"       'gh pr merge https://github.com/acme/app/pull/12 --merge'
t 0 "stacked PR into a feature branch" "gh pr merge 14 --squash --match-head-commit $H"
t 0 "PR lookup only"                   'gh pr view 11'
t 0 "REST read of merge state"         'gh api repos/o/r/pulls/11/merge'
t 0 "msg mentions a merge"             'git commit -m "gh pr merge 11"'
t 0 "local merge into a feature branch" 'git merge origin/develop'
t 2 "without agent_merges, a green pinned squash is still the owner's" "gh pr merge 11 --squash --match-head-commit $H"

echo "-- the verdict on a PR's checks, which the merge guard and the status line both give"
verdict_is "checks passed" "every check passed, skipped or neutral, the gate among them" "$(check_run read-draft Gate COMPLETED SUCCESS),$GATE,$(check_run docs Docs COMPLETED SKIPPED),$(status_context legacy/ci SUCCESS)"
verdict_is "checks pending" "the gate still running" "$(check_run "$GATE_NAME" Gate IN_PROGRESS '')"
verdict_is "gate not run" "no gate among the checks" "$(check_run lint Lint COMPLETED SUCCESS)"
verdict_is "checks failed" "a check failed" "$GATE,$FAILED"
verdict_is "checks failed" "a failed check outweighs a pending one" "$(check_run lint Lint IN_PROGRESS ''),$FAILED"
verdict_is "checks pending" "a status still pending" "$GATE,$(status_context legacy/ci PENDING)"
verdict_is "no checks" "no checks at all" ""
# An empty conclusion is not a pass, even on a check that says it completed.
verdict_is "checks failed" "a check completed with no conclusion" "$GATE,$(check_run test Test COMPLETED '')"
verdict_is "checks failed" "a failed up-to-date status, though the checks passed" "$GATE,$(check_run up-to-date 'Branch protection' COMPLETED SUCCESS),$(status_context up-to-date FAILURE)"
verdict_is "gate not run" "the gate's check name from another workflow" "$(check_run "$GATE_NAME" Lint COMPLETED SUCCESS)"
verdict_is "gate not run" "the gate skipped" "$(check_run "$GATE_NAME" Gate COMPLETED SKIPPED)"
verdict_is "gate not run" "the gate skipped, read-draft passed" "$(check_run read-draft Gate COMPLETED SUCCESS),$(check_run "$GATE_NAME" Gate COMPLETED SKIPPED)"
verdict_is "checks passed" "a check counts by its newest run, not by an earlier one cancelled" "$(check_run read-draft Gate COMPLETED SUCCESS 2026-01-01T00:00:10Z),$(check_run read-draft Gate COMPLETED CANCELLED 2026-01-01T00:00:00Z),$GATE"

echo "-- agent_merges: the agent's own PR into develop, squashed, pinned to a head whose checks passed"
t_on 0 "own green PR, squash, pinned head"   "gh pr merge 11 --squash --match-head-commit $H"
t_on 0 "promotion still passes"              'gh pr merge 12 --merge'
t_on 2 "pin to another commit"               'gh pr merge 11 --squash --match-head-commit 2222222222222222222222222222222222222222'
t_on 2 "a merge commit into develop"         'gh pr merge 11 --merge'
t_on 2 "--auto"                              "gh pr merge 11 --squash --auto --match-head-commit $H"
t_on 2 "checks not passed"                   "gh pr merge 17 --squash --match-head-commit $H"
t_on 2 "another repository after cd"         "cd $STUB/other && gh pr merge 11 --squash --match-head-commit $H"
t_on 2 "bugfix into staging stays the owner's" "gh pr merge 16 --squash --match-head-commit $H"
t_on 2 "feature into main stays the owner's" "gh pr merge 15 --squash --match-head-commit $H"
t_on 2 "a squashed promotion still blocks"   "gh pr merge 12 --squash --match-head-commit $H"
t_on 2 "REST merge route still blocks"       'gh api -X PUT repos/acme/app/pulls/11/merge'
guard_case "$STUB/on-ssh/.claude/hooks/bash-guard.sh" 0 "own repo from an ssh origin" "gh pr merge 11 --squash --match-head-commit $H"
guard_case "$STUB/on-no-origin/.claude/hooks/bash-guard.sh" 2 "no origin, so no own repository" "gh pr merge 11 --squash --match-head-commit $H"
says "--match-head-commit <sha>', word for word" "a merge in another form names the two forms" 'gh pr merge 11 --squash'
says "read 'checks failed'" "checks not passed are named by their verdict" "gh pr merge 17 --squash --match-head-commit $H"
says "only its own repository" "another repository is named as not this project's" "cd $STUB/other && gh pr merge 11 --squash --match-head-commit $H"

echo "-- skipping the commit hooks (must block)"
t 2 "commit --no-verify"               'git commit --no-verify -m "x"'
t 2 "commit -n"                        'git commit -n -m "x"'
t 2 "commit -nm cluster"               'git commit -nm "x"'
t 2 "-c before commit --no-verify"     'git -c user.name=z commit --no-verify -m x'
t 2 "SKIP env on commit"               'SKIP=lint git commit -m "x"'
t 2 "quoted SKIP env on commit"        'SKIP="lint" git commit -m "x"'
t 2 "HUSKY=0 on commit"                'HUSKY=0 git commit -m "x"'
t 2 "exported SKIP, later commit"      'export SKIP=lint && git commit -m "x"'
t 2 "hooksPath override on commit"     'git -c core.hooksPath=/dev/null commit -m "x"'
t 2 "hooksPath set persistently"       'git config core.hooksPath /dev/null'
t 2 "push --no-verify"                 'git push --no-verify origin feat/x'
t 2 "no-verify after a quoted msg"     'git commit -m "x" --no-verify'
t 2 "heredoc commit with --no-verify"  $'git commit --no-verify -F - <<\'EOF\'\nx\nEOF'

echo "-- committing in a main checkout (must block); a linked worktree may commit"
t 2 "commit after cd to a main checkout" "cd $STUB/repo && git commit -m \"x\""
t 2 "commit -C a main checkout"        "git -C $STUB/repo commit -m \"x\""
t 0 "commit in a linked worktree"      "cd $STUB/worktree && git commit -m \"x\""

echo "-- false positives (must pass)"
t 0 "msg only mentions --no-verify"    'git commit -m "never use --no-verify"'
t 0 "msg mentions SKIP="               'git commit -m "document SKIP=lint"'
t 0 "heredoc msg mentions --no-verify" $'git commit -F - <<\'EOF\'\nBlock hook skips\n\n- never pass --no-verify or -n\nEOF'
# A reviewer posts its report from a heredoc, and writes each command in it in backticks.
t 0 "review names git cmds in backticks" $'gh pr comment --body-file - <<\'EOF\'\n## Code review\n- it runs `git push origin main`, then `git switch main`\nEOF'
t 0 "amend --no-edit"                  'git commit --amend --no-edit'
t 0 "signoff flag"                     'git commit -s -m "x"'
t 0 "push -n is a dry run"             'git push -n origin feat/x'
t 0 "commit msg mentions main"         'git commit -m "align with main"'
t 0 "commit msg with push+main prose"  'git commit -m "push to main later"'
t 0 "separator inside quoted prose"    'git commit -m "talk ; git push origin main"'
t 0 "push feat + pr base main"         'git push origin feat/x && gh pr create --base main'
t 0 "commit main msg then push feat"   'git commit -m "main" && git push origin feat/x'
t 0 "branch name contains main"        'git push origin fix/main-page'
t 0 "full ref to unprotected branch"   'git push origin refs/heads/feat/x'
t 0 "prose only"                       'echo "deploy to staging"'
t 0 "new branch switch"                'git switch -c feat/new-thing'
t 0 "lease on feature branch"          'git push --force-with-lease origin feat/x'
# The quote pass must stay linear: past the hook timeout the guard fails OPEN.
t 0 "large push + quoted PR body" "git push origin feat/x && gh pr create --body \"$(awk 'BEGIN{for(i=0;i<200;i++) printf "\"old\" | \"new\" row%d ", i}')\""

echo "== $pass passed, $fail failed"
[ "$fail" -eq 0 ]
