#!/usr/bin/env bash
# From the agentic template: change the template, not this copy.
# staleness.sh - deterministic memory-vs-code check.
#
# Scope is mechanical and exhaustive on purpose: does every cited path resolve, does every link
# land, is anything untracked, are there secrets. Judging whether a memory is USEFUL - fluff,
# duplication, whether it earns its place - belongs to memory-cleaner, which can read for
# meaning. A regex cannot.
#
# Usage: staleness.sh <store-dir> [<store-dir> ...]
# Exit: 0 = no hard findings, 1 = hard findings, 2 = bad usage

set -uo pipefail

fail=0
warn=0

strip_ref() {
  local r="${1%%:*}"
  r="$(printf '%s' "$r" | sed -E 's#[^A-Za-z0-9_/.-]+$##')"
  printf '%s' "${r%/}"
}

# The repository's own folders, read from what git tracks: a memory cites paths under the top-level
# ones, and may shorten `app/api/x.py` to `api/x.py` under a second-level one.
top_dirs() { git -C "$1" ls-files | sed -n 's#/.*##p' | sort -u; }
second_dirs() { git -C "$1" ls-files | awk -F/ 'NF > 2 { print $2 }' | sort -u; }
ere_alternation() { sed 's/[.[\*^$()+?{|]/\\&/g' | paste -sd '|' -; }

# The paths a note cites, one per line. A function, not a block inside the loop's <( ): bash 3.2
# can mis-parse such a block and then feed the loop nothing, so a broken extraction would read as a
# clean store; a function body is parsed with the script, so a fault stops the checker instead.
# Top-level folders count only at a path boundary: a sibling repository's paths are legitimately
# absent here, and without the leading guard `sibling/.github/…` would be chopped into a
# `.github/…` reference this repo does not have. Second-level segments also occur mid-path
# (`app/api/x.py`), and the same guard stops a substring being reported as its own reference.
cited_paths() {
  local f="$1" top_re="$2" second_re="$3"
  {
    [ -z "$top_re" ] || grep -oE "(^|[^A-Za-z0-9_/])($top_re)/[A-Za-z0-9_./-]+(:[0-9]+)?" "$f" | sed -E 's/^[^A-Za-z0-9_.]+//'
    [ -z "$second_re" ] || grep -oE "(^|[^A-Za-z0-9_/])($second_re)/[A-Za-z0-9_./-]*\.[A-Za-z0-9]+(:[0-9]+)?" "$f" | sed -E 's/^[^A-Za-z0-9_]+//'
  } | sort -u
}

resolve_path() {
  local repo="$1" c="$2" top
  [ -e "$repo/$c" ] && { printf '%s' "$c"; return; }
  grep -qxF -- "${c%%/*}" <<<"$TOP_DIRS" && { printf ''; return; }
  while IFS= read -r top; do
    [ -n "$top" ] && [ -e "$repo/$top/$c" ] && { printf '%s' "$top/$c"; return; }
  done <<<"$TOP_DIRS"
  printf ''
}

# One dialect, one vocabulary: every store writes the harness shape, a `metadata:` block with an
# indented `type:` drawn from the harness's four kinds. The agent-only spellings `memory_type:`,
# `navigation` and `maintainer-guidance` are gone. `navigation` in particular named the content that
# rotted fastest — a note defined by citing paths, symbols and line numbers is invalidated by every
# refactor and can be regenerated with one `rg`, so it cost more than it paid.
# The parser tolerates trailing whitespace and optional quotes: a value that visibly declares a type
# but fails to parse produces a hard finding naming the wrong problem, and blocks a commit.
topic_memory_type() {
  local v
  v="$(awk '
    /^metadata:[[:space:]]*$/ { inblock = 1; next }
    inblock && /^[^[:space:]]/ { exit }
    inblock && /^[[:space:]]+type:[[:space:]]*/ {
      sub(/^[[:space:]]+type:[[:space:]]*/, "")
      gsub(/["'"'"']/, ""); sub(/[[:space:]]+$/, "")
      print; exit
    }
  ' "$1")"
  case "$v" in
    user|feedback|project|reference) printf '%s' "$v" ;;
    *) printf '' ;;
  esac
}

