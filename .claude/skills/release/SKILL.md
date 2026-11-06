---
name: release
description: Use when `develop` is ready to ship as a new template version — promotes `develop` to `main` as a merge commit, then reports the tag `Build` pushes.
model: haiku
effort: high
allowed-tools: Bash(git fetch:*), Bash(git log:*), Bash(git diff:*), Bash(gh pr list:*), Bash(gh pr view:*), Bash(gh pr create:*), Bash(gh pr checks:*), Bash(gh pr merge:*), Bash(gh run list:*), Bash(gh run watch:*)
---

## Release context

- Pending on `develop`: !`git fetch origin develop main --quiet 2>/dev/null; git --no-pager log origin/main..origin/develop --first-parent --oneline`
- Open release PR: !`gh pr list --base main --head develop --state open --json url --jq '.[].url'`

Run unattended while everything is green. **Stop at the first red** — a failed or cancelled check, a
merge that will not apply, a failed `Build` — and report what went red and its run URL.

1. Nothing pending → the release is already out; say so and stop. An open `develop` → `main` PR →
   adopt it rather than opening a second.
2. Group the pending first-parent commits into themes, reading enough of
   `git diff origin/main...origin/develop`. Run `gh pr create --head develop --base main` with the
   title `Release: <themes>` (at most 72 characters) and `Summary`, `Included changes` and
   `Validation` sections. `Validation` states that every change passed `Gate` on its `develop` PR.
3. Wait for its checks with `gh pr checks <pr> --watch --fail-fast`.
4. Merge with `gh pr merge <pr> --merge`. Never squash, never rebase: `main` must keep `develop`'s
   commits, or the next release PR carries them again and conflicts.
5. Find the `Build` run of the merge commit with `gh run list --workflow Build --branch main --limit 1`
   and wait for it with `gh run watch <id> --exit-status`. Its last job pushes the version tag.
   Close with the PR URL, the `Gate` result, and the tag.
