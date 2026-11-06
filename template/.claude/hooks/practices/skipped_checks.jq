# From the python-service template: change the template, not this copy.
# STOP: a skipped check (a suppression such as `# noqa`) without its rule code, or without a reason
# in the form skipped-checks.md gives, after the directive or on the comment lines above it. The
# hook checks the form; review judges whether the reason holds. Reason places were checked against
# each tool: ruff, basedpyright and bandit honour text after the directive; `# fmt: skip` only
# behind a second `#`; `# fmt: off` only standing alone, so its reason goes on the comment lines
# above (same for `# pyright:` file directives).
include "lib";
include "python";

# The form to show for a line whose skipped check lacks its code or reason, or empty when it has
# both. given($directive): the line holds $directive, and the text after it or the comment lines
# above hold the reason.
def missing_reason($above):
  def given($directive):
    (capture($directive + "(?<reason>.*)$"; "i").reason // null) as $after
    | $after != null and (($after | reason_form) or ($above | reason_form));
  if has("#\\s*(ruff:\\s*)?noqa\\b") then
    if given("#\\s*(ruff:\\s*)?noqa:\\s*[a-z]+[0-9]+(\\s*,\\s*[a-z]+[0-9]+)*") then empty
    else "# noqa: <rule code> <reason>" end
  elif has("#\\s*type:\\s*ignore\\b") then
    if given("type:\\s*ignore\\[[^\\]]+\\]") then empty
    else "# type: ignore[<error code>] <reason>" end
  elif has("#\\s*pyright:\\s*ignore\\b") then
    if given("pyright:\\s*ignore\\[[^\\]]+\\]") then empty
    else "# pyright: ignore[<rule name>] <reason>" end
  elif has("^\\s*#\\s*pyright:") then
    if $above | reason_form then empty
    else "<reason> on the comment lines above the # pyright: directive" end
  elif has("#\\s*nosec\\b") then
    if given("nosec\\s+b[0-9]+(\\s*,\\s*b[0-9]+)*") then empty
    else "# nosec <test ID> <reason>" end
  elif has("#\\s*pragma:?\\s*no\\s*cover") then
    if given("no\\s*cover") then empty
    else "# pragma: no cover <reason>" end
  elif has("#\\s*fmt:\\s*skip\\b") then
    if given("fmt:\\s*skip\\s*(#|$)") then empty
    else "# fmt: skip  # <reason>  (the second # is required)" end
  elif has("#\\s*fmt:\\s*off\\b") then
    if has("^\\s*#\\s*fmt:\\s*off\\s*$") and ($above | reason_form) then empty
    else "<reason> on the comment lines above; # fmt: off must stand alone" end
  elif has("pytest\\.mark\\.(skip|skipif|xfail)\\b") then
    if has("reason\\s*=\\s*[rf]?[\"'][^\"']") and given("pytest\\.mark\\.(skip|skipif|xfail)\\b")
    then empty
    else "reason=\"<the outside condition that makes this test impossible here>\", and the"
      + " Tried sentences in a comment" end
  elif has("pytest\\.skip\\(") then
    if has("pytest\\.skip\\(\\s*(reason\\s*=\\s*)?[rf]?[\"'][^\"']") and given("pytest\\.skip\\(")
    then empty
    else "pytest.skip(\"<the outside condition that makes this test impossible here>\"), and"
      + " the Tried sentences in a comment" end
  else empty end;

def suppression:
  has("#\\s*(ruff:\\s*)?noqa\\b") or has("#\\s*type:\\s*ignore\\b") or has("#\\s*pyright:")
  or has("#\\s*nosec\\b") or has("#\\s*pragma:?\\s*no\\s*cover") or has("#\\s*fmt:\\s*(skip|off)\\b")
  or has("pytest\\.mark\\.(skip|skipif|xfail)\\b") or has("pytest\\.skip\\(");

def check($ctx):
  [$ctx.added[] | select(.line | suppression)
   | comment_above($ctx.new; .at) as $above | .line as $line
   | ($line | missing_reason($above)) as $form
   | "- `\($line | short)`\n  Write it in this form: \($form)"]
  | select(length > 0)
  | {level: "stop", text: ("Stopped by the practices hook, skipped-checks rule"
      + " (.claude/rules/skipped-checks.md). This edit skips a check without a reason in the"
      + " required form.\n" + reason_steps("skipping the check"; "the skipped check"; checkers)
      + "The reason goes after the directive and its rule code, on the same line. When that line"
      + " would pass 100 columns, it goes on the comment lines directly above, and the line keeps"
      + " only the directive. `# fmt: off` and `# pyright:` file directives must stand alone, so"
      + " their reason always goes above.\n" + join("\n"))};
