# From the python-service template: change the template, not this copy.
# STOP: a new except in the package that does not say why it earns its keep; REMIND on one that
# does (python-conventions.md, Error Handling). The reason is a comment on the except line or a
# plain comment directly above or below it; whether it holds is the reader's call, not the hook's.
# An except is new when its code, comment stripped, was not there before: moving, re-indenting or
# annotating an old one is not new.
include "lib";
include "python";

def code: sub("\\s*#.*$"; "");

def reasoned($new; $at):
  ($new[$at] | test("#\\s*\\S"))
  or ($at > 0 and ($new[$at - 1] | plain_comment))
  or (($new[$at + 1] // "") | plain_comment);

def check($ctx):
  ($ctx.removed | map(code) | line_set) as $old_code
  | [$ctx.added[] | select(.line | has("^\\s*except\\b")) | select($old_code[.line | code] | not)]
  | select(($ctx.rel | in_package) and length > 0)
  | map(select(reasoned($ctx.new; .at) | not) | .line) as $bare
  | if ($bare | length) > 0 then
      {level: "stop", text: ("Stopped by the practices hook, except rule"
        + " (.claude/rules/python-conventions.md, Error Handling). This edit adds an except without"
        + " saying why it earns its keep:\n" + ($bare | map("- `\(short)`") | join("\n"))
        + "\nErrors propagate to the boundary in this codebase; an except stays only when it"
        + " handles a failure that can really happen better than the boundary would. Add a"
        + " one-line comment on the except line, or directly above or below it, naming that"
        + " failure and why handling it here beats the boundary. If no such sentence holds, remove"
        + " the except and let the error propagate.")}
    else
      {level: "remind", text: ("Practices hook, except rule (.claude/rules/python-conventions.md,"
        + " Error Handling). This edit adds an except: `\(.[0].line | short)`. Errors propagate to"
        + " the boundary in this codebase. Keep it only if its comment holds: the failure can"
        + " really happen here (bad user input, a provider or network error, a race), not a case"
        + " our own code already rules out (input a model has validated, a value the database"
        + " forbids, data another of our services always produces), and the handler does better"
        + " than the boundary (a clearer API error, one item failing without stopping the rest, a"
        + " fallback that is the intended behaviour).")}
    end;
