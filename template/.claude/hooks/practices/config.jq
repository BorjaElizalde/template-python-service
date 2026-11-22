# From the python-service template: change the template, not this copy.
# STOP: an edit that switches a check off in the lint, type-check, duplication, test or pre-commit
# setup without a reason in the form conventions.md gives. An added line's reason sits in its
# comment or on the comment lines above it; a removed line leaves no place, so the edit adds the
# reason as a comment.
# Tightening edits pass silently: a select entry is removed only if its code leaves the rule list,
# a Makefile tool line only if no added line runs the same tool, and a commit hook the edit adds
# may name its files or exclude. A select added to a ruff config that extends another counts as
# switching checks off: ruff takes it as the whole rule list and drops the extended one; so does a
# removed extend line. Every edit to the shared base files stops, reason or not: each update
# rewrites them, so a change goes to the template. Every edit to .bandit, [.]pytest.ini,
# [.]pytest.toml or [.]ruff.toml stops until it adds a reason on comment lines of their own: the
# gate's tools can read their settings there, and the hook does not read these files' entries.
# In a conftest.py, the statements that set collect_ignore or collect_ignore_glob are checked:
# pytest does not collect the paths they list. pre-commit.base.yaml is checked like
# .pre-commit-config.yaml instead, as the place a project switches a template hook off; a changed
# entry that runs pre-commit, such as template-hooks, can switch them off too. CI workflows are not
# checked here: the owner reviews CI changes in the PR, which only the owner merges.
include "lib";
include "python";
include "config_entries";

def checked_section: test("^\\s*\\[tool\\.(ruff|basedpyright|pyright|coverage|pytest|bandit|mypy)");

def quoted: [scan("\"([^\"]+)\"") | .[0]];

# Quoted entries (rule codes, paths) the new file still lists under keys matching $re.
def kept($ctx; $re): [$ctx.new | annotate[] | select(.key | test($re)) | .line | quoted[]] | line_set;

def dropped($kept): [quoted[] | select($kept[.] | not)] | length > 0;

def extends_ruff($ctx):
  any($ctx.new | annotate[]; .key == "extend" and (.section | test("^\\s*\\[tool\\.ruff\\]")));

# The opening line of a select, the one place a ruff rule list starts.
def opens_select:
  (.line | test("^\\s*select\\s*=")) and (.section | test("^\\s*\\[tool\\.ruff(\\.lint)?\\]\\s*$"));

# An addopts line that turns a pytest plugin off: a list item can hold `no:x` apart from its `-p`.
def plugin_off: has("-p\\s*no:|(^|[\\s\"'])no:");

def drops_tests: has("(^|[\\s\"'])-[km]|--deselect|--ignore");

# An addopts line under which pytest only collects the tests, or sets up or plans their fixtures.
def runs_no_test: has("--(co|collect-?only|setup-?(only|plan))\\b");

# Each finding is {text, at}: `at` is an added line's index in the new file, null for a removed line.
def pyproject_findings($ctx):
  ($ctx.removed | line_set) as $removed
  | kept($ctx; "^(extend-)?select$") as $kept_rules
  | kept($ctx; "^(include|testpaths)$") as $kept_paths
  | kept($ctx; "^extends?$") as $kept_bases
  | ($ctx.new | annotate) as $notes
  | ($ctx.added[] | .at as $at | $notes[$at] | select(.section | checked_section)
     | select(.line | test("^\\s*(#|\\[|$)") | not)
     | select((.section | test("per-file-ignores"))
         or (.key | test("^(extend-)?(ignore|exclude|force-exclude|omit|exclude_lines|exclude_also|norecursedirs|skips)$"))
         or (.line | has("^\\s*report\\w+\\s*=\\s*(false|\"(none|warning|information|hint)\")"))
         or (.line | has("typeCheckingMode\\s*=\\s*\"(off|basic|standard|strict)\""))
         or (.line | has("failOnWarnings\\s*=\\s*false|check-typed-exception\\s*=\\s*false|--exit-zero"))
         or ((.key == "addopts") and (.line | plugin_off or drops_tests or runs_no_test)))
     | {text: "added `\(.line | short)`", at: $at}),
    ($ctx.old | annotate[] | select($removed[.line]) | select(.section | checked_section)
     | select(((.key | test("^(extend-)?select$")) and (.line | dropped($kept_rules)))
         or ((.key | test("^(include|testpaths)$")) and (.line | dropped($kept_paths)))
         or ((.key | test("^extends?$")) and (.line | dropped($kept_bases)))
         or (.line | has("^\\s*report\\w+\\s*=\\s*(true|\"error\")|check-typed-exception\\s*=\\s*true")))
     | {text: "removed `\(.line | short)`", at: null}),
    (if extends_ruff($ctx) then
       $ctx.added[] | .at as $at | $notes[$at] | select(opens_select)
       | {text: ("added `\(.line | short)`: in a config that extends another, select replaces its"
           + " whole rule list; extend-select adds to it"), at: $at}
     else empty end);

