# .prumo

This directory is the declared spec of this repository under Prumo, an engineering paradigm
for working with agents. What is declared here is binding: a declared invariant with no test is
worse than no invariant at all, because a revoked one becomes a guard that blocks the business
and an unimplemented one becomes a guarantee nobody enforces.

The loop: a human states an intention, the agent interrogates it until the spec is complete, the
agent executes, the machine verifies, the human decides. Verification is not a phase and not a
human chore: either the machine confirms or the merge does not happen. The agent never declares
a deliverable done; the right human for each goal does.

## Layer 1: Goals

Ten universes: Business, User, Product, Engineering, Quality, Performance, Security,
Compliance, Operational, Data. Each goal has a measurable success criterion, and the human who
owns that universe is the one who declares it met.

## Layer 2: Deliverables

The unit of work: observable, verifiable, atomic, owned, and linked to a goal. Six kinds:
Functional, Technical, Quality, Data, Operational, Compliance.

## Layer 3: Verification

Manual (who, what, when) or automated (why it passes or fails). Declared apart from the
deliverable, so the agent does not decide what is enough.

## Layer 4: Assumptions

What must be true for the spec to hold. Four kinds: Context, Data, State, Business. An
assumption that breaks in production is an incident, not a bug.

## Layer 5: Expectations

What the system does. Five kinds: Functional, State, Boundary, Negative, Performance.
Boundary expectations carry an id and do not exist until a test linked to that id passes. A
comment that mentions the id is not proof; only a passing test is.

## Layer 6: Edge cases

Six kinds: Boundary, Null, Concurrent, Degraded, State transition, Permission. Every edge case
points at a specific assumption or expectation. One that points at nothing is noise.

## Layer 7: Regression rules

Business invariants that hold across releases and are never violated. They come from real
incidents or absolute business rules, not from caution. A rule that can be negotiated under
deadline pressure is a guideline. Declared in `regression-rules/`, checked by `prumo-trace`.

## Layer 8: Environment contract

The execution environment is declared, not assumed, and reproducible (for example a Nix flake
with a default dev shell). A test that depends on the state of the runner is a bet, not a test.
Declared in `environment-contracts/`.

## Layer 9: Spec format

One template per deliverable. If a mandatory field is empty, the agent does not start. The
template is `specs/SPEC-template.md`.

## Files

| Path | What it holds | Checked by |
|---|---|---|
| `regression-rules/*.md` | Layer 7 invariants, one list line each | `prumo-trace` |
| `specs/` | Layer 9 specs, one per deliverable | review |
| `environment-contracts/` | Layer 8 environment declarations | review |
| `execution-contracts/` | Behavioral contracts for agents and automated jobs | review |
| `subsystems.yml` | Subsystems and how their usage is measured | `checks/metabolic.sh` |
| `fail-closed.patterns` | Project degradation phrases, one regex per line | `checks/fail-closed.sh` |

A gate whose satisfaction token is produced by the model is not a gate. Only the files marked
with a checker are enforced mechanically; the others are declarations a human reviews.
