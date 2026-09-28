---
name: prumo-trace
description: Use when adding, revoking or testing a business invariant in a repository with a .prumo/ directory. Explains how to declare the invariant and tag the test that proves it, so prumo-trace can check the link.
---

# Trace invariants to tests

In a repository with `.prumo/`, the declared spec is binding. An invariant declared without a
test is worse than none: a revoked rule still guarded blocks the business, and an unimplemented
one becomes a guarantee nobody enforces.

## Declare

One markdown list line in a file under `.prumo/regression-rules/`:

```markdown
- `BIZ-03` : **ACTIVE** : price is never negative
- `BIZ-02` : **REVOKED 2026-09-18 (owner)** : text
- `BIZ-07` : **OPEN** (issue #3) : text
```

- ACTIVE needs at least one tagged test.
- REVOKED must have no tag left. Remove the guard in the same change that revokes the rule.
- OPEN cites an issue and has no tag yet.
- Ids are unique. Never reuse a revoked id.

## Tag

Put the tag in a comment next to the test that proves the rule, in any language:

```python
# PRUMO: BIZ-03
def test_price_never_negative(): ...
```

## Check

```sh
prumo-trace --root .
```

Exit 0 is compliant, 1 is a violation. Report its output, not your reading of the files.

**Limit:** a tag proves the test points at the rule, not that it passes or that it bites.
Run the test, and break the rule on purpose once to see it fail.
