#!/usr/bin/env bash
# prumo-trace: the contracts ported from prumo_traceability.rs, one case per test
# of the original, plus the cases the language-agnostic version adds (several
# rules files, trace-ignore, legacy separator).
. "$(dirname "$0")/lib.sh"

T="$PACK_ROOT/bin/prumo-trace"
F="$PACK_ROOT/tests/fixtures/trace"

echo "contracts from the original"
# PRUMO: PACK-01
check_output "ACTIVE without tag fails" 1 "SEC-02" "$T" --root "$F/active-without-tag"
# PRUMO: PACK-02
check_output "tag citing an undeclared id fails" 1 "DATA-04" "$T" --root "$F/undeclared-id"
# PRUMO: PACK-03
check_output "REVOKED with a live guard fails" 1 "BIZ-02 still guarded" "$T" --root "$F/revoked-with-tag"
# PRUMO: PACK-04
check_output "OPEN without issue fails" 1 "OPEN without an issue" "$T" --root "$F/open-without-issue"
check_output "OPEN with proof fails" 1 "BIZ-07 already proven" "$T" --root "$F/open-with-proof"
check_output "invariant without status fails" 1 "declares no status" "$T" --root "$F/no-status"
check_output "id declared twice fails (even across files)" 1 "SEC-01 declared in" "$T" --root "$F/duplicate-id"
check_output "rules with no invariant fail (blind checker)" 1 "declare no invariant at all" "$T" --root "$F/no-invariants"
check_output "no rules file fails" 1 "no rules file" "$T" --root "$F/no-rules"
check "missing root fails" 2 "$T" --root "$F/does-not-exist"

echo "good case"
check_output "compliant repository passes" 0 "5 declared" "$T" --root "$F/good"
check_output "prose, docs/ and node_modules/ do not count as tags" 0 "OK" "$T" --root "$F/good"
check "trace-ignore excludes declared paths" 0 "$T" --root "$F/ignored"

echo "id parser (ported from o_parser_de_ids_aceita_o_que_a_rr_001_usa_e_recusa_prosa)"
for good in SEC-01 BIZ-04b TIER-03 OPS-02 DATA-01 FISC-05; do
  check "accepts $good" 0 "$T" --valid-id "$good"
done
for bad in sec-01 SE-01 BIZ- BIZ-x BIZ-04bb RR-001 -01 BIZ01; do
  check "rejects $bad" 1 "$T" --valid-id "$bad"
done

echo "legacy format compatibility (em dash and Portuguese statuses, generated here)"
D="$(tmpdir)"
mkdir -p "$D/.prumo/regression-rules" "$D/src"
DASH="$(printf '\342\200\224')"
printf -- '- `SEC-01` %s **ACTIVA** %s legacy\n- `BIZ-02` %s **REVOGADA 18 Set 2026 (x)** %s dead\n' \
  "$DASH" "$DASH" "$DASH" "$DASH" >"$D/.prumo/regression-rules/RR-001-core-invariants.md"
cp "$F/active-without-tag/src/t.sh" "$D/src/t.sh"
check "legacy RR (em dash, ACTIVA, REVOGADA) is read" 0 "$T" --root "$D"
D="$(tmpdir)"
mkdir -p "$D/.prumo/regression-rules" "$D/src"
printf -- '- `BIZ-07` : **ABERTA** (issue #3) : legacy\n' >"$D/.prumo/regression-rules/RR-001-core-invariants.md"
printf '# PRUMO: BIZ-07\n' >"$D/src/t.sh"
check_output "legacy ABERTA counts as OPEN" 1 "BIZ-07 already proven" "$T" --root "$D"

finish
