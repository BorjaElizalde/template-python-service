# From the python-service template: change the template, not this copy.
# REMIND: every new prose comment in Python, TOML, YAML and the Makefile
# (comments-and-docstrings.md), with one more line when it reads like history. A comment is new
# when its text was not in the file before: moving or re-indenting an old one is not new.
# Directives such as `# noqa` or `# fmt: off` are not prose, and neither is a `#` line inside a
# triple-quoted string (the MCP guides hold markdown headings).
include "lib";
include "python";

def triple_quotes: [match("\"\"\"|'''"; "g").string];

# For each line, whether it starts inside a triple-quoted string.
def in_string($lines):
  reduce $lines[] as $line ({open: null, inside: []};
    .inside += [.open != null]
    | if .open == null and ($line | test("^\\s*#")) then .
      else reduce ($line | triple_quotes[]) as $q (.;
        if .open == null then .open = $q elif .open == $q then .open = null else . end)
      end)
  | .inside;

# Words that tell what changed rather than what holds. Version-bound only where the word alone has
# ordinary uses ("since the lock is held", "a dropped connection").
def history_marker:
  (match("\\b(no longer|anymore|used to)\\b"
    + "|\\b(since|as of)\\s+v?\\d+\\.\\d+"
    + "|\\bv?\\d+\\.\\d+(\\.\\d+)*\\s+(dropped|removed|added|deprecated|renamed|changed)\\b"
    + "|\\b(dropped|removed|added|deprecated|renamed)\\s+in\\s+v?\\d+\\.\\d+"; "i") | .string)
  // null;

def check($ctx):
  ([$ctx.old[] | comment | select(. != null)] | line_set) as $old
  | in_string($ctx.new) as $inside
  | [$ctx.added[] | select($inside[.at] | not) | .line | comment
     | select(. != null) | select(plain_comment and ($old[.] | not))]
  | select(length > 0)
  | (first(.[] | history_marker | select(. != null) | [.]) // []) as $history
  | {level: "remind", text: ("Practices hook, comment rule"
      + " (.claude/rules/comments-and-docstrings.md). This edit adds a comment: `\(.[0] | short)`"
      + (if length > 1 then " (and \(length - 1) more)" else "" end) + "."
      + " This codebase keeps comments to a minimum: the code and its names should explain"
      + " themselves. Before keeping it, ask whether a clearer name or a simpler structure would"
      + " make it unnecessary, without hurting performance or the design; if so, change the code"
      + " instead. " + durability
      + " Keep a comment only if it tells the reader something they can't get from the"
      + " code and the project context: why the obvious approach is wrong here, an outside"
      + " constraint (how a provider, library or platform behaves), a safety, security or"
      + " data-integrity rule, a contract callers must respect, or the reason for a skipped check"
      + " or an except. If it restates the code, the history or the diff, delete it. Keep what"
      + " stays to one line, except a skipped check's reason, which takes the form"
      + " skipped-checks.md gives."
      + ($history | map("\nIt reads like history (`\(.)`): say what holds and why, not what"
          + " changed.") | add // ""))};
