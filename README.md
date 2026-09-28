# prumo-pack

The Prumo gates, packaged to install in any repository (GitLab, GitHub or anything else).
One source, N consumers, instead of scripts copied by hand between projects.

Prumo is an engineering paradigm for working with agents. The rule behind this pack:
**a gate whose satisfaction token is produced by the model is not a gate.** Everything here is
mechanical, no check calls an LLM, and nothing gets in until it has been measured biting in a
real project.

## Status (v0.1.0)

| Piece | Status |
|---|---|
| `bin/prumo-trace` | Works, 28 tests |
| `checks/fail-closed.sh` | In progress |
| `checks/metabolic.sh` | Not started |
| `bin/prumo-init` (scaffolds `.prumo/`, idempotent) | Not started |
| `bin/prumo-certify` (file parity, live back end, rendered DOM) | Not started |
| CI templates (GitLab `include:`, GitHub reusable workflow) | Not started |
| Claude Code plugin (skills and hooks) | Not started |

## prumo-trace

Links every invariant declared in `.prumo/regression-rules/` to the test that proves it, through
the text tag `PRUMO: <id>`. It scans plain text, so it works for any language.

Declare an invariant as one markdown list line, with status `ACTIVE`, `REVOKED` or `OPEN`:

```markdown
- `BIZ-03` : **ACTIVE** : price is never negative
- `BIZ-02` : **REVOKED 2026-09-18 (Daniel)** : text
- `BIZ-07` : **OPEN** (issue #3) : text
```

The Portuguese keywords `ACTIVA`, `REVOGADA` and `ABERTA` are still accepted, for repositories
already declared in Portuguese.

Tag the test that proves it, in any code or CI file:

```rust
// PRUMO: BIZ-03
#[test]
fn price_never_negative() { ... }
```

Contract checked:

- an ACTIVE invariant has at least one tag outside prose;
- a REVOKED invariant has no tag (a guard defending a dead rule blocks the business);
- an OPEN invariant cites an issue and has no tag yet;
- no tag cites an id the rules do not declare;
- no id is declared twice;
- a rules file with no invariants is an error (a blind checker does not get to say OK).

```sh
bin/prumo-trace --root /path/to/repo
```

Exits 0 when compliant, 1 on a violation, 2 on a usage error.

**Limit:** a tag proves that a test points at the rule, not that the test passes or that it
bites. That is the job of the test runner and of mutation testing.

## Development

```sh
make test     # runs tests/run.sh; zero cases run counts as a failure
make trace    # runs prumo-trace over this repo
```

Needs only `bash` and `python3` (stdlib).

## License

MIT, Daniel Carneiro.
