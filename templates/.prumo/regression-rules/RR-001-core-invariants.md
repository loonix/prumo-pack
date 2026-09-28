# RR-001: core invariants

Business invariants that are never violated (Layer 7). `prumo-trace` reads every markdown list
line in this directory that starts with an id between backticks, and links it to the tests that
carry the tag `PRUMO: <id>` in code or CI files (prose files do not count).

Syntax, one invariant per list line (`ID` stands for a real id):

```markdown
- `ID` : **ACTIVE** : text                    at least one tagged test must exist
- `ID` : **REVOKED 2026-09-18 (who)** : text  no tag may remain: delete the guard
- `ID` : **OPEN** (issue #3) : text           cites an issue, no tag yet
```

An id is three or more capital letters, a dash, digits and an optional lowercase letter:
`BIZ-03`, `SEC-12b`. Each id is declared once across all rules files.

CORE-01 below is a placeholder, and `prumo-trace` fails until a test carries
`PRUMO: CORE-01`. Replace the text with a real invariant of this repository and tag the test
that proves it, or revoke it with a date and an author.

## Invariants

- `CORE-01` : **ACTIVE** : replace with the first invariant this repository must never violate
