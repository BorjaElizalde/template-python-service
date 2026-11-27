---
paths: ["**/.claude/**/*.{md,md.jinja}", "**/CLAUDE.md"]
---
# Writing

Agents write two kinds of text that others read. Published text is an issue, a comment that
briefs a task, a plan, a PR body or a commit message: people read it to decide what to build, to
review a change, and to learn later why the code is as it is. Instruction text is a `.md` file
under `.claude/` or a `CLAUDE.md`: Claude follows it, and the owner reads it to know what Claude
will do. Text that helps a model think is not the same as text that a person understands. Write
both kinds for a person to understand, in one pass: plain text serves Claude as well.

These rules do not govern how you think, plan or answer in chat. The step that writes a text says
what it holds; these rules say how to write it.

- Keep every fact, reason and doubt the text would hold without these rules. Less is more: cut
  words, never content.
- Go from the general to the detail: open with the main point, then order the rest by importance
  and impact. When the detail has parts, say in a sentence how they divide before giving them.
  Put the items of a list in that order too, the most important first. Where a step sets the
  order, as an issue's sections do, keep it, and use this order inside each part.
- Give the reason with the claim: what was done, or must be done, comes with why, never in a
  later section. Join a short reason or condition to its claim ("so that", "since", "unless",
  "whereas"), and put a long one in the next sentence.
- No mannered prose: say what you mean, with no metaphor or flourish in place of a direct
  statement. Write "a parameter worth varying", not "a dial worth turning"; "this point still
  matters", not "this point earns its keep". When a literal phrase exists, use it. Nor rhetorical
  patterns: a list of three for rhythm, "not X, but Y" to set up a reveal, a colon before a
  punchline, a fragment for emphasis, or a title that promises instead of saying what the text is.
- Use the common word: "use", not "leverage" or "utilize".
- Write each claim as a whole sentence, and keep sentences short. Split a sentence that a reader
  must read twice, but never into fragments.
- Make an abstract point concrete with one example, and say whether it is real or made up.
- Use the active voice, and name who or what acts.
- Use one term for one thing, and the same term each time.
- Be specific: give the number, the name or the `file:line`, not "some", "several" or "various".
- Say a doubt once, plainly, where it applies: "unverified", "I assume". Do not hedge what you
  know. When a claim rests on judgment rather than a check, say what it rests on: "I think",
  "in the runs I read".
- Leave out filler: no preamble, no summary of what the text already said, no praise of the
  change.
- In instruction text, say each rule once, in the file that does its step, and name that file
  from elsewhere. A file that loads in every session holds only what a session must do before any
  skill loads.
- In instruction text, read a script, a hook or a file before you state what it does.
