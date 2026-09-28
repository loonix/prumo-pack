# Execution contracts

Behavioral contracts for agents and automated jobs that act on this repository or its systems:
what they may do, what they must refuse, and the deterministic gate that enforces it. A gate
whose satisfaction token is produced by the model is not a gate, so every contract here names a
check in the runtime or a structural invariant, never an instruction in a prompt.

One file per actor (`EXEC-<name>.md`), stating:

- the actor (agent, bot, scheduled job) and who owns it;
- allowed actions and resources, and the actions it must refuse;
- the enforcement point (runtime gate, permission, type, test) for each refusal, and the test
  that proves it bites, tagged `PRUMO: <id>` when it is a regression rule;
- contract constants (timeouts, limits, TTLs), pinned by a test to the values declared here;
- what happens when the gate is missing: the actor does not start.

Nothing in this directory is checked mechanically yet. It is a declaration a human reviews.
