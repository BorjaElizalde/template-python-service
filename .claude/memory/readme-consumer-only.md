---
name: readme-consumer-only
description: This repository's README says only what a project does to apply, update and extend the template, never how a template file works inside
metadata:
  type: feedback
---

The README tells a project how to consume and leverage the template: what to run, what to edit, what to delete. It does not explain how a template file works inside.

**Why:** The owner, on 2026-11-18, about a README bullet that explained the make include chain, how `make help` reads descriptions and what make warns on a second recipe: "readme should only talk about how to consume and leverage the repo", and the bullet was "unnecessary details about the makefile". An issue's solved-list had asked for a README statement, and the bullet held far more than it asked.

**How to apply:** When an issue asks for a README change, write the one action the project takes, in the section that already covers that moment, and stop. How a file works goes in that file's header comment. My reading, not the owner's words: this holds for every template file, not only the make fragments.
