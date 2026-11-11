# From the python-service template: change the template, not this copy.
# Python helpers for the practice modules, which include it after lib.jq (jq includes do not pass
# on the definitions they bring in). stack.json, rendered from the template answers, names
# the application package.
include "lib";
import "stack" as $stack;

def package: $stack[0].package;
def outside_tests: startswith("tests/") | not;
def directive: "^\\s*#\\s*(fmt|noqa|type|pyright|nosec|pragma|ruff|jscpd)\\b|^\\s*#!";
def plain_comment: has("^\\s*#\\s*[a-z0-9]") and (has(directive) | not);

# The tools whose docs a stop for a skipped check or a loosened config sends the agent to first.
def checkers: "ruff, basedpyright, bandit, pytest, jscpd";

# The line's comment, from its `#` to the end, or null. Quoted text is blanked first so a `#`
# inside a string is not read as one; a line holding a triple quote has no trailing comment read.
# A `#` glued to the text before it is not a comment in YAML or in a shell recipe line
# (`url: https://x.test/#frag`).
def comment:
  if test("^\\s*#") then trimmed
  elif test("\"\"\"|'''") then null
  else gsub("\"(\\\\.|[^\"\\\\])*\"|'(\\\\.|[^'\\\\])*'"; "\"\"")
    | (capture("\\s(?<c>#.*)$") // {c: null}).c
    | if . == null then null else trimmed end
  end;

# The comment lines directly above line $at, without their `#`, one per line: where the reason
# for a skipped check or a loosened config goes when it does not fit on the line.
def comment_above($lines; $at):
  ($lines[:$at] | reverse) as $up
  | (first(range(0; $up | length) | select($up[.] | has("^\\s*#") and (has(directive) | not) | not))
     // ($up | length)) as $n
  | $up[:$n] | reverse | map(sub("^\\s*#\\s?"; "")) | join("\n");