# The trailing " — hook" is optional: agent stores write bare links, the harness writes hooked ones.
# Held in a variable: bash 5 reads backslash escapes in an inline [[ =~ ]] pattern differently from
# bash 3.2, and the inline form matches no index line on Linux.
RE_INDEX_LINK='^- \[[^]]+\]\([A-Za-z0-9_-]+\.md\)( — .*)?$'

check_index_shape() {
  local f="$1" hard_ref="$2" line n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    [ -z "$line" ] && continue
    [[ "$line" =~ ^# ]] && continue
    [[ "$line" =~ $RE_INDEX_LINK ]] && continue
    printf -v "$hard_ref" '%s  [index-detail] MEMORY.md:%s must be a heading, a blank line, or a bullet link optionally followed by " — hook"\n' "${!hard_ref}" "$n"
    fail=1
  done < "$f"
}

check_store() {
  local store="${1%/}"
  [ -d "$store" ] || { echo "SKIP (not a dir): $store"; return; }

  local repo branch topics lines status_line status path
  repo="$(git -C "$store" rev-parse --show-toplevel 2>/dev/null)" || {
    echo "SKIP (not in git): $store"
    return
  }
  branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  TOP_DIRS="$(top_dirs "$repo")"
  local top_re second_re
  top_re="$(ere_alternation <<<"$TOP_DIRS")"
  second_re="$(second_dirs "$repo" | ere_alternation)"

  echo "== store: $store"
  echo "   repo:  $repo  (branch: ${branch:-?})"

  if [ -f "$store/MEMORY.md" ]; then
    lines="$(wc -l < "$store/MEMORY.md" | tr -d ' ')"
    echo "   MEMORY.md: ${lines} lines (cap 200)"
    if [ "$lines" -gt 200 ]; then
      echo "   [BLOCKING] MEMORY.md exceeds 200 lines"
      fail=1
    fi
  fi

  topics="$(find "$store" -maxdepth 1 -name '*.md' ! -name 'MEMORY.md' | wc -l | tr -d ' ')"
  echo "   topic files: ${topics}"
  if [ "$topics" -gt 6 ]; then
    echo "   [pressure] more than 6 topic files; consider merging or dropping the weakest"
    warn=1
  fi

  while IFS= read -r status_line; do
    [ -n "$status_line" ] || continue
    status="${status_line:0:2}"
    path="${status_line:3}"
    if [[ "$status" == "??" && "$path" == *.md ]]; then
      echo "   [BLOCKING] untracked memory file: $path"
      fail=1
    fi
    # -uall, because git collapses a wholly-untracked directory to `?? <dir>/`, which fails the
    # *.md test above — so a brand-new agent store's notes would slip through entirely.
  done < <(git -C "$repo" status --short -uall -- "$store" 2>/dev/null)
  echo

  local f name hard adv p clean base parent hist elsewhere dirhit memory_type idx lk tok topic_lines
  for f in "$store"/*.md; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    hard=""
    adv=""

    if [ "$name" = "MEMORY.md" ]; then
      check_index_shape "$f" hard
    else
      memory_type="$(topic_memory_type "$f")"
      if [ -z "$memory_type" ]; then
        hard+="  [policy] topic must declare a metadata block with 'type: <t>', where <t> is one of user, feedback, project, reference"$'\n'
        fail=1
      fi

      topic_lines="$(wc -l < "$f" | tr -d ' ')"
      if [ "$topic_lines" -gt 50 ]; then
        adv+="  [size] $name is ${topic_lines} lines; a note this long is usually an inventory"$'\n'
        warn=1
      fi
    fi

    while IFS= read -r p; do
      [ -n "$p" ] || continue
      clean="$(strip_ref "$p")"
      [ -n "$clean" ] || continue
      [ -n "$(resolve_path "$repo" "$clean")" ] && continue

      base="$(basename "$clean")"
      if [[ "$base" != *.* ]]; then
        parent="$(dirname "$clean")"
        if [ -n "$(resolve_path "$repo" "$parent")" ]; then
          git -C "$repo" grep -qw -- "$base" 2>/dev/null \
            || adv+="  [symbol?]    $p  (parent dir exists; '$base' not found on branch)"$'\n'
          continue
        fi
      fi

      hist="$(git -C "$repo" log --oneline -1 -- "$clean" 2>/dev/null)"
      elsewhere="$(git -C "$repo" ls-files 2>/dev/null | grep -E "/${base}$" | head -1)"
      dirhit="$(git -C "$repo" ls-files 2>/dev/null | grep -E "/${base%.*}/" | head -1)"
      if [ -n "$elsewhere" ]; then
        hard+="  [moved?]     $p  -> maybe $elsewhere (re-point)"$'\n'
      elif [ -n "$dirhit" ]; then
        hard+="  [refactor?]  $p  -> looks split into ${base%.*}/ package (re-point)"$'\n'
      elif [ -n "$hist" ]; then
        hard+="  [deleted]    $p  (was on this branch, now removed; stale)"$'\n'
      else
        hard+="  [off-branch] $p  (not on this branch; re-point, rewrite, or delete)"$'\n'
      fi
      fail=1
    done < <(cited_paths "$f" "$top_re" "$second_re")

    while IFS= read -r lk; do
      [ -n "$lk" ] || continue
      [ -f "$store/$lk.md" ] && continue
      hard+="  [deadlink]   [[$lk]] (no $lk.md in store)"$'\n'
      fail=1
    done < <(grep -oE '\[\[[a-z0-9-]+\]\]' "$f" | sed -E 's/\[\[|\]\]//g' | sort -u)

    while IFS= read -r idx; do
      [ -n "$idx" ] || continue
      [ -f "$store/$idx" ] && continue
      hard+="  [deadindex]  ($idx) (index points to missing file)"$'\n'
      fail=1
    done < <(grep -oE '\]\([a-z0-9_-]+\.md\)' "$f" | sed -E 's/^\]\(|\)$//g' | sort -u)

    secret_shaped=0
    if grep -Eq '(AKIA[0-9A-Z]{16}|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)' "$f"; then
      hard+="  [SECRET]     possible secret/token value present; remove"$'\n'
      secret_shaped=1
      fail=1
    fi

    # [absent-sym] echoes each token VERBATIM, and a secret in a fresh memory is absent from the
    # branch by definition — so on a file that trips the secret check this loop would print the
    # secret the branch above deliberately withheld, into the agent transcript and the session log.
    # Report the file, never its tokens.
    if [ "$secret_shaped" -eq 0 ]; then
      while IFS= read -r tok; do
        [ -n "$tok" ] || continue
        git -C "$repo" grep -qw -- "$tok" 2>/dev/null && continue
        adv+="  [absent-sym] \`$tok\` (not found anywhere on branch; possibly stale)"$'\n'
      done < <(grep -oE '`[A-Za-z_][A-Za-z0-9_]{3,}' "$f" | tr -d '`' | sort -u | head -60)
    fi

    if [ -n "$hard$adv" ]; then
      echo "   x $name"
      [ -n "$hard" ] && printf "%s" "$hard"
      if [ -n "$adv" ]; then
        echo "     advisory:"
        printf "%s" "$adv"
      fi
    fi
  done
  echo
}

print_failure_guidance() {
  cat <<'EOF'

Memory findings are mechanical: a path, link, index entry, or type declaration that does not hold.
- Fix by re-pointing the reference, or by deleting the note if its subject is gone.
- Every topic needs a metadata block with 'type: <t>', where <t> is user, feedback, project, or reference.
- Re-run this checker after changes; hard findings mean the memory store is not clean.
- For whether a memory is worth keeping at all - useful, duplicated, true - run memory-cleaner.
EOF
}

[ $# -ge 1 ] || { echo "usage: $0 <store-dir> [<store-dir> ...]"; exit 2; }

for s in "$@"; do
  check_store "$s"
done

if [ "$fail" -eq 0 ]; then
  if [ "$warn" -eq 0 ]; then
    echo "RESULT: clean"
  else
    echo "RESULT: clean with pressure warnings"
  fi
else
  echo "RESULT: hard findings present"
  print_failure_guidance
fi

exit "$fail"
