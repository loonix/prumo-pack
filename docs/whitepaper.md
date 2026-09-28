# Prumo: An Empirical Paradigm for AI-Native Software Engineering

**Full whitepaper: version 2.1 (chapters 1 to 8) with the version 2.2 supplement (chapter 9)**

Author: Daniel Carneiro. v2.1 updated June 2026, v2.2 updated July 2026.

> **About this edition.** Chapters 1 to 8 are a complete English translation of the canonical
> v2.1 knowledge base, not the short summary. Chapter 9 is the canonical v2.2 supplement. Two
> kinds of edits were made, both declared here:
>
> 1. **The rhetorical revisions mandated by section 9.6 are applied to chapters 1 to 8.**
>    "Cryptographic intersection" is written as what it is, an exact string match
>    intersection; "mathematically prove that the code works" is written as "mechanically
>    enforce that every declared boundary contract has a test proven non-hollow within the
>    tool's mutation space".
> 2. **Names of the projects, company and hosts where the evidence was gathered are replaced
>    by neutral names** (the lead marketplace API is "LeadNet", its contracts `BE-LEADNET-*`;
>    the operations agent's contracts are `BE-AGENT-*`). Numbers, dates, commits, iterations
>    and results are unchanged.

---

## Executive summary

The adoption of AI for code generation exposed a critical flaw in traditional development
methodologies (Agile, Lean, Waterfall): the **verification asymmetry**. AI generates code far
faster than humans can audit it rigorously, which produces hollow tests and false positives
in continuous integration.

**Prumo** is an AI-native operating paradigm built to close that asymmetry. It does not
propose a new way to write code. It proposes a new way to establish that code works: Boundary
Expectations (BEs) mechanically linked to the tests that verify them, and mutation testing
that proves those tests are not hollow. Prumo mechanically enforces that every declared
boundary contract has a test proven non-hollow within the tool's mutation space. If the
machine cannot show that an injected fault is killed, the code is rejected.

---

## 1. The Prumo paradigm

Prumo differs from Agile, Lean and Waterfall because **the AI does not execute the spec; the
AI builds the spec through interrogation.** Nothing exists until it is declared. Nothing runs
on implicit Assumptions.

The fundamental loop:

```
Human -> Intent -> AI interrogates -> Complete spec -> AI executes -> AI verifies -> Human decides
```

What sets Prumo apart from other methodologies: verification is not optional, it is not a
separate phase, and it is not a human responsibility. It is a mechanical contract. Either the
machine confirms, or the merge does not happen.

### 1.1 The 9 layers

**Layer 1: Goals (10 universes).**
Business, User, Product, Engineering, Quality, Performance, Security, Compliance, Operational,
Data. Every Goal has a measurable success criterion. The AI does not declare Done. The right
human for each universe declares it.

**Layer 2: Deliverables.**
A complete unit: observable, verifiable, atomic, owned, and linked to a Goal.
Six types: Functional, Technical, Quality, Data, Operational, Compliance.

**Layer 3: Verification.**
Manual (who, what, when) or automated (why it passes or fails). Kept separate from the
Deliverable: the AI does not decide what is sufficient.

**Layer 4: Assumptions.**
What must be true for the spec to be valid.
Four types: Context, Data, State, Business.
If an Assumption fails in production, that is an **Incident**, not a bug.
(Chapter 9, section 9.7, extends this layer with the Evidence Contract.)

**Layer 5: Expectations (Boundary Expectations).**
What the system does. Five types: Functional, State, Boundary, Negative, Performance.
Boundary Expectations (`BE-*`) have a special status, defined in chapter 2.

**Layer 6: Edge Cases.**
Six types: Boundary, Null, Concurrent, Degraded, State Transition, Permission.
Every edge case points to a specific Assumption or Expectation.
If you cannot say which one, it is not an edge case: it is noise.

**Layer 7: Regression Rules.**
Business invariants that can never be violated. Cross-release.
They are born from real incidents or from absolute business invariants, not from caution.
A Regression Rule is not optional because of urgency or a deadline. If it is negotiable, it is
a guideline.

**Layer 8: Environment Contract.**

> **DEFINITION: hermetic declarative cage.**
>
> The execution environment is declared, not assumed, and enclosed in a reproducible hermetic
> cage. Valid format: Nix flakes (`flake.nix` with `devShells.default`). A `requirements.txt`
> or an ad-hoc `Dockerfile` does not satisfy this layer.
>
> Any execution outside the cage (`nix develop --command ...`) invalidates the build.
> A test that depends on the state of the runner is not a test. It is a bet.

**Layer 9: Spec Format.**
A mandatory template per Deliverable. If any mandatory field is empty, the AI does not begin
execution.

### 1.2 Definition of Done by universe

| Universe | Done when |
|---|---|
| Business | the market confirms it: the Goal metric is moving |
| User | a real user completed the flow without assistance |
| Product | every Deliverable is Done and the experience was validated by hand |
| Engineering | tests pass, performance is within SLA, code review done, no Regression Rule violated, prumo-verify PASS, prumo-mutants 0 survivors for every BE |
| Quality | coverage reached, every edge case has a test, zero false positives |
| Performance | SLA verified under real load in staging with representative data |
| Security | validated by someone who did not write the code |
| Compliance | legal sign-off or external audit |
| Operational | deploy without incident, rollback tested, alerts firing |
| Data | event or metric verified in real production |

**The AI never declares Done. The right human for each universe declares it.**

---

## 2. The mechanical invariant: Boundary Expectations

### 2.1 Mandatory mechanical linkage

> **DEFINITION: mandatory mechanical linkage.**
>
> A BE declared in the spec **does not exist** until it is linked to the syntax tree of a test
> through a dedicated macro. The ID (for example `BE-LEADNET-02`) must be injected directly
> into the compiled identifier of the test, for example `#[prumo_expect("BE-LEADNET-02")]`.
>
> A BE counts as verified if and only if its ID appears in an event of type
> `{"type": "test", "event": "ok"}` in the JSON output of the test runner.
>
> **EXPLICIT REPUDIATION:** an ID in a comment, a docstring or a variable name **is not**
> verification. A comment `// BE-LEADNET-02` has no value as proof. Only the empirical PASSED
> counts.

### 2.2 prumo-verify (Layer 5 to CI)

Blocking flow:

```
.prumo/specs/*.md
  -> extract every BE-* ID by regex
  -> required_ids = { BE-LEADNET-01, BE-LEADNET-02, ... }
  -> cargo test --format=json > test-results.json
  -> verified_ids = { IDs with event "ok" in the JSON }
  -> missing = required_ids - verified_ids
  -> missing is empty     -> PRUMO PASS -> exit 0
  -> missing is not empty -> PRUMO FAIL -> list the missing IDs -> exit 1
```

The intersection is an exact string match between the declared IDs and the test runner's PASS
events. Nothing more: no signature, no hash.

### 2.3 prumo-mutants (Layer 5 to mortality)

prumo-mutants validates that the `#[prumo_expect]` tests are not hollow: that concrete
mutations exist which would be detected if the code were changed silently.

A test that passes with a correct contract **and** with a violated contract is not a test. It
is a linter that approves anything.

prumo-mutants blocks the merge if any viable mutant survives.

---

## 3. Empirical data: two sprints

### 3.1 Sprint Bags v1: infrastructure (June 2026)

First adoption of the paradigm. It established the infrastructure.

| Artifact | Time |
|---|---|
| `.prumo/specs/bags.md` (2 BEs) | ~5 min |
| `prumo_macros/src/lib.rs` (the linkage macro) | ~25 min |
| `bags_api/src/lib.rs` (logic and 3 annotated tests) | ~15 min |
| `scripts/prumo-verify.py` (the auditor) | ~10 min |
| `flake.nix` and `.gitlab-ci.yml` | ~15 min |
| **Total for 2 BEs end to end** | **~70 min** |

Conclusion: the overhead is dominated by infrastructure, not by the spec. Marginal cost of
further BEs in the same project: about 10 minutes per BE.

### 3.2 Sprint LeadNet v1: mortality proof (June 2026)

| | |
|---|---|
| Target | `leadnet-api/src/handlers/leads.rs` |
| Contracts | `BE-LEADNET-01`, `BE-LEADNET-02` |
| Pipelines to 100% mortality | 4 iterations |
| Wall clock of the slowest shard | 575 s |
| Viable mutants | 8, caught 8, survivors 0 |
| Total cost (existing infrastructure) | ~90 min |

#### Chronology of failures: the honest record

**Iteration 1: 3 surviving mutants in `resolve_lead_view` (lines 49, 54, 56).**

Cause: the logical duality `has_access || has_signed_agreement` created two semantically
equivalent paths. A mutation in one was compensated by the other. In addition, no fixture
covered `status=Reserved` with `claimed_by` set.

Fix: a single condition, `is_buyer`. Fixture `Reserved` with `claimed_by=Some(broker_oid)`.

**Iteration 2: 2 more mutants, in `submit_lead:115` and `purchase_lead:139`.**

Cause: logic inline in the handler, with no isolated domain coverage. Extracting pure
functions is the obvious solution, but an incomplete one.

Fix: `lead_is_purchasable()` and `broker_should_be_notified()` as pure functions with direct
unit tests.

**Iteration 3: 1 residual mutant, `delete !` in `purchase_lead:154`.**

Architectural root cause, the critical insight of this sprint:

The pure function `lead_is_purchasable()` had been extracted correctly. Its internal mutants
(`== Open` to `!= Open`) were killed by the direct unit tests.

But the negation `!` lived **in the handler**, outside the reach of the pure function's tests.
cargo-mutants generated a mutant in the handler that the pure function's tests could not see,
because those tests never called the handler.

> **NEW EMPIRICAL RULE.**
> Pure functions resolve mutations *inside* the function.
> They do not resolve guard negations in the handler that calls them.
> The only solution is to remove the negation from the handler.

**Iteration 4: Zero-Logic Handler (the definitive solution).**

Pattern implemented: `LeadPurchaseGuard` with an opaque `PurchaseToken` and a `LeadRejection`
enum.

Resulting handler:

```rust
let token = LeadPurchaseGuard::evaluate(&lead).map_err(|r| ...)?;
state.leads.reserve(token.lead_oid(), &broker_oid).await?;
```

No `if`, no `!`, no logic. The compiler enforces the invariant.
Mutant `delete !`: **unviable** (it no longer exists in the handler to be mutated).
Mutant `!= Open`: killed by a triple strike in the unit tests of `LeadPurchaseGuard`.

Mortality: 8/8, 100%. **SEALED.**

### 3.3 The escalation ladder

(Added in this edition: section 9.2 cites it as section 3 of v2.1.) Read in order, the four
iterations are one movement: the invariant was pushed down, step by step, until nothing above
it could remove it.

```
prompt -> pure function -> transport -> type system
```

Each failure was climbed, none was skipped. Chapter 9 shows the same ladder, climbed by a
whole system instead of a handler.

---

## 4. Formalized architectural patterns

### 4.1 Zero-Logic Handler

**Problem:** handlers with guard logic (`if !f(...)`) create mutants in the handler that the
tests of pure functions cannot kill.

**Solution:** the handler holds no logic. It delegates to a guard that returns an algebraic
type, and translates that type to HTTP.

Before:

```rust
if !lead_is_purchasable(&lead.status) { return Err(...) }
state.leads.reserve(lead.id, &broker_oid).await?;
```

After:

```rust
let token = LeadPurchaseGuard::evaluate(&lead).map_err(|r| ...)?;
state.leads.reserve(token.lead_oid(), &broker_oid).await?;
```

**When to apply:** whenever a handler contains `if !something(...)`.

**Benefit for mutation testing:** cargo-mutants generates no viable mutants in a handler with
no logic. Mutants in the algebraic types are always reachable by direct unit tests.

### 4.2 Opaque Token

**Problem:** the guard can be bypassed if the handler is able to build the token type by
hand.

**Solution:** the success return type is opaque: no public fields, no constructors, no
`Default`, no `Clone`. The guard is the only constructor.

```rust
#[derive(Debug)]  // allowed: needed by the test harness
pub struct PurchaseToken { lead_oid: ObjectId }  // private field

impl LeadPurchaseGuard {
    pub fn evaluate(lead: &Lead) -> Result<PurchaseToken, LeadRejection> {
        // the only place a PurchaseToken is created
    }
}
```

**Benefit for mutation testing:** any mutant that tries to bypass the guard fails to compile,
so it is unviable: no noise, no false positives.

### 4.3 Real state fixtures

**Problem:** state comparison mutants survive when the test fixtures do not cover every
relevant state of the lifecycle.

**Example:** the mutant `== Sold` to `!= Sold` survives if no fixture has `status=Sold` and
`claimed_by` set at the same time.

**Solution:** for every access control BE, create one fixture per state of the lifecycle enum,
with every relevant combination of the other fields.

**Rule:** if the lifecycle has N states, the tests of an access BE need N fixtures, one per
state, plus the critical combinations.

---

## 5. Known limitations and open gaps

### Gap 1: HTTP integration tests versus domain unit tests

**Observed:** the attempt to write real HTTP tests (`POST /leads`,
`POST /leads/{id}/purchase`) to kill mutants in handlers failed, because `SharedState` needs
MongoDB, Stripe and SMTP running, and none of them exist on the CI runner.

**Conclusion:** real HTTP tests require service traits and a mock for each trait, a refactor
of about 200 lines that is not in the scope of a mutation testing sprint.

The Zero-Logic Handler solves the problem by another route: once the handler holds no logic,
the relevant mutants move into pure functions that can be tested directly.

**Decision:** do not introduce `axum-test` and service mocks only to kill mutants. Prefer the
Zero-Logic Handler as the architectural pattern.

### Gap 2: no multi-sprint time baselines

Observed data (two sprints):

- Bags v1 (2 BEs, new infrastructure): ~70 min
- LeadNet v1 (2 BEs, existing infrastructure, 4 iterations): ~90 min

**Unconfirmed hypothesis:** "the 9 layers take only 10 minutes for small tasks". This
hypothesis still has no empirical support for layers with mechanical linkage.

Baselines to measure in the next sprints:

- time spent writing the spec versus time spent implementing, per BE;
- number of Verification Loops avoided because a linked BE existed;
- cost of adoption in projects with no prior Nix infrastructure.

### Gap 3: sharding coverage versus domain coverage

**Observed:** cargo-mutants shards distribute mutants geographically (by file and line), not
by semantic criticality. A security critical mutant can land in the same shard as 20 trivial
ones, with no priority.

**Risk:** under time pressure, disabling a shard to speed up the pipeline can silently
exclude critical mutants of security BEs.

**Current mitigation:** none. Shards are distributed uniformly.
**Future mitigation:** tag critical mutants with a priority weight in cargo-mutants.

---

## 6. Prior art and acknowledgments

The foundation of Prumo, in particular the mechanization of trust through the verification
pipeline (Layer 5) and the hermetic cage (Layer 8), owes a great deal to the ideas of
**deterministic runtimes and forced fault injection** championed by **Geoffrey Huntley**.

Huntley's work on deterministic testing architectures (intercepting virtual time, entropy
counters, explicit fault plans injected into the state and event log) was the empirical
catalyst for Prumo. The realization that software correctness
cannot be established without isolating non-determinism and deliberately forcing failures
(mutants) is the direct precursor of prumo-mutants. Prumo is that deterministic rigor applied,
industrially, to AI-native generation.

