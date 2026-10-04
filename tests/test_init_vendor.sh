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
    github) mkdir -p "$d/.github/workflows" ;;
    jenkins) printf 'pipeline {\n  stages { }\n}\n' >"$d/Jenkinsfile" ;;
    jenkins-dir) mkdir -p "$d/pipelines"; printf 'pipeline {\n}\n' >"$d/pipelines/Jenkinsfile.build" ;;
    jenkins-wired)
      printf "pipeline {\n  stages {\n    stage('Prumo') {\n      steps {\n        script {\n" >"$d/Jenkinsfile"
      printf "          def prumo = load '.prumo/vendor/ci/jenkins.groovy'\n          prumo.prumoGates()\n" >>"$d/Jenkinsfile"
      printf "        }\n      }\n    }\n  }\n}\n" >>"$d/Jenkinsfile"
      ;;
    bitbucket) printf 'pipelines:\n  default:\n    - step:\n        script:\n          - echo hi\n' >"$d/bitbucket-pipelines.yml" ;;
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

echo "Jenkins, vendored"
D="$(repo jenkins)"
cp "$D/Jenkinsfile" "$D/jenkinsfile.orig"
check_output "a Jenkinsfile is detected and the gates vendored" 0 "created $V/MANIFEST" "$I" "$D"
check "the vendored MANIFEST verifies" 0 "$D/$V/bin/prumo-vendor-verify"
check "Jenkins groovy vendored byte for byte" 0 same_bytes templates/ci/jenkins/prumo-vendored.groovy "$D/$V/ci/jenkins.groovy"
check "the Jenkinsfile is never edited" 0 cmp "$D/Jenkinsfile" "$D/jenkinsfile.orig"
check_output "the snippet to paste names the vendored groovy" 0 "$V/ci/jenkins.groovy" "$I" "$D"
check_output "the snippet names the entry point" 0 "prumoGates" "$I" "$D"
before="$(snapshot "$D")"; "$I" "$D" >/dev/null 2>&1; after="$(snapshot "$D")"
check "second Jenkins run changes not one byte" 0 test "$before" = "$after"

D="$(repo jenkins-dir)"
check_output "a Jenkinsfile under pipelines/ is detected" 0 "created $V/MANIFEST" "$I" "$D"
check "groovy vendored for a Jenkinsfile under pipelines/" 0 test -f "$D/$V/ci/jenkins.groovy"

D="$(repo jenkins-wired)"
check_output "a Jenkinsfile that already loads the groovy is reported kept" 0 "kept Jenkinsfile" "$I" "$D"

echo "the vendored Jenkins gates replay locally"
# replay <repo>: runs every unconditional `sh '...'` payload of the vendored
# groovy inside the repository, with the environment the template sets. The
# anti-leak payload is left out because the template runs it only when
# PRUMO_ANTI_LEAK is "on"; a case below proves that gate sits behind the if.
replay() {
  local d="$1" cmds rc=0 c
  cmds="$(python3 - "$d/$V/ci/jenkins.groovy" <<'PY'
import re, sys
for m in re.finditer(r"sh\s+'([^']*)'", open(sys.argv[1], encoding="utf-8").read()):
    if "anti-leak.sh" not in m.group(1):
        print(m.group(1))
PY
)"
  [ -n "$cmds" ] || { echo "no sh payload found in the groovy"; return 1; }
  while IFS= read -r c; do
    (cd "$d" && PRUMO_VENDOR_DIR="$V" PRUMO_FAIL_CLOSED_DIRS="." PRUMO_ANTI_LEAK="off" \
      PRUMO_ANTI_LEAK_ARGS="." sh -c "$c") || rc=1
  done <<<"$cmds"
  return "$rc"
}
D="$(repo jenkins)"
"$I" "$D" >/dev/null 2>&1
mkdir -p "$D/tests" "$D/src/billing"
printf '#!/bin/sh\n# PRUMO: CORE-01\ntest "$(echo ok)" = ok\n' >"$D/tests/core_test.sh"
printf '  - name: billing\n    path: src/billing\n    usage_metric: invoices per day\n    since: 2026-09-01\n' >>"$D/.prumo/subsystems.yml"
printf 'def serve():\n    return 0\n' >"$D/src/billing/app.py"
check "a wired repository passes every Jenkins gate on replay" 0 replay "$D"
check "the anti-leak gate sits behind PRUMO_ANTI_LEAK" 0 \
  grep -qE 'if \(.*PRUMO_ANTI_LEAK.*== *.on.' "$D/$V/ci/jenkins.groovy"
