# From the python-service template: change the template, not this copy.
# ASK the owner: an edit that switches a check off in the lint, type-check, test or pre-commit
# setup. Tightening edits pass silently: a select entry is removed only if its code leaves the
# rule list, and a Makefile tool line only if no added line runs the same tool. CI workflows are
# not checked here: the owner reviews CI changes in the PR, which only the owner merges.
include "lib";

# Each line with the TOML section and key it sits under (array items inherit the opening key).
def annotate:
  reduce .[] as $l ({section: "", key: "", out: []};
    if ($l | test("^\\s*\\[")) then .section = $l | .key = ""
    elif ($l | test("^\\s*[\"']?[A-Za-z0-9_.*/-]+[\"']?\\s*=")) then
      .key = ($l | capture("^\\s*[\"']?(?<k>[A-Za-z0-9_.*/-]+)").k)
    else . end
    | .out += [{line: $l, section, key}])
  | .out;

def checked_section($rel):
  ($rel | test("(^|/)\\.?ruff\\.toml$"))
  or test("^\\s*\\[tool\\.(ruff|basedpyright|pyright|coverage|pytest|bandit|mypy)");

def quoted: [scan("\"([^\"]+)\"") | .[0]];

# Quoted entries (rule codes, paths) the new file still lists under keys matching $re.
def kept($ctx; $re): [$ctx.new | annotate[] | select(.key | test($re)) | .line | quoted[]] | line_set;

def dropped($kept): [quoted[] | select($kept[.] | not)] | length > 0;

def toml_findings($ctx):
  ($ctx.added | map(.line) | line_set) as $added
  | ($ctx.removed | line_set) as $removed
  | kept($ctx; "^(extend-)?select$") as $kept_rules
  | kept($ctx; "^(include|testpaths)$") as $kept_paths
  | ($ctx.new | annotate[] | select($added[.line]) | select(.section | checked_section($ctx.rel))
     | select(.line | test("^\\s*(#|$)") | not)
     | select((.section | test("per-file-ignores"))
         or (.key | test("^(extend-)?(ignore|exclude|force-exclude|omit|exclude_lines|exclude_also|norecursedirs|skips)$"))
         or (.line | has("^\\s*report\\w+\\s*=\\s*(false|\"(none|warning|information|hint)\")"))
         or (.line | has("typeCheckingMode\\s*=\\s*\"(off|basic)\"|check-typed-exception\\s*=\\s*false|--exit-zero"))
         or ((.key == "addopts") and (.line | has("-p\\s*no:|--deselect|\\s-k\\s|--ignore"))))
     | "added `\(.line | short)`"),
    ($ctx.old | annotate[] | select($removed[.line]) | select(.section | checked_section($ctx.rel))
     | select(((.key | test("^(extend-)?select$")) and (.line | dropped($kept_rules)))
         or ((.key | test("^(include|testpaths)$")) and (.line | dropped($kept_paths)))
         or (.line | has("^\\s*report\\w+\\s*=\\s*(true|\"error\")|check-typed-exception\\s*=\\s*true")))
     | "removed `\(.line | short)`");

def precommit_findings($ctx):
  ($ctx.added[].line
   | select(has("^\\s*(exclude|files):|stages:.*manual|--exit-zero|--skip|--ignore|[\\s\\[\"]-s[\\s\",\\]]"))
   | "added `\(short)`"),
  ($ctx.removed[] | select(has("^\\s*-\\s*(id|repo):")) | "removed `\(short)`");

def makefile_findings($ctx):
  ($ctx.added | map(.line)) as $added
  | ($ctx.added[].line | select(test("^\t-|\\|\\|\\s*true|--exit-zero")) | "added `\(short)`"),
    ($ctx.removed[]
     | select(
         (test("ruff|basedpyright|bandit|pytest") and (
           capture("(?<tool>ruff|basedpyright|bandit|pytest)") as $m
           | [$added[] | select(contains($m.tool))] | length == 0))
         or (test("^gate:") and (
           ([$added[] | select(test("^gate:"))][0] // "") as $gate
           | [split(" ")[1:][] | select(length > 0) | select(. as $w | $gate | split(" ") | index([$w]) | not)]
           | length > 0)))
     | "removed `\(short)`");

def check($ctx):
  [if ($ctx.rel | test("(^|/)(pyproject\\.toml|\\.?ruff\\.toml)$")) then toml_findings($ctx)
   elif ($ctx.rel | test("(^|/)\\.pre-commit-config\\.yaml$")) then precommit_findings($ctx)
   elif ($ctx.rel | test("(^|/)Makefile$")) then makefile_findings($ctx)
   else empty end]
  | select(length > 0)
  | {level: "ask", text: ("Practices hook, config rule. This edit may switch off a check in"
      + " \($ctx.rel): \(.[0]). Loosening the lint, type-check, test or pre-commit setup is"
      + " the owner's call.")};
