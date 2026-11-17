#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
# PreToolUse(Edit|Write|MultiEdit) coding-practice guard: one hook, one verdict per edit.
# The stack layer supplies registry.jq beside this script, the one plug-in point:
#   kind($path)              -> the file's kind, or null when no practice applies
#   practices($ctx; $kind)   -> a stream of {level, text} from its practice modules
# Each practice module exposes check($ctx) over the edit_context in lib.jq. The strongest level
# wins:
#   stop   -> exit 2, stderr to Claude, the edit is refused until fixed
#   remind -> additionalContext: the edit goes on through the normal permission flow and Claude
#             gets the short note next to its result
# No practice asks the owner: an unattended session counts a permission prompt as a refusal.
# Messages are short fixed text; the rules files are never loaded. jq only, no grep (ugrep shim,
# see bash-guard.sh). Fails OPEN without a registry, for files of no kind, outside a git repo, for
# git-ignored files, and on any jq error.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
[ -f "$HERE/registry.jq" ] || exit 0
PAYLOAD="$(cat)"
FILE_PATH="$(jq -r '.tool_input.file_path // empty' <<<"$PAYLOAD" 2>/dev/null || true)"
[ -n "$FILE_PATH" ] || exit 0
KIND="$(jq -nr -L "$HERE" --arg path "$FILE_PATH" 'import "registry" as registry; registry::kind($path) // empty' 2>/dev/null)"
[ -n "$KIND" ] || exit 0

# Nearest existing ancestor (a new file may sit in a not-yet-created dir), resolved physically so
# the repo-relative path survives symlinked prefixes such as macOS /var -> /private/var.
d="$(dirname "$FILE_PATH")"
while [ -n "$d" ] && [ "$d" != "/" ] && [ ! -d "$d" ]; do d="$(dirname "$d")"; done
[ -d "$d" ] || exit 0
TOP="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null)" || exit 0
git -C "$d" check-ignore -q -- "$FILE_PATH" 2>/dev/null && exit 0
REAL="$(cd "$d" && pwd -P)${FILE_PATH#"$d"}"
REL="${REAL#"$TOP"/}"
# The trailing x keeps the file's final newlines, which $(...) strips; an Edit whose old_string
# ends at one would otherwise match nothing.
OLD_FILE="$(cat -- "$FILE_PATH" 2>/dev/null; printf x)"
OLD_FILE="${OLD_FILE%x}"

VERDICT="$(jq -c -L "$HERE" --arg old_file "$OLD_FILE" --arg rel "$REL" --arg kind "$KIND" '
  include "lib";
  import "registry" as registry;

  edit_context($old_file; $rel) as $ctx
  | [registry::practices($ctx; $kind)]
  | {stop: map(select(.level == "stop") | .text), remind: map(select(.level == "remind") | .text)}
' <<<"$PAYLOAD" 2>/dev/null)" || exit 0

STOP="$(jq -r '.stop | join("\n\n")' <<<"$VERDICT")"
if [ -n "$STOP" ]; then
  echo "$STOP" >&2
  exit 2
fi

jq '
  select(.remind | length > 0)
  | {hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: (.remind | join("\n"))}}
' <<<"$VERDICT"
exit 0
