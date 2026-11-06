#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
# Table-driven regression suite for bash-guard.sh (the copy sitting next to this file).
# Run from any repo checkout: bash .claude/hooks/bash-guard.test.sh
# Exit 2 = guard blocked, 0 = guard allowed. Every case documents a policy decision or a class
# that once regressed or bypassed.
set -u
GUARD="$(cd "$(dirname "$0")" && pwd)/bash-guard.sh"
pass=0; fail=0

# A stub gh answers the guard's PR lookup: `gh pr view [<pr>]` prints "<base> <head>".
STUB="$(mktemp -d)"
trap 'rm -rf "$STUB"' EXIT
cat >"$STUB/gh" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "pr view" ] || exit 1
case "${3:-}" in
  11) echo "develop feat/x" ;;
  12) echo "staging develop" ;;
  13) echo "main staging" ;;
  14) echo "feat/x fix/y" ;;
  15) echo "main feat/x" ;;
  --*|"") echo "feat/x fix/y" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$STUB/gh"
export PATH="$STUB:$PATH"

# The guard blocks a commit in a main checkout, so the folder a case runs in decides its verdict.
# Every case runs in $STUB, which is no repo; the main-checkout cases name their repo with cd.
git init -q "$STUB/repo"
git -C "$STUB/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$STUB/repo" worktree add -q --detach "$STUB/worktree"

t() {
  local exp="$1" desc="$2" cmd="$3" got
  (cd "$STUB" && jq -n --arg c "$cmd" '{tool_input:{command:$c}}' | bash "$GUARD" >/dev/null 2>&1)
  got=$?
  if [ "$got" -eq "$exp" ]; then pass=$((pass+1)); echo "PASS ($got) $desc"
  else fail=$((fail+1)); echo "FAIL (want $exp, got $got) $desc :: $cmd"; fi
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
