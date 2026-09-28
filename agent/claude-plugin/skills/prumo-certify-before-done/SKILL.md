---
name: prumo-certify-before-done
description: Use before reporting any task as finished, fixed, merged, deployed or working. Replaces "done" with what a verifier printed, and keeps merged, deployed and visible apart.
---

# Certify before done

"Done" is the human's word. You report what was measured and what measured it.

## Rules

1. **Never write "done", "fixed", "works" or "ready" on your own authority.** Write the
   command you ran and what it printed: `make test: 147 passed, 0 failed`.
2. **A claim needs a verifier that is not you.** A test runner, a CI job, an HTTP status, a
   rendered page, a row in a database. Your own summary of your own work is not evidence.
3. **Merged is not deployed is not visible.** Each is a separate claim with its own proof:
   - merged: the commit is on the target branch (`git branch -r --contains <sha>`);
   - deployed: the running artefact carries that commit (version endpoint, image tag, file hash);
   - visible: the user-facing surface shows the change (fetched page, screenshot, API response).
   Stop at the highest level you actually checked and name it.
4. **Classify the evidence.** Something you observed directly beats documentation, which beats
   inference. Inference alone does not support "it works in production".
5. **Report what was not checked.** Skipped tests, untested paths and known limits go in the
   first report, not after someone asks.

## Report shape

```
Measured: <command> -> <output that matters>
Level reached: merged | deployed | visible
Not checked: <what and why>
```
