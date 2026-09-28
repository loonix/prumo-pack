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
| `bin/prumo-trace` | Works, 31 tests |
| `checks/fail-closed.sh` | Works, 12 tests |
| `checks/metabolic.sh` | Works, 19 tests |
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

## checks/fail-closed.sh

A missing protection must refuse to start, never log a warning and carry on. The check flags
any line in production code that contains a warning call (anything matching `warn`) and a
degradation phrase (`running without`, `degraded mode`, `skipping auth`, `sem sandbox`, ...).
Add project phrases to `<dir>/.prumo/fail-closed.patterns`, one extended regex per line.
Tests, `docs/`, prose files and vendored directories are not scanned.

```sh
checks/fail-closed.sh src services     # default: .
```

Exits 0 when compliant, 1 on a finding or when zero files were scanned, 2 when a directory
does not exist.

**Limit:** line based and phrase based. A warning whose message sits on the next line, a
degradation logged at info level, or a phrase not in the list is not seen.

## checks/metabolic.sh

Every subsystem declares how its usage is measured, or it does not grow. Declare them in
`.prumo/subsystems.yml`:

```yaml
roots: [src]
subsystems:
  - name: billing
    path: src/billing
    usage_metric: invoices created per day (table invoices)
    since: 2026-09-01
```

Contract checked:

- every subsystem has `name`, `path` and a `usage_metric` that is not a placeholder
  (`TODO`, `TBD`, `n/a`, ...);
- every declared path exists and no name is declared twice;
- every directory directly under a root is declared, and no subsystem covers a whole root;
- a missing manifest, no roots, no subsystems, a root with zero directories, an unknown key
  or an unparsable line is an error.

```sh
checks/metabolic.sh [--manifest FILE] /path/to/repo
```

Exits 0 when compliant, 1 on a violation, 2 when the repository root does not exist.

**Limit:** it checks declarations, not usage. It does not read the metric, so it cannot tell
whether the metric is collected, whether usage is zero, or whether the text describes a real
measurement. Only directories directly under a root count as subsystems.

## Development

```sh
make test         # runs tests/run.sh; zero cases run counts as a failure
make trace        # runs prumo-trace over this repo
make fail-closed  # runs checks/fail-closed.sh over bin, lib and checks
```

Needs only `bash` and `python3` (stdlib).

## License

MIT, Daniel Carneiro.
