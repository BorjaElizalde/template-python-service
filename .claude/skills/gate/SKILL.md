---
name: gate
description: Use when full validation (`make gate`) is required or a current-session green gate may still apply.
---

## Gate

1. Run `bash "${CLAUDE_SKILL_DIR}/scripts/run-gate.sh" --fingerprint`.
2. Reuse a successful `/gate` result only when it is in the current session and its
   fingerprint exactly matches. Report the reuse.
3. Otherwise run `bash "${CLAUDE_SKILL_DIR}/scripts/run-gate.sh"`. Record the successful
   fingerprint. On failure, use the compact output first and read the retained log only when
   needed.
4. Return PASS or FAIL, the fingerprint, whether the gate ran or was reused, and the failure log
   path when applicable.
