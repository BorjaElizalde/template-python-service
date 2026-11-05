# From the python-service template: change the template, not this copy.
# STOP: a skipped check (a suppression such as `# noqa`) without its reason next to it; the agent
# adds the reason and retries. ASK: one with a reason goes to the owner, since only a person can
# judge whether the reason says why the code is right here (skipped-checks.md).
# In an unattended run the ask is a refusal. Reason forms were checked against each tool:
# ruff, basedpyright and bandit honour text after the directive; `# fmt: skip` only behind a
# second `#`; `# fmt: off` only standing alone, so its reason goes on the comment line above (same
# for `# pyright:` file directives).
include "lib";
include "python";

def reason: "\\s+#?\\s*[a-z]";

def missing_reason($above):
  if has("#\\s*(ruff:\\s*)?noqa\\b") then
    if has("#\\s*(ruff:\\s*)?noqa:\\s*[a-z]+[0-9]+(\\s*,\\s*[a-z]+[0-9]+)*" + reason) then empty
    else "# noqa: BLE001 <why nothing better>" end
  elif has("#\\s*type:\\s*ignore\\b") then
    if has("type:\\s*ignore\\[[^\\]]+\\]" + reason) then empty
    else "# type: ignore[assignment] <why nothing better>" end
  elif has("#\\s*pyright:\\s*ignore\\b") then
    if has("pyright:\\s*ignore\\[[^\\]]+\\]" + reason) then empty
    else "# pyright: ignore[reportAssignmentType] <why nothing better>" end
  elif has("^\\s*#\\s*pyright:") then
    if ($above | plain_comment) then empty
    else "# <why nothing better>  (on the line above the # pyright: directive)" end
  elif has("#\\s*nosec\\b") then
    if has("nosec\\s+b[0-9]+(\\s*,\\s*b[0-9]+)*" + reason) then empty
    else "# nosec B506 <why nothing better>" end
  elif has("#\\s*pragma:?\\s*no\\s*cover") then
    if has("no\\s*cover" + reason) then empty
    else "# pragma: no cover <why nothing better>" end
  elif has("#\\s*fmt:\\s*skip\\b") then
    if has("fmt:\\s*skip\\s+#\\s*[a-z]") then empty
    else "# fmt: skip  # <why nothing better>  (the second # is required)" end
  elif has("#\\s*fmt:\\s*off\\b") then
    if has("^\\s*#\\s*fmt:\\s*off\\s*$") and ($above | plain_comment) then empty
    else "# <why nothing better>  (on the line above; # fmt: off must stand alone)" end
  elif has("pytest\\.mark\\.(skip|skipif|xfail)\\b") then
    if has("reason\\s*=\\s*[rf]?[\"'][^\"']") then empty
    else "reason=\"<the outside condition that makes this test impossible here>\"" end
  elif has("pytest\\.skip\\(") then
    if has("pytest\\.skip\\(\\s*(reason\\s*=\\s*)?[rf]?[\"'][^\"']") then empty
    else "pytest.skip(\"<the outside condition that makes this test impossible here>\")" end
  else empty end;

def suppression:
  has("#\\s*(ruff:\\s*)?noqa\\b") or has("#\\s*type:\\s*ignore\\b") or has("#\\s*pyright:")
  or has("#\\s*nosec\\b") or has("#\\s*pragma:?\\s*no\\s*cover") or has("#\\s*fmt:\\s*(skip|off)\\b")
  or has("pytest\\.mark\\.(skip|skipif|xfail)\\b") or has("pytest\\.skip\\(");

# A standalone directive carries its reason on the comment line above, so the owner sees both.
def shown: if .line | has("^\\s*#\\s*(fmt:\\s*off|pyright:)") then "\(.above | short) / \(.line | short)"
  else .line | short end;

def check($ctx):
  [$ctx.added[] | select(.line | suppression)] as $found
  | [$found[] | .above as $a | .line as $l | ($l | missing_reason($a)) as $form
     | "- `\($l | short)`\n  Write it as: \($form)"] as $missing
  | if ($missing | length) > 0 then
      {level: "stop", text: ("Stopped by the practices hook, skipped-checks rule"
        + " (.claude/rules/skipped-checks.md). This edit skips a check without"
        + " saying why:\n" + ($missing | join("\n"))
        + "\nA skipped check is the last resort in this codebase: first narrow the construct,"
        + " restructure, or use the idiom the rule points to. If it really must stay, give the rule"
        + " code and, on the same line, a plain-English reason saying why the code is right here,"
        + " not why the tool flags it. `# fmt: off` and `# pyright:` file directives must stand"
        + " alone, so their reason goes on the comment line above.")}
    elif ($found | length) > 0 then
      {level: "ask", text: ("Practices hook, skipped-checks rule. This edit skips a lint or type"
        + " check. Approve only if each reason says, in plain English, why the code is right here,"
        + " not why the tool flags it:\n"
        + ($found | map("- `\(shown)`") | join("\n")))}
    else empty end;
