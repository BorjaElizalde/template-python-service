#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
# Watch one workflow's run for a commit through to completion.
#   0  the run succeeded
#   1  the run failed or was cancelled
#   2  usage, or no run registered for the commit inside the grace window
# Resumable: a run cut short mid-watch can simply be started again.
set -u -o pipefail

workflow=${1:-}
sha=${2:-}
[[ -n "$workflow" && -n "$sha" ]] || { printf 'Usage: %s <workflow-name> <commit-sha>\n' "$0" >&2; exit 2; }

grace=300

while :; do
  id=$(gh run list --workflow "$workflow" --commit "$sha" --limit 1 --json databaseId \
    --jq '.[0].databaseId' 2>/dev/null)
  [[ -n "${id:-}" && "$id" != "null" ]] && break
  if (( SECONDS > grace )); then
    printf 'No %s run registered for %s within %ss.\n' "$workflow" "$sha" "$grace" >&2
    exit 2
  fi
  sleep 15
done

gh run watch "$id" --exit-status --interval 30
