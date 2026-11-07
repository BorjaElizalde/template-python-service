#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
# Table-driven regression suite for bash-guard.sh (the copy sitting next to this file).
# Run from any repo checkout: bash .claude/hooks/bash-guard.test.sh
# Exit 2 = guard blocked, 0 = guard allowed. Every case documents a policy decision or a class
# that once regressed or bypassed.
set -u
SRC="$(cd "$(dirname "$0")" && pwd)/bash-guard.sh"
pass=0; fail=0

# A stub gh answers the guard's PR lookup, `gh pr view [<pr>] [--repo <r>] --json ...`, with the
# PR's JSON in the shape gh prints. The PR's repository is the --repo it names, else the origin of
# the folder gh runs in, else acme/app. Every PR's head is $H.
STUB="$(mktemp -d)"
trap 'rm -rf "$STUB"' EXIT
H=1111111111111111111111111111111111111111
printf '#!/usr/bin/env bash\nH=%s\n' "$H" >"$STUB/gh"
cat >>"$STUB/gh" <<'EOF'
[ "$1 $2" = "pr view" ] || exit 1
shift 2
pr="" repo=""
while [ $# -gt 0 ]; do
  case "$1" in
    -R|--repo) repo="$2"; shift ;;
    --json|--jq) shift ;;
    -*) ;;
    *) [ -n "$pr" ] || pr="$1" ;;
  esac
  shift
done
if [ -z "$repo" ]; then
  url="$(git remote get-url origin 2>/dev/null)" && repo="${url#https://github.com/}" && repo="${repo%.git}"
fi
run() { printf '{"__typename":"CheckRun","name":"%s","status":"%s","conclusion":"%s"}' "$1" "$2" "$3"; }
ctx() { printf '{"__typename":"StatusContext","context":"%s","state":"%s"}' "$1" "$2"; }
GATE="$(run gate COMPLETED SUCCESS)"
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
  "") pr_json feat/x fix/y "$GATE" ;;
  # The opt-in cases' PRs into develop, each with its checks.
  21) pr_json develop feat/x "$GATE,$(run docs COMPLETED SKIPPED),$(ctx legacy/ci SUCCESS)" ;;
  22) pr_json develop feat/x "$(run gate IN_PROGRESS '')" ;;
  23) pr_json develop feat/x "$(run lint COMPLETED SUCCESS)" ;;
  24) pr_json develop feat/x "$GATE,$(run test COMPLETED FAILURE)" ;;
  25) pr_json develop feat/x "$GATE,$(ctx legacy/ci PENDING)" ;;
  26) pr_json develop feat/x "" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$STUB/gh"
export PATH="$STUB:$PATH"

