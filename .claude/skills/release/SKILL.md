---
name: release
description: Use when `develop` is ready to ship to `main` — promotes it to `staging`, then to `main`, waiting on checks and merging each PR.
model: haiku
effort: xhigh
allowed-tools: Bash(bash:*), Bash(git fetch:*), Bash(git log:*), Bash(git diff:*), Bash(gh pr list:*), Bash(gh pr view:*), Bash(gh pr create:*), Bash(gh pr checks:*), Bash(gh pr merge:*)
---

## Release context

- `develop` → `staging` pending: !`git fetch origin develop staging --quiet 2>/dev/null; git --no-pager log origin/staging..origin/develop --first-parent --oneline`
- `develop` → `staging` open PR: !`gh pr list --base staging --head develop --state open --json url --jq '.[].url'`
- `staging` → `main` pending: !`git fetch origin staging main --quiet 2>/dev/null; git --no-pager log origin/main..origin/staging --first-parent --oneline`
- `staging` → `main` open PR: !`gh pr list --base main --head staging --state open --json url --jq '.[].url'`

Every promotion PR carries one check, `gate`: it checks the PR comes from the branch below its
base (`develop` into `staging`, `staging` into `main`), then runs the project's checks on the merge
result.
The rulesets require it, so a promotion PR with no check is a red.

Run every leg unattended for as long as everything is green: never pause to confirm a green step.
**Stop at the first red** — a failed or cancelled check, a merge that will not apply, a failed
deploy — and report what went red, its run URL, and which branches the release reached before it
stopped. Never continue past a red.

Every merge is `gh pr merge <pr> --merge`. Never squash, never rebase: a squash or rebase gives the
target commits the source never had, so the branches drift apart and the next promotion conflicts.

## 1. Pick the starting leg

Nothing pending on any leg → the release is already out; say so and stop. An empty earlier leg
with a later leg pending → an earlier release half-landed; resume at the first pending leg. An open
promotion PR for a leg → adopt it rather than opening a second.

## 2. Each leg in order, from `develop` to `main`

1. Fetch both branches and group the pending first-parent commits of `origin/<dst>..origin/<src>`
   into themes, reading enough of the diff. A leg can span more than the previous merge when an
   earlier release stopped there.
2. `gh pr create --head <src> --base <dst>`, title at most 72 characters in the form
   `Release: <themes> to <dst>`, body with `Summary`, `Included changes`, `Validation` and
   `Merge strategy` sections. `Validation` states what `gate` proves for this leg.
3. Run `bash "${CLAUDE_SKILL_DIR}/scripts/await-checks.sh" <pr>` in the background. Exit 3 (no
   check ever registered) is a red.
4. Merge. After the last leg, read the merge commit:
   `gh pr view <pr> --json mergeCommit --jq .mergeCommit.oid`.

## 3. Deploy

The merge into `main` starts `Build`. Run
`bash "${CLAUDE_SKILL_DIR}/scripts/await-run.sh" Build <last-merge-sha>` in the background.

Either wait script may be cut short before it reaches a verdict; both resume, so start it again
rather than reading the truncated output as a result. Close with every PR URL, the check results,
and the deploy conclusion and URL.
