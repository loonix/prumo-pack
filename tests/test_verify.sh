#!/usr/bin/env bash
# prumo-verify: an ACTIVE invariant counts only when the runner reports a PASS
# for the tests bound to it (#9). Fixtures are generated here, one repository
# per case, so each case states exactly what it puts on disk.
. "$(dirname "$0")/lib.sh"

V="$PACK_ROOT/bin/prumo-verify"

# repo <rules...>: a repository whose regression rules are the given lines.
repo() {
  local d
  d="$(tmpdir)"
  mkdir -p "$d/.prumo/regression-rules" "$d/src"
  printf '%s\n' "# RR-001" "$@" >"$d/.prumo/regression-rules/RR-001.md"
  printf '%s\n' "$d"
}
RULES=('- `SEC-01` : **ACTIVE** : tenants are isolated'
  '- `SEC-02` : **ACTIVE** : a token expires'
  '- `BIZ-02` : **REVOKED 2026-09-18 (daniel)** : old rule'
  '- `BIZ-07` : **OPEN** (issue #3) : future rule')

# A Rust module with one tagged test per ACTIVE invariant.
rust_src() {
  cat >"$1/src/auth.rs" <<'EOF'
#[cfg(test)]
mod tests {
    // PRUMO: SEC-01
    #[test]
    fn tenants_do_not_see_each_other() {}

    /// PRUMO: SEC-02
    #[test]
    #[should_panic]
    fn an_expired_token_is_refused() {}
}
EOF
}
# libtest <event for SEC-01> <event for SEC-02>: cargo test --format json.
libtest() {
  printf '%s\n' \
    '{ "type": "suite", "event": "started", "test_count": 2 }' \
    '{ "type": "test", "event": "started", "name": "auth::tests::tenants_do_not_see_each_other" }' \
    "{ \"type\": \"test\", \"name\": \"auth::tests::tenants_do_not_see_each_other\", \"event\": \"$1\" }" \
    "{ \"type\": \"test\", \"name\": \"auth::tests::an_expired_token_is_refused\", \"event\": \"$2\" }" \
    '{ "type": "suite", "event": "ok", "passed": 2, "failed": 0 }'
}

echo "libtest JSON, tag on the line above the test"
D="$(repo "${RULES[@]}")"; rust_src "$D"
libtest ok ok >"$D/r.json"
check_output "every ACTIVE invariant passed: OK" 0 "prumo-verify: OK, 2 active" "$V" --root "$D" --results "$D/r.json"
libtest ok ignored >"$D/r.json"
check_output "an ignored test proves nothing" 1 "SEC-02" "$V" --root "$D" --results "$D/r.json"
check_output "and the reason says it did not run" 1 "did not run" "$V" --root "$D" --results "$D/r.json"
libtest failed ok >"$D/r.json"
check_output "a failed test fails its invariant" 1 "SEC-01" "$V" --root "$D" --results "$D/r.json"
check_output "and names the failed test" 1 "failed: auth::tests::tenants_do_not_see_each_other" \
  "$V" --root "$D" --results "$D/r.json"
libtest ok ok | grep -v an_expired >"$D/r.json"
check_output "a bound test missing from the results fails" 1 "an_expired_token_is_refused" \
  "$V" --root "$D" --results "$D/r.json"

echo "a tag that is not on a test is not proof"
D="$(repo "${RULES[@]}")"; rust_src "$D"
sed -i 's|/// PRUMO: SEC-02||' "$D/src/auth.rs"
mkdir -p "$D/ci"; printf 'script:\n  - run   # PRUMO: SEC-02\n' >"$D/ci/pipeline.yml"
libtest ok ok >"$D/r.json"
check_output "a tag in CI binds to no test" 1 "not on a test" "$V" --root "$D" --results "$D/r.json"
D="$(repo "${RULES[@]}")"; rust_src "$D"
sed -i 's|/// PRUMO: SEC-02||' "$D/src/auth.rs"
libtest ok ok >"$D/r.json"
check_output "an invariant with no tag at all fails" 1 "no test bound" "$V" --root "$D" --results "$D/r.json"

echo "the id in the test name binds too (the whitepaper form)"
D="$(repo '- `SEC-01` : **ACTIVE** : x')"
printf '{ "type": "test", "name": "be::test_sec_01_isolation", "event": "ok" }\n' >"$D/r.json"
check_output "a passed test named with the id: OK" 0 "OK" "$V" --root "$D" --results "$D/r.json"
printf '{ "type": "test", "name": "be::test_sec_010_isolation", "event": "ok" }\n' >"$D/r.json"
check_output "SEC-01 is not SEC-010" 1 "SEC-01" "$V" --root "$D" --results "$D/r.json"
printf '{ "type": "test", "name": "be::test_sec_01b_isolation", "event": "ok" }\n' >"$D/r.json"
check_output "SEC-01 is not SEC-01b" 1 "SEC-01" "$V" --root "$D" --results "$D/r.json"