printf 'X' >>"$D/$V/lib/prumo_trace.py"
check "a drifted vendor directory fails the replay before any gate" 1 replay "$D"
check_output "rerun restores the drifted vendor directory" 0 "updated $V" "$I" "$D"
check "the restored vendor directory replays green again" 0 replay "$D"

echo "Bitbucket Cloud, vendored"
D="$(repo bitbucket)"
cp "$D/bitbucket-pipelines.yml" "$D/pipelines.orig"
check_output "an unwired bitbucket-pipelines.yml is refused with the snippet" 1 "by hand" "$I" "$D"
check "the existing pipelines file is left byte for byte" 0 cmp "$D/bitbucket-pipelines.yml" "$D/pipelines.orig"
check "that refusal writes nothing" 0 test ! -e "$D/.prumo"
check_output "--force-ci bitbucket does not override that refusal" 1 "by hand" "$I" --force-ci bitbucket "$D"
D="$(repo none)"
check_output "--force-ci bitbucket creates bitbucket-pipelines.yml" 0 "created bitbucket-pipelines.yml" "$I" --force-ci bitbucket "$D"
check "the created file is the vendored template byte for byte" 0 same_bytes templates/ci/bitbucket/prumo-vendored.yml "$D/bitbucket-pipelines.yml"
check "bitbucket-pipelines.yml reaches no network" 0 no_network "$D/bitbucket-pipelines.yml"
check "the MANIFEST verifies in a Bitbucket repository" 0 "$D/$V/bin/prumo-vendor-verify"
check_output "second Bitbucket run is a no-op" 0 "kept bitbucket-pipelines.yml" "$I" "$D"

echo "the vendored Bitbucket steps replay locally"
# replay_yaml <repo> <file>: runs every single-quoted script line of a Bitbucket
# pipelines file inside the repository, in order, with the variables the
# template defaults. The anti-leak invocation is left out because the template
# runs it only when PRUMO_ANTI_LEAK is "on"; the line that skips when the
# variable is off does run, and prints that it skipped.
replay_yaml() {
  local d="$1" f="$2" cmds rc=0 c
  cmds="$(python3 - "$d/$f" <<'PY'
import re, sys
for line in open(sys.argv[1], encoding="utf-8"):
    m = re.match(r"\s*-\s*'(.*)'\s*$", line)
    if m and "anti-leak.sh" not in m.group(1):
        print(m.group(1))
PY
)"
  [ -n "$cmds" ] || { echo "no script line found in $f"; return 1; }
  while IFS= read -r c; do
    (cd "$d" && PRUMO_VENDOR_DIR="$V" PRUMO_FAIL_CLOSED_DIRS="." PRUMO_ANTI_LEAK="off" \
      PRUMO_ANTI_LEAK_ARGS="." sh -c "$c") || rc=1
  done <<<"$cmds"
  return "$rc"
}
D="$(repo none)"
"$I" --force-ci bitbucket "$D" >/dev/null 2>&1
mkdir -p "$D/tests" "$D/src/billing"
printf '#!/bin/sh\n# PRUMO: CORE-01\ntest "$(echo ok)" = ok\n' >"$D/tests/core_test.sh"
printf '  - name: billing\n    path: src/billing\n    usage_metric: invoices per day\n    since: 2026-09-01\n' >>"$D/.prumo/subsystems.yml"
printf 'def serve():\n    return 0\n' >"$D/src/billing/app.py"
check "a Bitbucket repository passes every gate on replay" 0 replay_yaml "$D" bitbucket-pipelines.yml
printf 'X' >>"$D/$V/lib/prumo_trace.py"
check "a drifted vendor directory fails the Bitbucket replay before a gate" 1 replay_yaml "$D" bitbucket-pipelines.yml
check_output "rerun restores the vendor directory of a Bitbucket repository" 0 "updated $V" "$I" --force-ci bitbucket "$D"
check "the restored Bitbucket repository replays green again" 0 replay_yaml "$D" bitbucket-pipelines.yml

finish
