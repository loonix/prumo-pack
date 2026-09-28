#!/usr/bin/env bash
# tests/lib.sh itself: scratch directories are removed when a test file exits.
. "$(dirname "$0")/lib.sh"

leaked_dir() {
  local d
  d="$(bash -c '. "$1/tests/lib.sh"; D="$(tmpdir)"; printf "%s" "$D"' _ "$PACK_ROOT")"
  [ -n "$d" ] && [ ! -e "$d" ]
}

echo "cleanup"
check "tmpdir called in a command substitution is removed on exit" 0 leaked_dir

finish
