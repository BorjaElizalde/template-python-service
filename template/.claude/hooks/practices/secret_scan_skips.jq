# From the python-service template: change the template, not this copy.
# STOP: a skip of the secret scan without a reason in the form the rules give. gitleaks skips
# a finding whose line holds `gitleaks:allow`, in a file of any type; one whose fingerprint the
# root .gitleaksignore lists; and one the root .gitleaks.toml allowlists or whose rule it disables.
# A .gitleaks.toml without `useDefault = true` drops gitleaks's own rules. The hook checks the
# form; review judges whether the reason holds.
include "lib";
include "python";
include "config_entries";

# gitleaks reads `gitleaks:allow` only on the finding's own line, and the text after it there.
def allow_reasoned($ctx):
  (.line | capture("gitleaks:allow(?<after>.*)$").after | reason_form)
  or (comment_above($ctx.new; .at) | reason_form);

def allow_findings($ctx):
  $ctx.added[] | select(.line | test("gitleaks:allow")) | select(allow_reasoned($ctx) | not)
  | "- `\(.line | short)`\n  Write it in this form: gitleaks:allow <reason>";

# gitleaks reads the whole line as the fingerprint, so a reason after it breaks the entry.
def fingerprint_findings($ctx):
  $ctx.added[] | select(.line | test("^\\s*(#|$)") | not)
  | select(comment_above($ctx.new; .at) | reason_form | not)
  | "- added `\(.line | short)`";

def skip_key: has("(^|\\.)(commits|paths|regexes|stopwords|disabledrules)$");
def holds_value: (test("^\\s*#") | not) and test("[\"']");
# gitleaks reads useDefault only under [extend], or as extend.useDefault outside any table.
def sets_use_default:
  any(annotate[];
    ((.section | has("^\\s*\\[extend\\]")) and (.line | has("^\\s*usedefault\\s*=\\s*true\\b")))
    or (.section == "" and (.line | has("^\\s*extend\\.usedefault\\s*=\\s*true\\b"))));

# gitleaks reads its own rules when .gitleaks.toml is missing, or sets useDefault under [extend].
def drops_own_rules($ctx):
  (($ctx.old | length == 0) or ($ctx.old | sets_use_default))
  and ($ctx.new | sets_use_default | not);

def config_findings($ctx):
  ($ctx.new | annotate) as $notes
  | ($ctx.added[] | .at as $at | $notes[$at]
     | select((.key | skip_key) and (.line | holds_value))
     | {text: "added `\(.line | short)`", at: $at}),
    (if drops_own_rules($ctx) then
       {text: ("left out `useDefault = true` under `[extend]`: gitleaks then drops its own rules"
         + " and reads only this file's. Add it, or add the reason as a comment"), at: null}
     else empty end)
  | select(entry_reasoned($ctx) | not) | "- \(.text)";

def check($ctx):
  [allow_findings($ctx),
   if $ctx.rel == ".gitleaksignore" then fingerprint_findings($ctx)
   elif $ctx.rel == ".gitleaks.toml" then config_findings($ctx)
   else empty end]
  | select(length > 0)
  | {level: "stop", text: ("Stopped by the practices hook, skipped-checks rule"
      + " (in .claude/rules/). This edit skips a finding of the secret scan,"
      + " gitleaks, without a reason in the required form. A skip hides a real secret as well as a"
      + " false one: revoke a real secret and take it out of the code instead.\n"
      + reason_steps("skipping the finding"; "the skip"; "gitleaks")
      + "The reason goes after `gitleaks:allow`, on the same line: gitleaks reads it only on the"
      + " finding's own line. When that line would pass 100 columns, the reason goes on the `#`"
      + " comment lines directly above. In .gitleaks.toml, it goes in a comment on the entry's"
      + " line or on the comment lines directly above it. In .gitleaksignore, it goes on the"
      + " comment lines directly above the fingerprint: gitleaks reads the whole line as the"
      + " fingerprint.\n"
      + join("\n"))};