# The guard reads agent_merges from the agentic.conf beside its folder, and its own repository from
# its checkout's origin. Each copy below runs beside a fixture answer, so the cases never depend on
# the answers this project was rendered with.
fixture() {  # fixture <dir> <agent_merges> [<origin>]
  mkdir -p "$1/.claude/hooks"
  cp "$SRC" "$1/.claude/hooks/bash-guard.sh"
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
t 2 "reset hard origin main"           'git reset --hard origin/main'
t 2 "switch existing branch"           'git switch develop'

echo "-- merges into protected branches (PR 11 feat→develop, 12 develop→staging, 13 staging→main,"
echo "   14 fix→feat, 15 feat→main, unnamed = the current branch's PR, fix→feat)"
t 2 "feature PR into develop"          'gh pr merge 11 --merge'
t 2 "feature PR into main"             'gh pr merge 15 --squash'
t 2 "auto-merge into develop"          'gh pr merge --auto --merge 11'
t 2 "after cd"                         'cd /tmp && gh pr merge 11 --merge'
t 2 "quoted subject is not the PR"     'gh pr merge --subject "Merge 14" 11 --merge'
t 2 "promotion squashed"               'gh pr merge 12 --squash'
t 2 "promotion rebased"                'gh pr merge 13 --rebase'
t 2 "promotion with no strategy"       'gh pr merge 12'
t 2 "PR not found"                     'gh pr merge 99 --merge'
t 2 "REST merge route"                 'gh api -X PUT repos/o/r/pulls/14/merge'
t 2 "GraphQL merge mutation"           "gh api graphql -f query='mutation { mergePullRequest(input: {pullRequestId: \"x\"}) { clientMutationId } }'"
t 0 "promotion develop→staging"        'gh pr merge 12 --merge'
t 0 "promotion staging→main, -md"      'gh pr merge 13 -md'
t 0 "stacked PR into a feature branch" 'gh pr merge 14 --squash -d'
t 0 "current branch's stacked PR"      'gh pr merge --merge'
t 0 "PR lookup only"                   'gh pr view 11'
t 0 "REST read of merge state"         'gh api repos/o/r/pulls/11/merge'
t 0 "msg mentions a merge"             'git commit -m "gh pr merge 11"'
t 0 "local merge into a feature branch" 'git merge origin/develop'
t 2 "without agent_merges, a green pinned squash is still the owner's" "gh pr merge 21 --squash --match-head-commit $H"
# A short-flag cluster is read as gh reads it: a letter that takes a value takes the rest.
t 2 "promotion squashed, an m in an attached subject"   'gh pr merge 12 --squash -tmessage'
t 2 "promotion given two strategies"                    'gh pr merge 12 --merge --squash'
t 0 "promotion with -m and an attached subject"         'gh pr merge 12 -m -tsubject'
t 0 "promotion with --merge=true"                       'gh pr merge 12 --merge=true'
t 2 "promotion with --merge=false"                      'gh pr merge 12 --merge=false'

echo "-- agent_merges: the agent's own PR into develop, squashed, pinned to a head whose every check"
echo "   passed with gate among them (PR 21 green; 22 gate running; 23 no gate; 24 a check failed;"
echo "   25 a status pending; 26 no checks; 16 bugfix→staging)"
t_on 0 "own green PR, squash, pinned head"   "gh pr merge 21 --squash --match-head-commit $H"
t_on 0 "pin given with ="                    "gh pr merge 21 --squash --match-head-commit=$H"
t_on 0 "short -s in a cluster with -d"       "gh pr merge 21 -sd --match-head-commit $H"
t_on 0 "own repo named with -R, any case"    "gh pr merge 21 -R Acme/App --squash --match-head-commit $H"
t_on 0 "promotion still passes"              'gh pr merge 12 --merge'
t_on 2 "no pin"                              'gh pr merge 21 --squash'
t_on 2 "pin to another commit"               'gh pr merge 21 --squash --match-head-commit 2222222222222222222222222222222222222222'
t_on 2 "a merge commit into develop"         "gh pr merge 21 --merge --match-head-commit $H"
t_on 2 "a rebase into develop"               "gh pr merge 21 --rebase --match-head-commit $H"
t_on 2 "--auto"                              "gh pr merge 21 --squash --auto --match-head-commit $H"
t_on 2 "--admin"                             "gh pr merge 21 --squash --admin --match-head-commit $H"
t_on 2 "gate still running"                  "gh pr merge 22 --squash --match-head-commit $H"
t_on 2 "no gate among the checks"            "gh pr merge 23 --squash --match-head-commit $H"
t_on 2 "a check failed"                      "gh pr merge 24 --squash --match-head-commit $H"
t_on 2 "a status still pending"              "gh pr merge 25 --squash --match-head-commit $H"
t_on 2 "no checks at all"                    "gh pr merge 26 --squash --match-head-commit $H"
t_on 2 "another repository named with -R"    "gh pr merge 21 -R other/app --squash --match-head-commit $H"
t_on 2 "another repository after cd"         "cd $STUB/other && gh pr merge 21 --squash --match-head-commit $H"
t_on 2 "bugfix into staging stays the owner's" "gh pr merge 16 --squash --match-head-commit $H"
t_on 2 "feature into main stays the owner's" "gh pr merge 15 --squash --match-head-commit $H"
t_on 2 "a squashed promotion still blocks"   "gh pr merge 12 --squash --match-head-commit $H"
t_on 2 "REST merge route still blocks"       'gh api -X PUT repos/acme/app/pulls/21/merge'
guard_case "$STUB/on-ssh/.claude/hooks/bash-guard.sh" 0 "own repo from an ssh origin" "gh pr merge 21 --squash --match-head-commit $H"
guard_case "$STUB/on-no-origin/.claude/hooks/bash-guard.sh" 2 "no origin, so no own repository" "gh pr merge 21 --squash --match-head-commit $H"
says "--match-head-commit $H" "a missing pin names the head to pin" 'gh pr merge 21 --squash'
says "a-check-not-passed" "a failed check is named in the verdict" "gh pr merge 24 --squash --match-head-commit $H"
says "only its own repository" "another repository is named as not this project's" "gh pr merge 21 -R other/app --squash --match-head-commit $H"
t_on 2 "a rebase whose attached subject holds an s"     "gh pr merge 21 -r -tsubject --match-head-commit $H"
t_on 2 "a squash and a rebase both"                     "gh pr merge 21 --squash --rebase --match-head-commit $H"
t_on 2 "--squash=false"                                 "gh pr merge 21 --squash=false --rebase --match-head-commit $H"
t_on 0 "-s, then an attached subject"                   "gh pr merge 21 -s -tmessage --match-head-commit $H"
t_on 0 "-st, the subject the next word"                 "gh pr merge 21 -st subject --match-head-commit $H"
t_on 0 "--squash=true"                                  "gh pr merge 21 --squash=true --match-head-commit $H"
t_on 2 "another repository attached to -R"              "gh pr merge 21 -Rother/app --squash --match-head-commit $H"
t_on 2 "another repository in an -sR cluster"           "gh pr merge 21 -sR other/app --match-head-commit $H"
t_on 2 "--auto=true"                                    "gh pr merge 21 --squash --auto=true --match-head-commit $H"
t_on 0 "--auto=false"                                   "gh pr merge 21 --squash --auto=false --match-head-commit $H"
t_on 2 "--admin=1"                                      "gh pr merge 21 --squash --admin=1 --match-head-commit $H"

echo "-- skipping the commit hooks (must block)"
t 2 "commit --no-verify"               'git commit --no-verify -m "x"'
t 2 "commit -n"                        'git commit -n -m "x"'
t 2 "commit -nm cluster"               'git commit -nm "x"'
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
