#!/usr/bin/env bash
# bin/prumo-init --source vendor (the default): the gates are copied into
# <repo>/.prumo/vendor/ with a MANIFEST, and the CI it wires runs them from
# there, so a private pack needs no network and no token. Every case builds its
# repository in a temporary directory.
. "$(dirname "$0")/lib.sh"

I="$PACK_ROOT/bin/prumo-init"
V=".prumo/vendor"
GITLAB_LOCAL="local: $V/ci/gitlab.yml"

repo() {
  local d
  d="$(tmpdir)"
  case "$1" in
    gitlab) printf 'stages: [test]\n' >"$d/.gitlab-ci.yml" ;;
    github) mkdir -p "$d/.github" ;;
    none) ;;
  esac
  printf '%s' "$d"
}

snapshot() {
  (cd "$1" && find . -type f | LC_ALL=C sort | while read -r f; do
    printf '%s ' "$f"; cksum <"$f"
  done)
}

# no_network <file>: the CI file names no remote include, no clone of the pack
# and no checkout of another repository.
no_network() {
  if grep -nE 'remote:|git (clone|fetch)|raw\.githubusercontent|repository: *loonix' "$1"; then
    echo "$1 reaches the network for the pack"; return 1
  fi
}

# same_bytes <pack path> <vendored path>
same_bytes() { cmp "$PACK_ROOT/$1" "$2"; }

echo "flag"
check_output "unknown --source value is a usage error" 2 "vendor|remote" "$I" --source http "$(repo gitlab)"
check_output "--source without a value is a usage error" 2 "usage" "$I" --source

echo "GitLab, vendored by default"
D="$(repo gitlab)"
check_output "default source is vendor" 0 "created $V/MANIFEST" "$I" "$D"
check "the vendored MANIFEST verifies" 0 "$D/$V/bin/prumo-vendor-verify"
for f in bin/prumo-trace bin/prumo-vendor-verify lib/prumo_trace.py checks/fail-closed.sh checks/metabolic.sh checks/anti-leak.sh; do
  check "$f vendored byte for byte" 0 same_bytes "$f" "$D/$V/$f"
done
check "GitLab job file vendored byte for byte" 0 same_bytes templates/ci/gitlab/prumo-vendored.yml "$D/$V/ci/gitlab.yml"
check "include is local, not remote" 0 grep -qF "$GITLAB_LOCAL" "$D/.gitlab-ci.yml"
check ".gitlab-ci.yml reaches no network" 0 no_network "$D/.gitlab-ci.yml"
check "vendored GitLab jobs reach no network" 0 no_network "$D/$V/ci/gitlab.yml"
check "MANIFEST pins a commit, not a tag" 0 grep -qE '^pack_commit [0-9a-f]{40}$' "$D/$V/MANIFEST"
check "MANIFEST records the pack version" 0 grep -qF "pack_version $(cat "$PACK_ROOT/VERSION")" "$D/$V/MANIFEST"
check_output "second run is a no-op" 0 "kept $V/MANIFEST" "$I" "$D"
before="$(snapshot "$D")"; "$I" "$D" >/dev/null 2>&1; after="$(snapshot "$D")"
check "second run changes not one byte" 0 test "$before" = "$after"

echo "GitHub, vendored by default"
D="$(repo github)"
check_output "GitHub workflow created" 0 "created .github/workflows/prumo.yml" "$I" "$D"
check "workflow is the vendored GitHub template byte for byte" 0 \
  same_bytes templates/ci/github/prumo-vendored.yml "$D/.github/workflows/prumo.yml"
check "GitHub workflow reaches no network for the pack" 0 no_network "$D/.github/workflows/prumo.yml"
check "GitHub workflow is not a call to the reusable workflow" 1 grep -q 'uses: loonix/' "$D/.github/workflows/prumo.yml"

echo "drift is restored, never trusted"
D="$(repo gitlab)"
"$I" "$D" >/dev/null 2>&1
printf 'X' >>"$D/$V/lib/prumo_trace.py"
check_output "drift fails the vendored verifier" 1 "lib/prumo_trace.py" "$D/$V/bin/prumo-vendor-verify"
check_output "rerun restores the vendor directory" 0 "updated $V" "$I" "$D"
check "restored vendor verifies" 0 "$D/$V/bin/prumo-vendor-verify"
printf 'x\n' >"$D/$V/stray.txt"
check_output "rerun removes an unlisted file" 0 "updated $V" "$I" "$D"
check "stray file gone" 0 test ! -e "$D/$V/stray.txt"

echo "pack provenance"
P="$(tmpdir)/pack"
mkdir -p "$P"
(cd "$PACK_ROOT" && tar cf - bin lib checks templates VERSION) | (cd "$P" && tar xf -)
D="$(repo gitlab)"
check_output "a pack without git history is refused (no commit to pin)" 1 "commit" "$P/bin/prumo-init" "$D"
check "that refusal writes nothing" 0 test ! -e "$D/.prumo"

echo "gates run from the vendor directory, pipeline style"
D="$(repo gitlab)"
"$I" "$D" >/dev/null 2>&1
mkdir -p "$D/tests" "$D/src/billing"
printf '#!/bin/sh\n# PRUMO: CORE-01\ntest "$(echo ok)" = ok\n' >"$D/tests/core_test.sh"
printf '  - name: billing\n    path: src/billing\n    usage_metric: invoices per day\n    since: 2026-09-01\n' >>"$D/.prumo/subsystems.yml"
printf 'def serve():\n    return 0\n' >"$D/src/billing/app.py"
check_output "vendored trace passes, vendor code not traced" 0 "1 declared" bash -c "cd '$D' && $V/bin/prumo-trace --root ."
check_output "vendored metabolic passes" 0 "1 subsystem(s) declared" bash -c "cd '$D' && $V/checks/metabolic.sh ."
check_output "vendored fail-closed passes" 0 "fail-closed: OK" bash -c "cd '$D' && $V/checks/fail-closed.sh ."

finish
