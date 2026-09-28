# shellcheck shell=bash
# Minimal test library. Each tests/test_*.sh file runs `. tests/lib.sh`,
# declares cases with `check` and ends with `finish`. A case that did not run
# does not count as passed: `skip` records it separately and run.sh reports it.

PACK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PACK_ROOT
PASSED=0
FAILED=0
SKIPPED=0

# check <name> <expected exit> <command...>
check() {
  local name="$1" expected="$2" output actual
  shift 2
  output="$("$@" 2>&1)"
  actual=$?
  if [ "$actual" = "$expected" ]; then
    PASSED=$((PASSED + 1))
    printf '  ok     %s\n' "$name"
  else
    FAILED=$((FAILED + 1))
    printf '  FAIL   %s (expected exit %s, got %s)\n' "$name" "$expected" "$actual"
    printf '%s\n' "$output" | head -30 | sed 's/^/         | /'
  fi
}

# check_output <name> <expected exit> <text the output must contain> <command...>
check_output() {
  local name="$1" expected="$2" pattern="$3" output actual
  shift 3
  output="$("$@" 2>&1)"
  actual=$?
  if [ "$actual" = "$expected" ] && printf '%s' "$output" | grep -qF -- "$pattern"; then
    PASSED=$((PASSED + 1))
    printf '  ok     %s\n' "$name"
  else
    FAILED=$((FAILED + 1))
    printf '  FAIL   %s (expected exit %s with "%s", got exit %s)\n' "$name" "$expected" "$pattern" "$actual"
    printf '%s\n' "$output" | head -30 | sed 's/^/         | /'
  fi
}

# skip <name> <reason>: the case did not run. That is not a success.
skip() {
  SKIPPED=$((SKIPPED + 1))
  printf '  SKIP   %s (%s)\n' "$1" "$2"
}

# Temporary directory removed when the test file exits.
tmpdir() {
  local d
  d="$(mktemp -d "${TMPDIR:-/tmp}/prumo-test.XXXXXX")"
  _TMPDIRS="${_TMPDIRS:-} $d"
  printf '%s' "$d"
}
_cleanup() {
  local d
  for d in ${_TMPDIRS:-}; do rm -rf "$d"; done
}
trap _cleanup EXIT

finish() {
  printf '  -> %d passed, %d failed, %d skipped\n' "$PASSED" "$FAILED" "$SKIPPED"
  if [ -n "${PRUMO_TALLY:-}" ]; then
    printf '%s %s %s\n' "$PASSED" "$FAILED" "$SKIPPED" >>"$PRUMO_TALLY"
  fi
  [ "$FAILED" -eq 0 ]
}
