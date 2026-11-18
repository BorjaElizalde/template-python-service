## Code style

- Adapt to the existing code: before you extend a module, and above all before you create a file,
  read similar files beside it and match their structure, naming and idiom. Comment density is
  not style to match: the rules below govern comments.

## Comments

- Before you write a comment or a docstring, ask whether a clearer name, a smaller function or a
  simpler structure would make it unnecessary, without hurting performance or the design; if so,
  change the code instead.
- Write a comment only to say why the obvious approach is wrong here, an outside constraint (how a
  provider, library or platform behaves), a safety, security or data-integrity rule or a contract
  callers must respect that the code does not show, or the reason for a skipped check. Inside the
  code, a comment is one line, except that reason, and it never restates the code.
- A file whose language has no docstring (shell, jq, YAML, a Makefile) may open with a comment
  that says what the file is for, the contract it keeps and how to run it, in as few lines as that
  takes, held to the same bar as any comment.
- A comment or docstring must still hold, and still make sense, for a reader a year from now who
  never saw today's change: say what holds, not what changed (no past bug, no version it moved
  from, no "now", "no longer", "since" or "used to").

## Skipped checks

- A skipped check is a comment or marker that tells a tool not to check a line or run a test. A
  loosened config does the same for more than a line: an ignore or exclude entry, a lower report
  level, an option that skips tests, or a change to the gate, a git hook or CI that stops a tool
  from running or from failing. A stack's own rule lists its directives and the tools whose docs
  to read.
- First check whether a skip or a loosened config is really the only way. Read the current
  documentation: the rule's page in the tool's docs and the docs of any library involved, since a
  newer version often adds a setting, an idiom or a typed API that makes the skip unnecessary.
  Then look for a cleaner approach: fix the code so the check passes, narrow the construct,
  restructure, or use the idiom the rule's docs give as its fix. If one works, use it.
- Keep the skip only if no approach leaves the project easier to maintain. Its reason then has
  three parts: the rule code where the tool has one, in the directive or at the start of a config
  entry's comment; why this is right here and the most maintainable option, answering what a
  reader of the line would ask, never why the tool flags it; and one `Tried <alternative>, but
  <why it was discarded>.` sentence per alternative, the rule's documented fix among them.
- The reason goes after the directive, on the same line. When that line would pass the project's
  line length, or the directive must stand alone on its line, the reason goes on the comment lines
  directly above, and the line keeps only the directive. A config entry's reason goes on its line
  or the comment lines above it; when the loosening removes a line, in a comment where it was.
