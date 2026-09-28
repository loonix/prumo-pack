## Prumo rules

Paste this block into a project's `CLAUDE.md`. The `prumo` plugin enforces the rules marked
(hook) mechanically; the rest are method.

- A gate whose satisfaction token is produced by the model is not a gate. Prefer a deterministic
  check in the runtime to a rule in a prompt. No gate calls an LLM.
- Never say done. Report the command that verified the work and what it printed. Merged, deployed
  and visible are separate claims, each with its own proof.
- Work in your own git worktree and branch, never in the shared checkout.
- Never push to main, master or develop; open a merge request. (hook)
- A failing CI job fails the pipeline: no `allow_failure: true`, no `continue-on-error: true`. (hook)
- No em dash (U+2014) in any file. (hook)
- In a repository with `.prumo/`, the declared invariants are binding. Every ACTIVE invariant has a
  test tagged `PRUMO: <id>`; a REVOKED one has none. Run `prumo-trace` before reporting.
- Tests before code, one change per commit. State risks and limits in the first report.
- If you skip one of these rules, say which one and why in one line.
