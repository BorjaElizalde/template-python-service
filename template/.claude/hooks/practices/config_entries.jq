# From the python-service template: change the template, not a project's copy.
# Helpers for the modules that check a config's entries, which include it after lib.jq and
# python.jq: what each TOML line sits under, and whether an entry's reason is in the form.
include "lib";
include "python";

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
