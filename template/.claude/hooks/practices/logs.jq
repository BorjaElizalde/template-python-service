# From the python-service template: change the template, not this copy.
# REMIND: a new log call outside tests/ (python-conventions.md, Logging). Where a log belongs is
# judgment no linter makes, so the question comes at the moment one is written. A call is new when
# its code, comment stripped, was not there before: moving or re-indenting one is not.
include "lib";
include "python";

def code: sub("\\s*#.*$"; "") | trimmed;

def check($ctx):
  ($ctx.removed | map(code) | line_set) as $old_code
  | [$ctx.added[].line
     | select(has("\\b(log|logger)\\.a?(debug|info|warning|error|exception|critical)\\("))
     | select($old_code[code] | not)]
  | select(($ctx.rel | outside_tests) and length > 0)
  | {level: "remind", text: ("Practices hook, logging rule (.claude/rules/python-conventions.md,"
      + " Logging). This edit adds a log call: `\(.[0] | short)`. This codebase logs only where an"
      + " operator would act, and every line costs money in the log store. Keep it only if it fires"
      + " once per event an operator would act on (a request's outcome, a batch run, a failure),"
      + " never per data item, and only if that outcome isn't already saved in the database or"
      + " returned to the caller.")};
