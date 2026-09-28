#!/usr/bin/env bash
# checks/anti-leak.sh: a generic pack must not carry private data. Each rule has
# a fixture that breaks it on purpose.
. "$(dirname "$0")/lib.sh"

C="$PACK_ROOT/checks/anti-leak.sh"
F="$PACK_ROOT/tests/fixtures/anti-leak"

echo "violations"
check_output "public IPv4 address fails" 1 "91.99.12.34" "$C" "$F/ip"
check_output "email outside example domains fails" 1 "jane.doe@acme-internal.io" "$C" "$F/email"
check_output "word from the hashed deny list fails" 1 "denied word" "$C" "$F/word"
check_output "hashed hit names file and line" 1 "src/cfg.py:2" "$C" "$F/word"
D="$(tmpdir)"
mkdir -p "$D/src"
printf 'x = "10.0.0.5"\n' >"$D/src/a.py"
check_output "private range IPv4 fails too (it maps real infrastructure)" 1 "10.0.0.5" "$C" "$D"

echo "good cases"
check_output "clean tree passes" 0 "0 finding" "$C" "$F/clean"
check_output "loopback, documentation ranges and example.com pass" 0 "0 finding" "$C" "$F/doc-ranges"
D="$(tmpdir)"
mkdir -p "$D/.prumo" "$D/src"
printf 'x = 1\n' >"$D/src/a.py"
printf 'not-a-hash\n' >"$D/.prumo/anti-leak.sha256"
check_output "malformed deny list line is an error" 1 "not a sha256" "$C" "$D"

echo "fails closed on itself"
check_output "zero files scanned fails" 1 "zero files" "$C" "$F/no-files"
check_output "missing directory is a usage error" 2 "does not exist" "$C" "$F/does-not-exist"
check_output "--exclude skips a path prefix" 0 "0 finding" "$C" --exclude src "$F/ip"
D="$(tmpdir)"
mkdir -p "$D/src"
printf 'owner = "acmecorp"\n' >"$D/src/a.py"
check_output "--deny-file reads another hash list" 1 "denied word" \
  "$C" --deny-file "$F/word/.prumo/anti-leak.sha256" "$D"
check_output "the pack itself is clean" 0 "0 finding" make -s -C "$PACK_ROOT" leak

finish