echo "same function name in two modules: both must pass"
D="$(repo '- `SEC-01` : **ACTIVE** : x')"
printf '// PRUMO: SEC-01\n#[test]\nfn it_holds() {}\n' >"$D/src/a.rs"
printf '%s\n' '{ "type": "test", "name": "a::it_holds", "event": "ok" }' \
  '{ "type": "test", "name": "b::it_holds", "event": "failed" }' >"$D/r.json"
check_output "an ambiguous name that failed anywhere fails" 1 "b::it_holds" "$V" --root "$D" --results "$D/r.json"
printf '%s\n' '{ "type": "test", "name": "a::not_it_holds", "event": "ok" }' >"$D/r.json"
check_output "a name is matched whole, not as a suffix of another" 1 "it_holds" \
  "$V" --root "$D" --results "$D/r.json"

echo "JUnit XML (pytest, nextest, vitest, jest)"
D="$(repo '- `SEC-01` : **ACTIVE** : x' '- `SEC-02` : **ACTIVE** : y')"
cat >"$D/src/test_auth.py" <<'EOF'
import pytest

# PRUMO: SEC-01
@pytest.mark.slow
def test_tenants_are_isolated():
    pass
EOF
cat >"$D/src/auth.test.ts" <<'EOF'
describe("auth", () => {
  // PRUMO: SEC-02
  it("refuses an expired token", () => {});
});
EOF
junit() {
  cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<testsuites><testsuite name="all" tests="2">
<testcase classname="src.test_auth" name="test_tenants_are_isolated" time="0.1">$1</testcase>
<testcase classname="src/auth.test.ts" name="auth refuses an expired token" time="0.1"/>
</testsuite></testsuites>
EOF
}
junit "" >"$D/r.xml"
check_output "python def and a JS it() pass: OK" 0 "OK, 2 active" "$V" --root "$D" --results "$D/r.xml"
junit '<skipped message="slow"/>' >"$D/r.xml"
check_output "a skipped testcase proves nothing" 1 "did not run" "$V" --root "$D" --results "$D/r.xml"
junit '<failure message="boom"/>' >"$D/r.xml"
check_output "a testcase with <failure> fails" 1 "failed: src.test_auth::test_tenants_are_isolated" \
  "$V" --root "$D" --results "$D/r.xml"
junit '<error message="boom"/>' >"$D/r.xml"
check_output "a testcase with <error> fails" 1 "SEC-01" "$V" --root "$D" --results "$D/r.xml"

echo "go test -json"
D="$(repo '- `SEC-01` : **ACTIVE** : x')"
printf 'package auth\n\n// PRUMO: SEC-01\nfunc TestTenantsAreIsolated(t *testing.T) {}\n' >"$D/src/auth_test.go"
printf '%s\n' '{"Action":"run","Package":"x/auth","Test":"TestTenantsAreIsolated"}' \
  '{"Action":"pass","Package":"x/auth","Test":"TestTenantsAreIsolated","Elapsed":0}' \
  '{"Action":"pass","Package":"x/auth","Elapsed":0.1}' >"$D/r.json"
check_output "a passed go test: OK" 0 "OK" "$V" --root "$D" --results "$D/r.json"
sed -i '2s/"pass"/"skip"/' "$D/r.json"
check_output "a skipped go test proves nothing" 1 "did not run" "$V" --root "$D" --results "$D/r.json"

echo "several results files are one run"
D="$(repo "${RULES[@]}")"; rust_src "$D"
libtest ok ok | grep -v an_expired >"$D/a.json"
libtest ok ok | grep -v tenants_do_not >"$D/b.json"
check_output "results split across files: OK" 0 "OK" "$V" --root "$D" --results "$D/a.json" --results "$D/b.json"

echo "fails closed"
D="$(repo "${RULES[@]}")"; rust_src "$D"
check "no --results is a usage error" 2 "$V" --root "$D"
check "a missing results file is a usage error" 2 "$V" --root "$D" --results "$D/nope.json"
printf 'running 0 tests\n' >"$D/r.txt"
check_output "a file in no known format is refused" 2 "format" "$V" --root "$D" --results "$D/r.txt"
printf '{ "type": "suite", "event": "ok", "passed": 0 }\n' >"$D/r.json"
check_output "results with no test case are refused (blind)" 1 "REFUSED" "$V" --root "$D" --results "$D/r.json"
printf '<testsuites/>\n' >"$D/r.xml"
check_output "an empty JUnit file is refused (blind)" 1 "REFUSED" "$V" --root "$D" --results "$D/r.xml"
D="$(repo '- `BIZ-02` : **REVOKED 2026-09-18 (daniel)** : old')"
libtest ok ok >"$D/r.json"
check_output "rules with no ACTIVE invariant are refused" 1 "REFUSED" "$V" --root "$D" --results "$D/r.json"
D="$(tmpdir)"
libtest ok ok >"$D/r.json"
check_output "no rules file is refused" 1 "no rules file" "$V" --root "$D" --results "$D/r.json"

finish
