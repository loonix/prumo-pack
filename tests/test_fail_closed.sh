#!/usr/bin/env bash
# checks/fail-closed.sh: a missing protection must refuse to start, never log a
# warning and carry on. Each rule has a fixture that breaks it on purpose.
. "$(dirname "$0")/lib.sh"

C="$PACK_ROOT/checks/fail-closed.sh"
F="$PACK_ROOT/tests/fixtures/fail-closed"

echo "violations"
check_output "warning that continues without sandbox fails" 1 "server.py:8" "$C" "$F/warn-and-continue"
check_output "Portuguese degradation phrase fails" 1 "main.go:7" "$C" "$F/portuguese-phrase"
check_output "project pattern from .prumo/fail-closed.patterns fails" 1 "app.js:3" "$C" "$F/project-pattern"
check_output "one bad target among several fails" 1 "server.py:8" "$C" "$F/good" "$F/warn-and-continue"

echo "good cases"
check_output "fatal refusal and unrelated warnings pass" 0 "1 file(s) scanned" "$C" "$F/good"
check_output "tests, docs, prose and vendored dirs are not scanned" 0 "1 file(s) scanned" "$C" "$F/excluded"
check "the pack's own code passes" 0 "$C" "$PACK_ROOT/bin" "$PACK_ROOT/lib" "$PACK_ROOT/checks"

echo "fails closed on itself"
check_output "missing directory is an error" 2 "does not exist" "$C" "$F/does-not-exist"
check_output "missing directory among good ones is an error" 2 "does not exist" "$C" "$F/good" "$F/does-not-exist"
D="$(tmpdir)"
check_output "empty directory is an error (zero files scanned)" 1 "zero files scanned" "$C" "$D"
check_output "directory with only excluded files is an error" 1 "zero files scanned" "$C" "$F/only-excluded"
D="$(tmpdir)"
printf 'serve()\n' >"$D/app.py"
check_output "no argument scans the current directory" 0 "1 file(s) scanned" sh -c "cd '$D' && '$C'"

finish
