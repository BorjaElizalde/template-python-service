# From the python-service template: change the template, not this copy.
# Python helpers for the practice modules, which include it after lib.jq (jq includes do not pass
# on the definitions they bring in). stack.json, rendered from the template answers, names
# the application package.
include "lib";
import "stack" as $stack;

def package: $stack[0].package;
def outside_tests: startswith("tests/") | not;
def directive: "^\\s*#\\s*(fmt|noqa|type|pyright|nosec|pragma|ruff|jscpd|gitleaks:allow)\\b|^\\s*#!";
def plain_comment: has("^\\s*#\\s*[a-z0-9]") and (has(directive) | not);

# The tools whose docs a stop for a skipped check or a loosened config sends the agent to first.
def checkers: "ruff, basedpyright, bandit, pytest, jscpd";

# The line with its quoted text blanked, so a `#` or a bracket inside a string is not read as code.
def unquoted: gsub("\"(\\\\.|[^\"\\\\])*\"|'(\\\\.|[^'\\\\])*'"; "\"\"");

# The line's comment, from its `#` to the end, or null. Quoted text is blanked first so a `#`
# inside a string is not read as one; a line holding a triple quote has no trailing comment read.
# A `#` glued to the text before it is not a comment in YAML or in a shell recipe line
# (`url: https://x.test/#frag`).
def comment:
  if test("^\\s*#") then trimmed
  elif test("\"\"\"|'''") then null
  else unquoted
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

# Each TOML line with the section and key it sits under. The items of a multi-line array keep the
# key that opened it, so an item that holds `=` is not read as a new key.
def annotate:
  reduce .[] as $l ({section: "", key: "", open: false, out: []};
    ($l | unquoted | sub("#.*$"; "")) as $code
    | if .open then .open = ($code | test("\\]") | not)
      elif ($l | test("^\\s*\\[")) then .section = $l | .key = ""
      elif ($l | test("^\\s*[\"']?[A-Za-z0-9_.*/-]+[\"']?\\s*=")) then
        .key = ($l | capture("^\\s*[\"']?(?<k>[A-Za-z0-9_.*/-]+)").k)
        | .open = ($code | test("=\\s*\\[[^\\]]*$"))
      else . end
    | .out += [{line: $l, section, key}])
  | .out;

# Whether a config finding's reason is in the form: an added line's, in its comment or on the
# comment lines above it; a removed line's (`at` null), in the comments the edit adds.
def entry_reasoned($ctx):
  if .at == null then [$ctx.added[].line | comment | select(. != null)] | join("\n") | reason_form
  else [($ctx.new[.at] | comment // ""), comment_above($ctx.new; .at)] | any(reason_form) end;