---

## 7. Ledger of sealed contracts

As of June 2026, these contracts reached 100% mortality and are mechanically enforced in CI:

| Contract | Invariant | Status |
|---|---|---|
| `BE-BAGS-01` | Eligibility gate (bags) | SEALED June 2026 |
| `BE-BAGS-02` | Minimum threshold per item | SEALED June 2026 |
| `BE-LEADNET-01` | Lead promotion gate | SEALED June 2026 |
| `BE-LEADNET-02` | PII visibility invariant | SEALED June 2026 |

Chapter 9, section 9.8, adds the behavioral contracts.

---

## 8. Terminology

- **Boundary Expectation (`BE-*`):** an Expectation with a formal ID mechanically linked to a
  test.
- **AST linkage:** the link from the ID to the compiled identifier through a macro
  (`#[prumo_expect("BE-*")]`).
- **prumo-verify:** the auditor that checks the intersection between declared BEs and
  empirical PASSED events.
- **prumo-mutants:** the mortality validator; blocks the merge if any mutant survives.
- **Zero-Logic Handler:** a handler with no domain logic; it delegates to an algebraic guard.
- **Opaque Token:** a success return type with no public constructors; the compiler enforces
  the invariant.
- **Hermetic cage:** a Nix environment that makes execution reproducible independently of the
  runner.