# Whether new line $at narrows checks that were there before the edit: it is top-level, so it
# narrows every hook, or it sits in a hook whose `- id:` line the edit did not add.
def narrows_old_checks($ctx; $at):
  ([range(0; $at) | select($ctx.new[.] | test("^\\s*-\\s*id:"))] | last) as $id
  | ($ctx.new[$at] | test("^\\S")) or $id == null or all($ctx.added[]; .at != $id);

def precommit_findings($ctx):
  ($ctx.added[]
   | select(((.line | has("^\\s*(exclude|files):")) and narrows_old_checks($ctx; .at))
       or (.line | has("stages:.*manual|--exit-zero|--skip|--ignore|[\\s\\[\"]-s[\\s\",\\]]")))
   | {text: "added `\(.line | short)`", at}),
  ($ctx.removed[] | select(has("^\\s*-\\s*(id|repo):|pre-commit\\s+run")) | {text: "removed `\(short)`", at: null});

def makefile_findings($ctx):
  ($ctx.added | map(.line)) as $added
  | ($ctx.added[] | select(.line | test("^\t-|\\|\\|\\s*true|--exit-zero"))
     | {text: "added `\(.line | short)`", at}),
    ($ctx.removed[]
     | select(
         (test("ruff|basedpyright|bandit|pytest|jscpd") and (
           capture("(?<tool>ruff|basedpyright|bandit|pytest|jscpd)") as $m
           | [$added[] | select(contains($m.tool))] | length == 0))
         or (test("^gate:") and (
           ([$added[] | select(test("^gate:"))][0] // "") as $gate
           | [split(" ")[1:][] | select(length > 0) | select(. as $w | $gate | split(" ") | index([$w]) | not)]
           | length > 0)))
     | {text: "removed `\(short)`", at: null});

# The line indexes of each statement that sets collect_ignore or collect_ignore_glob, which list
# the paths pytest leaves out of collection: from the line that names one to the line that closes
# its brackets. Each form that adds a path starts its statement with the name.
def ignore_statements($lines):
  def open_brackets: (gsub("[^\\[({]"; "") | length) - (gsub("[^\\])}]"; "") | length);
  reduce range(0; $lines | length) as $at ({depth: 0, out: []};
    ($lines[$at] | unquoted_code) as $code
    | if .depth > 0 then .out[-1] += [$at] | .depth += ($code | open_brackets)
      elif $code | test("^\\s*collect_ignore(_glob)?\\b") then
        .out += [[$at]] | .depth = ($code | open_brackets)
      else . end)
  | .out;

# A statement whose first line the edit adds gives one reason, on that line or above it; an entry
# added to an older statement gives its own. A comment or a closing bracket needs none.
def conftest_findings($ctx):
  [$ctx.added[].at] as $added
  | ignore_statements($ctx.new)[]
  | if .[0] | IN($added[]) then .[0] else .[1:][] | select(IN($added[])) end
  | select($ctx.new[.] | unquoted_code | test("[\\w\"']"))
  | {text: "added `\($ctx.new[.] | short)`", at: .};

def reason_on_own_lines($ctx): [$ctx.added[].line | select(test("^\\s*#"))] | join("\n") | reason_form;

def check($ctx):
  if $ctx.rel | test("(^|/)(ruff\\.base\\.toml|basedpyright\\.base\\.json|\\.jscpd\\.json)$") then
    {level: "stop", text: ("Stopped by the practices hook: \($ctx.rel) holds the settings every"
      + " Python service shares and comes from the python-service template. Every update rewrites"
      + " it, so an edit here is lost or conflicts. Change the template instead"
      + (if $ctx.rel | endswith(".jscpd.json") then
           ". A copy that must stay goes between `# jscpd:ignore-start` and `# jscpd:ignore-end`,"
           + " with its reason (.claude/rules/skipped-checks.md)."
         else ", or add this project's own settings in pyproject.toml, which extends this file." end))}
  elif $ctx.rel | test("(^|/)(\\.bandit|\\.?pytest\\.(ini|toml)|\\.?ruff\\.toml)$") then
    select(reason_on_own_lines($ctx) | not)
    | {level: "stop", text: ("Stopped by the practices hook, skipped-checks rule"
        + " (.claude/rules/skipped-checks.md). The gate's bandit, pytest or ruff can read its"
        + " settings from \($ctx.rel), and pytest and ruff then ignore those in pyproject.toml. The"
        + " hook does not check this file's entries, so every edit here stops until it adds a"
        + " reason in the required form.\n"
        + reason_steps("changing \($ctx.rel)"; "the change"; checkers)
        + "The reason goes on `#` comment lines of their own that the edit adds, and starts with"
        + " the rule code where there is one (`# B101: ...`): bandit and pytest read a `#` after"
        + " an INI entry as part of its value.")}
  else
    [if ($ctx.rel | test("(^|/)pyproject\\.toml$")) then pyproject_findings($ctx)
     elif ($ctx.rel | test("(^|/)(\\.pre-commit-config|pre-commit\\.base)\\.yaml$")) then precommit_findings($ctx)
     elif ($ctx.rel | test("(^|/)Makefile$")) then makefile_findings($ctx)
     elif ($ctx.rel | test("(^|/)conftest\\.py$")) then conftest_findings($ctx)
     else empty end
     | select(entry_reasoned($ctx) | not) | "- \(.text)"]
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
