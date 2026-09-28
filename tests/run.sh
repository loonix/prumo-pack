#!/usr/bin/env bash
# Runs every tests/test_*.sh and sums the cases. Exits 0 only if none failed AND
# at least one case ran: a runner that ran nothing cannot say OK.
#
# Usage: tests/run.sh [pattern]   (e.g. tests/run.sh trace)
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2

PRUMO_TALLY="$(mktemp "${TMPDIR:-/tmp}/prumo-tally.XXXXXX")"
export PRUMO_TALLY
trap 'rm -f "$PRUMO_TALLY"' EXIT

failed_files=""
for t in tests/test_*"${1:-}"*.sh; do
  [ -f "$t" ] || continue
  printf '== %s\n' "$t"
  if ! bash "$t"; then
    failed_files="$failed_files $t"
  fi
done

passed=0
failed=0
skipped=0
while read -r p f s; do
  passed=$((passed + p))
  failed=$((failed + f))
  skipped=$((skipped + s))
done <"$PRUMO_TALLY"

printf '\nTOTAL: %d passed, %d failed, %d skipped\n' "$passed" "$failed" "$skipped"
if [ -n "$failed_files" ]; then
  printf 'files with failures:%s\n' "$failed_files"
  exit 1
fi
if [ "$passed" -eq 0 ]; then
  echo "REFUSED: no case ran"
  exit 1
fi
exit 0