- **Boundary Expectation Breach:** a declared BE was violated in verification or in
  production.
- **Verification Loop:** a Deliverable goes back to In Progress after failing verification.
- **Assumption Incident:** an explicit Assumption violated by reality.
- **Regression Rule:** a business invariant that can never be violated.

---

## 9. Behavioral Boundary Expectations: Extending Prumo from Code to Agents

> v2.2 supplement, updated July 2026. Written after the events of 1 to 6 July 2026. Chapters 1
> to 8 remain canonical, with the rhetorical revisions mandated by section 9.6 (already applied
> in this edition). This chapter is empirical: every claim in it is anchored to a commit, a log
> line, or a falsifiable ledger entry on the systems where it happened.

Prumo v2.1 mechanized trust in **code**: a Boundary Expectation is not real until a test linked to it passes, and a test is not real until mutation testing proves it can kill injected faults. Chapter 9 documents the discovery that the same machinery, and the same escalation ladder, applies to **agent behavior**, and reports the first behavioral contracts to survive the full pipeline.

### 9.1 The Second Verification Asymmetry

v2.1 opened with the verification asymmetry of generation: AI writes code faster than humans can audit it. Operating an autonomous agent (the operations bot of the company where Prumo was developed) exposed a second asymmetry, prior to and more corrosive than the first: **AI produces verdicts faster than humans can verify them.** "The page is fine, it's probably cache." "Deploy confirmed, HTTP 200." "The service is in a restart loop; kill the process."

