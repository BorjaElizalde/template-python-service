# From the python-service template: change the template, not this copy.
# STOP: an edit that switches a check off in the lint, type-check, test or pre-commit setup without
# a reason in the form skipped-checks.md gives. An added line's reason sits in its comment or on the
# comment lines above it; a removed line leaves no place, so the edit adds the reason as a comment.
# Tightening edits pass silently: a select entry is removed only if its code leaves the rule list,
# and a Makefile tool line only if no added line runs the same tool. A select added to a ruff config
# that extends another counts as switching checks off: ruff takes it as the whole rule list and
# drops the extended one; so does a removed extend line. Every edit to the shared base files stops,
# reason or not: each update rewrites them, so a change goes to the template. CI workflows are not
# checked here: the owner reviews CI changes in the PR, which only the owner merges.
include "lib";
include "python";

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

def ruff_file: test("(^|/)\\.?ruff\\.toml$");

def extends_ruff($ctx):
  any($ctx.new | annotate[]; .key == "extend"
    and ((.section | test("^\\s*\\[tool\\.ruff\\]")) or ($ctx.rel | ruff_file)));

# The opening line of a select, the one place a ruff rule list starts.
def opens_select($rel):
  (.line | test("^\\s*select\\s*="))
  and ((.section | test("^\\s*\\[(tool\\.ruff(\\.lint)?|lint)\\]\\s*$")) or (.section == "" and ($rel | ruff_file)));

# Each finding is {text, at}: `at` is an added line's index in the new file, null for a removed line.
def toml_findings($ctx):
  ($ctx.removed | line_set) as $removed
  | kept($ctx; "^(extend-)?select$") as $kept_rules
  | kept($ctx; "^(include|testpaths)$") as $kept_paths
  | kept($ctx; "^extends?$") as $kept_bases
  | ($ctx.new | annotate) as $notes
  | ($ctx.added[] | .at as $at | $notes[$at] | select(.section | checked_section($ctx.rel))
     | select(.line | test("^\\s*(#|\\[|$)") | not)
     | select((.section | test("per-file-ignores"))
         or (.key | test("^(extend-)?(ignore|exclude|force-exclude|omit|exclude_lines|exclude_also|norecursedirs|skips)$"))
         or (.line | has("^\\s*report\\w+\\s*=\\s*(false|\"(none|warning|information|hint)\")"))
         or (.line | has("typeCheckingMode\\s*=\\s*\"(off|basic)\"|check-typed-exception\\s*=\\s*false|--exit-zero"))
         or ((.key == "addopts") and (.line | has("-p\\s*no:|--deselect|\\s-k\\s|--ignore"))))
     | {text: "added `\(.line | short)`", at: $at}),
    ($ctx.old | annotate[] | select($removed[.line]) | select(.section | checked_section($ctx.rel))
     | select(((.key | test("^(extend-)?select$")) and (.line | dropped($kept_rules)))
         or ((.key | test("^(include|testpaths)$")) and (.line | dropped($kept_paths)))
         or ((.key | test("^extends?$")) and (.line | dropped($kept_bases)))
         or (.line | has("^\\s*report\\w+\\s*=\\s*(true|\"error\")|check-typed-exception\\s*=\\s*true")))
     | {text: "removed `\(.line | short)`", at: null}),
    (if extends_ruff($ctx) then
       $ctx.added[] | .at as $at | $notes[$at] | select(opens_select($ctx.rel))
       | {text: ("added `\(.line | short)`: in a config that extends another, select replaces its"
           + " whole rule list; extend-select adds to it"), at: $at}
     else empty end);

def precommit_findings($ctx):
  ($ctx.added[]
   | select(.line | has("^\\s*(exclude|files):|stages:.*manual|--exit-zero|--skip|--ignore|[\\s\\[\"]-s[\\s\",\\]]"))
   | {text: "added `\(.line | short)`", at}),
  ($ctx.removed[] | select(has("^\\s*-\\s*(id|repo):")) | {text: "removed `\(short)`", at: null});

def makefile_findings($ctx):
  ($ctx.added | map(.line)) as $added
  | ($ctx.added[] | select(.line | test("^\t-|\\|\\|\\s*true|--exit-zero"))
     | {text: "added `\(.line | short)`", at}),
    ($ctx.removed[]
     | select(
         (test("ruff|basedpyright|bandit|pytest") and (
           capture("(?<tool>ruff|basedpyright|bandit|pytest)") as $m
           | [$added[] | select(contains($m.tool))] | length == 0))
         or (test("^gate:") and (
           ([$added[] | select(test("^gate:"))][0] // "") as $gate
           | [split(" ")[1:][] | select(length > 0) | select(. as $w | $gate | split(" ") | index([$w]) | not)]
           | length > 0)))
     | {text: "removed `\(short)`", at: null});

# Whether a finding's reason is in the form: an added line's, in its comment or on the comment
# lines above it; a removed line's, in the comments the edit adds.
def reasoned($ctx; $added_comments):
  if .at == null then $added_comments | reason_form
  else [($ctx.new[.at] | comment // ""), comment_above($ctx.new; .at)] | any(reason_form) end;

def check($ctx):
  if $ctx.rel | test("(^|/)(ruff\\.base\\.toml|basedpyright\\.base\\.json)$") then
    {level: "stop", text: ("Stopped by the practices hook: \($ctx.rel) holds the settings every"
      + " Python service shares and comes from the python-service template. Every update rewrites"
      + " it, so an edit here is lost or conflicts. Change the template instead, or add this"
      + " project's own settings in pyproject.toml, which extends this file.")}
  else
    ([$ctx.added[].line | comment | select(. != null)] | join("\n")) as $added_comments
    | [if ($ctx.rel | test("(^|/)(pyproject\\.toml|\\.?ruff\\.toml)$")) then toml_findings($ctx)
       elif ($ctx.rel | test("(^|/)\\.pre-commit-config\\.yaml$")) then precommit_findings($ctx)
       elif ($ctx.rel | test("(^|/)Makefile$")) then makefile_findings($ctx)
       else empty end
       | select(reasoned($ctx; $added_comments) | not) | "- \(.text)"]
    | select(length > 0)
    | {level: "stop", text: ("Stopped by the practices hook, skipped-checks rule"
        + " (.claude/rules/skipped-checks.md). This edit may switch off a check in \($ctx.rel)"
        + " without a reason in the required form.\n"
        + reason_steps("switching the check off"; "the config change"; checkers)
        + "The reason goes in a comment on the entry's line, or on the comment lines directly above"
        + " it, as above a per-file-ignores entry; it starts with the rule code where there is one"
        + " (`# E402: ...`). For a removed entry, the edit adds the reason as a comment where the"
        + " entry was.\n" + join("\n"))}
  end;
