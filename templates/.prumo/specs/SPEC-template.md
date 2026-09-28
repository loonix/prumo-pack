# SPEC-NNN: <deliverable name>

Copy this file to `SPEC-NNN-<slug>.md`, one per deliverable (Layer 9). If a mandatory field is
empty, execution does not start. Write "none" where a field truly has nothing, so an empty
field always means "not answered yet".

## Goal (mandatory)

Universe (Business, User, Product, Engineering, Quality, Performance, Security, Compliance,
Operational or Data), the measurable success criterion, and the human who declares it met.

## Deliverable (mandatory)

Kind (Functional, Technical, Quality, Data, Operational or Compliance), owner, and what is
observable when it exists.

## Verification (mandatory)

Automated: the command or job, and what makes it pass or fail.
Manual: who checks, what, and when.

## Assumptions (mandatory)

One line each, typed Context, Data, State or Business, with the evidence behind it and its
class (direct observation, expert testimony, documentation, inference).

## Expectations (mandatory)

One line each, typed Functional, State, Boundary, Negative or Performance. Boundary
expectations get an id and a test tagged `PRUMO: <id>`.

## Edge cases

One line each, typed Boundary, Null, Concurrent, Degraded, State transition or Permission,
naming the assumption or expectation it points at.

## Regression rules touched

Ids from `../regression-rules/` this deliverable relies on, adds or revokes.

## Environment

Reference to the contract in `../environment-contracts/` the verification runs in.

## Out of scope

What this deliverable does not do.