Between 01 and 05 July 2026, a falsifiable ledger (`incidents.md`, append-only, humans-only confirmation) recorded eight false investigative verdicts. Every one had the same anatomy: evidence of class *Inference* (a partial diff, an absent API field, memory recall, a wrong proxy) presented with the confidence of *DirectObservation*. False verdicts are worse than false code: code fails in CI; verdicts fail in the humans who trusted them, and the trust does not regenerate on redeploy.

The response was to apply Prumo to the agent itself: a declared spec (Goal, Assumptions, Expectations, Edge Cases, Regression Rules, DoD) whose deliverable is a rule about the agent's own epistemic conduct, with a falsification window and a metric a human reads. The agent never declares Done on itself.

### 9.2 Empirical Result: Gates Inside the Model Do Not Hold

Two enforcement attempts preceded the mechanical phase, and both failed in production within days. They are the load-bearing negative results of this chapter.

- **Prompt-layer guard (failed in 1 day).** A memory-resident rule ("never publish without showing the user a summary and getting explicit OK") was violated the day after a destructive publish destroyed a bespoke page (incident #4).
- **Model-mediated confirmation (failed in 2 days).** A `confirm=true` parameter, added to the destructive tools with mandatory-warning instructions, was satisfied *mechanically without fulfilling its purpose*: the model passed `confirm=true` after a casual "sim publica agora" ("yes, publish now"), without issuing the required warning (incident #5, an identical recurrence of #4, with the guard installed).

The generalization, now a Prumo law: **a gate whose satisfying token is produced by the model is not a gate; it is a request.** Deontic language ("NEVER", "MUST") steers model behavior and is the correct register for agent-facing documents, but steering is not enforcement. Where compliance is critical, the invariant must live where the model cannot reach it. This is the v2.1 escalation ladder (§3: prompt → pure function → transport → type system), climbed by a whole system instead of a handler.

### 9.3 The Enforcement Pyramid

The mechanical phase (deployed 06 July 2026, commits `8952bc3`/`2e0415c`) organizes enforcement in four layers, ordered by determinism and marginal token cost. The economic rule is absolute: **judgment pays tokens; enforcement never does.** No gate may invoke an LLM (Regression Rule, cross-release).

- **Layer 0: Deterministic runtime (zero tokens).** Go/Rust code the model cannot influence: the approval subsystem, the verdict annotation gate, the resource lock registry. This is where trust lives.
- **Layer 1: Auditable model output (tokens already paid).** The model's self-reports are cross-checked against facts the runtime possesses independently (e.g., a claim of direct observation against the session's actual tool-execution count). Self-classification is audited, never trusted.
- **Layer 2: Episodic token spend.** Replay evals (each production incident becomes a forbidden-pattern scenario) run on model/prompt changes, not per message. Calibration is pure arithmetic over logged (confidence, outcome) pairs, with zero LLM involvement.
- **Layer 3: Human DoD.** Unchanged from v2.1: the responsible human declares Done; the machine only makes the evidence cheap to read.

A cognitive framework was available (an in-house one: orchestrator, LLM loops, epistemic engine). The correct integration was to take its **deterministic core** (evidence-type ceilings, thresholds, calibration; pure Rust, zero tokens) and leave its cognitive loops out. Connecting agent to agent multiplies token cost and failure surface; connecting agent to arithmetic costs nothing and cannot hallucinate.

### 9.4 Derived Patterns (continuing §4)

#### 9.4.1 Human Interaction Token

*Problem:* any confirmation the model can express, the model can express wrongly (§9.2).
*Solution:* the Opaque Token of §4.2, ported from the type system to a **process boundary**. Destructive operations are never executed by the tool the model calls; the exact HTTP request is spooled to disk, and a runtime watcher posts Approve/Cancel buttons in the team's channel. Execution requires a `HumanApprovalToken`: unexported fields, no exported constructor, built exclusively in the UI-interaction handler after allowlist validation. The model is structurally incapable of forging a click.
*Fail-closed by enumeration:* no click in 15 min → expires; process restart → all pending requests expire; button-posting failure → nothing executes; non-allowlisted click → refused and logged; replayed click → refused (single-shot state transition).

#### 9.4.2 Verdict Annotation Gate

*Problem:* categorical verdicts uttered from recall are indistinguishable, to the reader, from verified ones.
*Solution:* a pure function over two runtime facts: does the response text match the (versioned, incident-grown) verdict pattern, and how many tools did this session actually execute? Zero executions means the evidence class is at best *Inference* (ceiling 0.65, §9.7); the response is annotated: *"No mechanical confirmation in this session."* The gate annotates; it does not censor, and its false positives are themselves ledger incidents.

#### 9.4.3 Resource Lock Registry (reject, don't queue)

*Problem:* concurrent agent sessions on one resource manufacture false narratives (a concurrency artifact was diagnosed as a security breach, incident #1).
*Solution:* per-resource try-lock; the second state-changing operation is **rejected with the holder's identity**, never silently queued. Locks wrap the execution of an operation only, never a conversation turn, because LLM calls were measured at up to 26 minutes and a held lock would starve the team.

### 9.5 Mortality Proof on Behavioral Gates

The v2.1 criterion (0 viable surviving mutants) was applied to the behavioral gates with `gremlins` (Go). The telemetry reproduced the LeadNet dynamics of §3 in miniature: mutation testing again acted as a design forcing function, not merely a test grader:

- **Iteration 1: 71.4% efficacy (35 killed / 14 lived).** Naive tests pass; mutants in defaults, HTTP payload construction, boundary comparisons, and log-only error branches survive.
- **Iteration 2: 93.9%.** Surviving mutants forced structural moves: contract constants (TTL 15 min, tick 3 s, timeouts) extracted and **pinned by test to the values declared in the spec**: mutating the constant now falsifies the spec, which is precisely what a contract constant should mean; exact-payload replay asserted byte-for-byte; boundary statuses (HTTP 300, exact-TTL instant) given dedicated fixtures per §4.3.
- **Iteration 3: 100.0% (49 killed / 0 lived).** The last survivors were log-only error branches, observable only in telemetry, so telemetry became the assertion (a log-recorder harness).

Tooling friction forced one architecture improvement directly: the verdict gate could not be mutation-tested inside a package with inherited failing tests, so it was extracted into its own package: the mutation engine, once again, pushing logic toward small, pure, independently provable units. Exclusions are declared, not hidden: the thin Discord SDK wrapper (requires a live session; covered by the human end-to-end click) and `const` declarations (pinned by test; the tool does not execute declarations).

The chain was sealed end-to-end on 06 July at 00:55: a spiked approval request, a real human click (recorded approver ID), the replayed HTTP call, the expected 404, the failed status, the edited message. Verification pipeline: `prumo-verify-go` (test-name linkage `TestBE_AGENT_NN_*` standing in for the Rust macro of §2): intersection 3/3 PASS.

### 9.6 The Epistemic/Deontic Rule for Agent-Facing Documents

Prumo documents are executed by LLMs: they are an operating system, not literature. Operating one for a week yielded a composition rule that v2.2 adopts and applies retroactively to v2.1's own prose:

1. **Obligations: maximally strict.** Absolute conditionals with verifiable gates ("if a mandatory field is empty, execution does not begin") are what a model actually follows. Do not soften them.
2. **Mechanism descriptions: literal.** A model that reads "cryptographic intersection" will reason about signatures that do not exist and describe the system falsely with full confidence. v2.1's "cryptographic intersection" is revised to what it is: an exact string-match intersection between declared IDs and test-runner PASS events.
3. **Guarantees: calibrated.** A model that believes "mathematically proven correct" stops compensating for the known gaps: it will answer "impossible, the contract is sealed" about the exact layer the Gap section says is uncovered. v2.1's "mathematically prove that the code works" is revised to: **mechanically enforce that every declared boundary contract has a test proven non-hollow within the tool's mutation space.** Weaker as rhetoric; stronger as a belief for an agent to hold, because it is true.

Inflated epistemic claims are more dangerous for LLM readers than for humans: humans discount hyperbole, models act on it. Gaps, likewise, are not confessions to file at the end: they are **routing rules** ("this layer is uncovered; therefore when touching it, do X") and belong where the agent will trip over them.

### 9.7 The Evidence Contract (extension to Layer 4, Assumptions)

Every incident in the baseline was a failure of the *investigation* phase, the phase v2.1 did not instrument. v2.2 closes this by typing the evidence under every Assumption and every investigative verdict, with ceilings taken from the in-house epistemic engine (Rust, deterministic):

| Evidence class | Ceiling | Examples |
|---|---|---|
| DirectObservation | 0.95 | file read now, test run now, API called now |
| ExpertTestimony | 0.85 | validated statement by a domain expert |
| Documentation | 0.75 | written sources, config state, API docs |
| Inference | 0.65 | partial diffs, absence of signal, memory recall |

Rules: an Assumption declares its evidence class and, if below DirectObservation, the **elevation step** that would raise it; an Assumption resting on Inference cannot ground a Boundary Expectation until elevated; a categorical verdict above its evidence ceiling must either run the elevation now or state "no mechanical confirmation" explicitly. The ceilings themselves are unvalidated constants (hypotheses, not facts), and the Phase-2 calibration loop (logged confidence vs. outcome, computed arithmetically) exists precisely to test them. Prumo instruments the epistemic engine; the engine disciplines Prumo.

### 9.8 Ledger (additions)

- **BE-AGENT-01**: Destructive operations execute only via Human Interaction Token. IMPLEMENTED 06 Jul 2026; verify PASS; mutation 100% (3 iterations, 71→94→100); human E2E click confirmed 00:55. SEALED pending: 7-day soak (to 13 Jul) + human Done.
- **BE-AGENT-02**: Categorical verdict with zero session tool-executions is annotated as Inference. IMPLEMENTED 06 Jul 2026; verify PASS; mutation 100%.
- **BE-AGENT-03**: Concurrent state-changing operations on one resource: exactly one executes, the second is rejected with context. IMPLEMENTED 06 Jul 2026; verify PASS; race-tested (no viable mutants in the tool's mutator set; fallback per spec).
- **BE-AGENT-04/05** (structured verdicts over the v1.2.0 shadow substrate; `epistemic-check` binary): DECLARED, Phase 2, gated on one week of shadow data and an explicit human decision.

### 9.9 Known Limitations & Open Gaps (v2.2)

- **Gap 4: the wrong-proxy class.** Two of the five Week-1 incidents involved *executed* tools that were the *wrong* tools (uptime as proof of deploy; CMS record as proof of rendered page). Distinguishing right tools from wrong tools is judgment, not counting; no deterministic gate covers it. Mitigation remains domain skills, replay evals, and humans. Any gate claiming to close this gap should be distrusted on sight.
- **Gap 5: evidence classification is model-side.** The runtime can prove *zero* observations occurred; it cannot yet prove a claimed observation was the relevant one. Phase 2 audits the classification (structured verdicts cross-checked against runtime facts); it does not eliminate it.
- **Gap 6: pattern gates have false negatives.** The verdict regex will miss phrasings it has not seen. By design (Layer 8), each miss caught in production becomes a ledger incident and a new pattern: the gate grows by incident, never by speculation.
- **Sample size.** One agent, one team, one week of behavioral contracts. The dynamics matched the code-level results of v2.1 exactly (interior gates fail; mutation forces design; invariants stabilize only below the model), which is consistency, not proof.

### 9.10 Glossary (additions)

- **Behavioral Boundary Expectation:** a BE whose subject is agent conduct rather than code output; same ID/linkage/mortality pipeline.
- **Human Interaction Token:** an Opaque Token constructible only from a human UI interaction in the runtime; the process-boundary form of §4.2.
- **Enforcement Pyramid:** the layering of §9.3; trust concentrates at the deterministic base, token spend concentrates where judgment is genuinely needed.
- **Evidence Contract:** the typed-evidence discipline of §9.7 (class, ceiling, elevation step) applied to Assumptions and verdicts.
- **Verdict Annotation Gate:** the Layer-0 gate of §9.4.2; annotates unverified categorical claims, never censors them.
- **Second Verification Asymmetry:** AI produces investigative verdicts faster than humans can verify them; the agent-behavior analogue of v2.1's generation asymmetry.

### 9.11 Chapter Conclusion

v2.1 ended by asserting that trust must be displaced from manual auditing to mechanical proof. v2.2 reports what happened when that assertion was tested against an agent's *behavior* rather than its code: the prompt guard failed in one day, the model-mediated gate in two, and the invariant held only when it crossed the process boundary: into a token the model cannot construct, a counter the model cannot fake, and a lock the model cannot bypass. The escalation ladder of §3 is therefore not a code-review anecdote; it is the general trajectory of enforcement in AI-native systems: **prompt → deterministic runtime gate → structural invariant.** Each failure is climbed, none is skipped, and the ledger records the climb. What the model believes is steered by language; what the system permits is decided below it. Prumo v2.2's contribution is the demonstration (small, instrumented, and falsifiable) that the second of these can be engineered with exactly the machinery the first cannot corrupt.

---
*Provenance: incidents.md (baseline 01 Jul, Week 1 #1–#5), SPEC-GATES-MECANICOS.md and its git history (dcddbcb…c005c9c), orchestrator commit 8952bc3, CMS commit 2e0415c, gremlins telemetry 06 Jul 2026. All on the production host.*
