# From the python-service template: change the template, not this copy.
# STOP: a new test that goes through no boundary, or that calls a write endpoint and does not use
# `db_session` after it (testing.md); REMIND on the others. A test is new when its name was not in
# the file before: moving, re-indenting or editing one is not new. Its text runs from the def to
# the next line indented no deeper. The contract and shipped-data checks below are the only tests
# that need no boundary; adding a place to that list is a reviewed change.
# A project with no boundary, from a part it picked or from its test_boundaries answer, gets no
# test check.
include "lib";
include "python";
import "stack" as $stack;

def contract_checks:
  test("^tests/(contracts|config_integrity" + when_picked("database"; "|migrations") + ")/");

def test_file: test("^tests/(.+/)?test_[^/]+\\.py$");
def test_name: capture("^\\s*(async\\s+)?def\\s+(?<name>test_\\w+)").name;
def indent: match("^\\s*").length;

# Each part's boundaries: the calls a test makes through them, and the names a stop gives them.
def part_boundaries: {
  api: {names: ["an endpoint", "an MCP tool"],
        calls: ["^\\s*def\\s+test_\\w+\\([^)]*\\bclient\\b", "\\bTestClient\\(",
                "\\bclient\\.(get|post|put|patch|delete|request|options|head)\\(",
                "\\bcall_tool\\("]},
  batch: {names: ["a batch task", "the batch CLI"],
          calls: ["\\btask_[a-z0-9_]+\\(", "\\bCliRunner\\("]}
};

# The project's boundaries: its parts', then those its test_boundaries answer names.
def boundaries:
  [$stack[0].parts[] | part_boundaries[.] // empty]
  + [($stack[0].boundaries // [])[] | {names: ["`\(.)`"], calls: ["\\b" + gsub("[.]"; "\\.") + "\\("]}];

def either: if length > 1 then (.[:-1] | join(", ")) + " or " + .[-1] else .[0] end;

# Any `db_session` use after the first write call counts, so a read inside a helper passes; a write
# made inside a helper is not seen.
def write_without_db_read:
  (first(match("\\bclient\\.(post|put|patch|delete)\\(")) // null) as $write
  | $write != null and (.[$write.offset + $write.length:] | test("\\bdb_session\\b") | not);

def bullets: map("- `\(.)`") | join("\n");

# A closing bracket at the def's own indentation still belongs to its signature.
def test_text($new; $at):
  ($new[$at] | indent) as $depth
  | (first(range($at + 1; $new | length)
           | select(($new[.] | trimmed) as $line | $line != "" and ($line | test("^[)\\]]") | not)
                    and ($new[.] | indent) <= $depth))
     // ($new | length)) as $end
  | $new[$at:$end] | join("\n");

def check($ctx):
  boundaries as $boundaries
  | select(($boundaries | length) > 0)
  | select(($ctx.rel | test_file) and ($ctx.rel | contract_checks | not))
  | ($boundaries | map(.calls[]) | join("|")) as $calls
  | (picked("api") and picked("database")) as $write_check
  | ([$ctx.old[] | test_name] | line_set) as $old_names
  | [$ctx.added[] | (.line | test_name) as $name | select($old_names[$name] | not)
     | test_text($ctx.new; .at) as $text
     | {name: $name, boundary: ($text | test($calls)),
        unread: ($write_check and ($text | write_without_db_read))}]
  | select(length > 0)
  | map(select(.boundary | not) | .name) as $direct
  | map(select(.unread) | .name) as $unread
  | if ($direct + $unread | length) > 0 then
      ($direct | select(length > 0)
       | {level: "stop", text: ("Stopped by the practices hook, test rule (.claude/rules/testing.md)."
           + " This test calls the code directly:\n" + bullets
           + "\nTests here build the case's data" + when_picked("database"; " with `mock_*`")
           + ", call a boundary (" + ($boundaries | map(.names[]) | either) + "), and check the"
           + " result. To reach a branch, give data that makes the boundary reach it. If no data"
           + " can, the branch is dead code: tell the owner instead of testing it.")}),
      ($unread | select(length > 0)
       | {level: "stop", text: ("Stopped by the practices hook, the database part's test rule."
           + " This test calls a write endpoint and does not read the database after it:\n" + bullets
           + "\nAfter a write, call `db_session.expire_all()`, read the rows through `db_session` and"
           + " check the specific changed result. After a refused write, check that nothing changed"
           + " in the database. A read checks the response against the mock data. A GET after the"
           + " write is not the check: it shows only what the API exposes.")})
    else
      {level: "remind", text: ("Practices hook, test rule (.claude/rules/testing.md). This edit adds"
        + " a test: `\(.[0].name)`. Check it follows the three steps: the case's data built"
        + when_picked("database"; " with `mock_*`") + ", the boundary called, then the check"
        + when_picked("database"; ": a write reads the changed rows through `db_session`, a refused"
            + " write shows nothing changed, a read checks the response against the mock data")
        + ". Never check how the code got there. Keep it only if no other test already covers that"
        + " case.")}
    end;
