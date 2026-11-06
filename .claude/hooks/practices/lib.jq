# From the agentic template: change the template, not this copy.
# Shared by every practice module: what one edit changes, plus text helpers.
# Whole-file set difference on trimmed lines, not a diff: a line that only moves or changes
# indentation is neither added nor removed, so refactoring old code never re-judges it.

def lines: split("\n");

# The file as the edit will leave it. $old_file is the content on disk ("" for a new file).
def new_file($old_file):
  .tool_input as $t
  | if ($t.content | type) == "string" then $t.content
    elif ($t.edits | type) == "array" then
      reduce $t.edits[] as $e ($old_file; split($e.old_string) | join($e.new_string))
    elif ($t.old_string // "") == "" then $t.new_string // ""
    else $old_file | split($t.old_string) | join($t.new_string // "")
    end;

def line_set: reduce .[] as $line ({}; .[$line] = true);

def trimmed: sub("^\\s+"; "") | sub("\\s+$"; "");

# The context every module's check($ctx) reads: {rel, old, new, added: [{line, at}], removed};
# `at` is the line's index in `new`.
def edit_context($old_file; $rel):
  ($old_file | lines) as $old
  | (new_file($old_file) | lines) as $new
  | ($old | map(trimmed) | line_set) as $old_set
  | ($new | map(trimmed) | line_set) as $new_set
  | {
      rel: $rel, old: $old, new: $new,
      added: [range(0; $new | length) as $i | select($old_set[$new[$i] | trimmed] | not)
              | {line: $new[$i], at: $i}],
      removed: [$old[] | select(trimmed as $line | $new_set[$line] | not)]
    };

def has($re): test($re; "i");
def short: sub("^\\s+"; "") | if length > 90 then .[:87] + "..." else . end;
def durability:
  "Will it still be true, and still make sense, in a year, to a reader who never saw today's"
  + " change? Say what holds, not what changed: no versions it moved from, no past bugs, no"
  + " \"now\", \"no longer\", \"since\" or \"used to\".";

# Whether a text holds a reason in the form the stack's skipped-checks rule gives: why this is
# right here, then one "Tried <alternative>, but <why it was discarded>." per alternative. A Tried
# sentence starts the text or follows a full stop, a `#` or a line break.
def reason_form:
  [splits("(^|[.#\\n])\\s*tried\\s"; "i")] as $parts
  | ($parts | length) > 1 and ($parts[0] | has("[a-z]"))
    and all($parts[1:][]; has("\\bbut\\s+\\S"));

# Every stop for a skipped check or a loosened config opens with these steps, so the agent looks
# for a cleaner approach before it writes a reason. $doing names the skip, $it what it adds, and
# $tools the stack's checkers, whose docs the agent reads first.
def reason_steps($doing; $it; $tools):
  "First stop and check whether \($doing) is really the only way. Read the current documentation:"
  + " the rule's page in the tool's docs (\($tools)) and the docs of any library involved; a newer"
  + " version often adds a setting, an idiom or a typed API that makes the skip unnecessary. Then"
  + " look for a cleaner approach: fix the code so the check passes, narrow the construct,"
  + " restructure, or use the idiom the rule's docs give as its fix. If one works, use it and drop"
  + " \($it).\n"
  + "Keep \($it) only if no approach leaves the project easier to maintain. Its reason then says"
  + " why this is the most maintainable option and why each alternative was discarded, in this"
  + " form: <why this is right here>. Tried <alternative>, but <why it was discarded>. Write one"
  + " \"Tried ..., but ...\" sentence per alternative, the rule's documented fix among them. The"
  + " hook checks only this form; review judges whether the reason holds.\n";
