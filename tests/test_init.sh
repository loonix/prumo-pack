#!/usr/bin/env bash
# bin/prumo-init: scaffolds .prumo/ from templates/.prumo/, never overwrites a
# file, and refuses to install without CI unless told so explicitly. Every case
# builds its repository in a temporary directory.
. "$(dirname "$0")/lib.sh"

I="$PACK_ROOT/bin/prumo-init"
T="$PACK_ROOT/bin/prumo-trace"
M="$PACK_ROOT/checks/metabolic.sh"
FC="$PACK_ROOT/checks/fail-closed.sh"
GITLAB_FILE="templates/ci/gitlab/prumo.yml"
GITHUB_USES="loonix/prumo-pack/.github/workflows/prumo.yml@v0"

# repo <ci>: a new repository with a GitLab file, a .github/ directory, both or
# nothing.
repo() {
  local d
  d="$(tmpdir)"
  case "$1" in
    gitlab) printf 'stages: [test]\n' >"$d/.gitlab-ci.yml" ;;
    github) mkdir -p "$d/.github" ;;
    both) printf 'stages: [test]\n' >"$d/.gitlab-ci.yml"; mkdir -p "$d/.github" ;;
    none) ;;
  esac
  printf '%s' "$d"
}

# Fingerprint of every file (path and content) under a directory.
snapshot() {
  (cd "$1" && find . -type f | LC_ALL=C sort | while read -r f; do
    printf '%s ' "$f"; cksum <"$f"
  done)
}

# scaffold_complete <repo>: every file the pack promises exists.
scaffold_complete() {
  local f
  for f in README.md regression-rules/RR-001-core-invariants.md specs/SPEC-template.md \
    environment-contracts/README.md execution-contracts/README.md subsystems.yml \
    fail-closed.patterns; do
    [ -f "$1/.prumo/$f" ] || { echo "missing .prumo/$f"; return 1; }
  done
}

# no_prumo <repo>: a refusal wrote nothing.
no_prumo() { [ ! -e "$1/.prumo" ] || { echo ".prumo was created"; return 1; }; }

# count_is <n> <fixed string> <file>
count_is() {
  local got
  got="$(grep -cF -- "$2" "$3")"
  [ "$got" = "$1" ] || { echo "expected $1 occurrence(s) of '$2' in $3, got $got"; return 1; }
}

# second_run_is_noop <repo> [flags...]: exit 0, nothing created or updated, and
# not one byte changed.
second_run_is_noop() {
  local d="$1" before after out
  shift
  before="$(snapshot "$d")"
  out="$("$I" "$@" "$d" 2>&1)" || { echo "second run exited $?"; echo "$out"; return 1; }
  after="$(snapshot "$d")"
  echo "$out"
  if printf '%s\n' "$out" | grep -qE '^(created|updated) '; then
    echo "second run wrote something"; return 1
  fi
  [ "$before" = "$after" ] || { echo "second run changed the tree"; return 1; }
}

echo "usage errors"
check_output "no argument is a usage error" 2 "usage" "$I"
check_output "missing repository is a usage error" 2 "does not exist" "$I" "$(tmpdir)/nope"
check_output "unknown flag is a usage error" 2 "usage" "$I" --bogus "$(repo gitlab)"
check_output "unknown --force-ci value is a usage error" 2 "gitlab|github|none" "$I" --force-ci jenkins "$(repo none)"
check_output "--force-ci without a value is a usage error" 2 "usage" "$I" --force-ci
check_output "two repositories is a usage error" 2 "usage" "$I" "$(repo gitlab)" "$(repo gitlab)"

echo "no CI is refused (decorative Prumo)"
D="$(repo none)"
check_output "no CI detected is refused" 1 "no CI detected" "$I" "$D"
check "refusal writes nothing" 0 no_prumo "$D"
D="$(repo none)"
check_output "--force-ci none installs with a warning" 0 "WARNING" "$I" --force-ci none "$D"
check "--force-ci none scaffolds .prumo" 0 scaffold_complete "$D"
check "--force-ci none wires no CI" 0 test ! -e "$D/.gitlab-ci.yml" -a ! -e "$D/.github"

echo "GitLab"
D="$(repo gitlab)"
check_output "GitLab repository is detected" 0 "updated .gitlab-ci.yml" "$I" "$D"
check "GitLab scaffold is complete" 0 scaffold_complete "$D"
check "include of the GitLab template appended once" 0 count_is 1 "$GITLAB_FILE" "$D/.gitlab-ci.yml"
check "include uses the documented project variable" 0 grep -qF 'PRUMO_PACK_PROJECT' "$D/.gitlab-ci.yml"
check "existing GitLab content kept on line 1" 0 test "$(head -1 "$D/.gitlab-ci.yml")" = "stages: [test]"
check_output "second GitLab run is a no-op" 0 "0 created, 0 updated" second_run_is_noop "$D"
check "include not duplicated by the second run" 0 count_is 1 "$GITLAB_FILE" "$D/.gitlab-ci.yml"

D="$(repo none)"
printf 'include:\n  - local: ci/build.yml\nstages: [test]\n' >"$D/.gitlab-ci.yml"
check "existing include list gets the item, not a second key" 0 "$I" "$D"
check "one top level include key" 0 test "$(grep -c '^include:' "$D/.gitlab-ci.yml")" = 1
check "existing include item kept" 0 grep -qF 'local: ci/build.yml' "$D/.gitlab-ci.yml"
check "template item added to the list" 0 count_is 1 "$GITLAB_FILE" "$D/.gitlab-ci.yml"

D="$(repo none)"
printf "include: 'ci/build.yml'\n" >"$D/.gitlab-ci.yml"
cp "$D/.gitlab-ci.yml" "$D/original.yml"
check_output "scalar include cannot be extended safely, refused" 1 "$GITLAB_FILE" "$I" "$D"
check "scalar include file left byte for byte" 0 cmp "$D/.gitlab-ci.yml" "$D/original.yml"
check "scalar include refusal writes nothing" 0 no_prumo "$D"

D="$(repo none)"
printf 'include:\n  local: ci/build.yml\n' >"$D/.gitlab-ci.yml"
cp "$D/.gitlab-ci.yml" "$D/original.yml"
check_output "map include cannot be extended safely, refused" 1 "by hand" "$I" "$D"
check "map include file left byte for byte" 0 cmp "$D/.gitlab-ci.yml" "$D/original.yml"
check "map include refusal writes nothing" 0 no_prumo "$D"

D="$(repo none)"
printf 'include:\n  - project: group/prumo-pack\n    file: %s\n' "$GITLAB_FILE" >"$D/.gitlab-ci.yml"
cp "$D/.gitlab-ci.yml" "$D/original.yml"
check_output "include already present by hand is kept" 0 "kept .gitlab-ci.yml" "$I" "$D"
check "hand written include left byte for byte" 0 cmp "$D/.gitlab-ci.yml" "$D/original.yml"

D="$(repo none)"
printf 'stages: [test]' >"$D/.gitlab-ci.yml"
check "file without final newline" 0 "$I" "$D"
check "include lands on its own line" 0 grep -q '^include:' "$D/.gitlab-ci.yml"

D="$(repo none)"
check_output "--force-ci gitlab creates .gitlab-ci.yml" 0 "created .gitlab-ci.yml" "$I" --force-ci gitlab "$D"
check "created .gitlab-ci.yml has the include" 0 count_is 1 "$GITLAB_FILE" "$D/.gitlab-ci.yml"

echo "GitHub"
D="$(repo github)"
check_output "GitHub repository is detected" 0 "created .github/workflows/prumo.yml" "$I" "$D"
check "GitHub scaffold is complete" 0 scaffold_complete "$D"
check "workflow calls the reusable workflow" 0 grep -qF "uses: $GITHUB_USES" "$D/.github/workflows/prumo.yml"
check_output "second GitHub run is a no-op" 0 "0 created, 0 updated" second_run_is_noop "$D"

D="$(repo github)"
mkdir -p "$D/.github/workflows"
printf 'name: mine\n# no trailing newline' >"$D/.github/workflows/prumo.yml"
cp "$D/.github/workflows/prumo.yml" "$D/original.yml"
check_output "existing workflow is kept" 0 "kept .github/workflows/prumo.yml" "$I" "$D"
check "existing workflow left byte for byte" 0 cmp "$D/.github/workflows/prumo.yml" "$D/original.yml"

D="$(repo none)"
check_output "--force-ci github creates the workflow" 0 "created .github/workflows/prumo.yml" "$I" --force-ci github "$D"

D="$(repo both)"
check "both CI systems detected" 0 "$I" "$D"
check "both: GitLab wired" 0 count_is 1 "$GITLAB_FILE" "$D/.gitlab-ci.yml"
check "both: GitHub wired" 0 test -f "$D/.github/workflows/prumo.yml"

D="$(repo github)"
check "--force-ci gitlab wires only GitLab" 0 "$I" --force-ci gitlab "$D"
check "--force-ci gitlab leaves .github alone" 0 test ! -e "$D/.github/workflows"

echo "existing files are never overwritten"
D="$(repo gitlab)"
mkdir -p "$D/.prumo/regression-rules"
printf -- '- `SEC-01` : **ACTIVE** : mine, no final newline' >"$D/.prumo/regression-rules/RR-001-core-invariants.md"
printf 'roots: [lib]\n' >"$D/.prumo/subsystems.yml"
cp "$D/.prumo/regression-rules/RR-001-core-invariants.md" "$D/rr.orig"
cp "$D/.prumo/subsystems.yml" "$D/sub.orig"
check_output "existing rules file reported as kept" 0 "kept .prumo/regression-rules/RR-001-core-invariants.md" "$I" "$D"
check "existing rules file left byte for byte" 0 cmp "$D/.prumo/regression-rules/RR-001-core-invariants.md" "$D/rr.orig"
check "existing subsystems.yml left byte for byte" 0 cmp "$D/.prumo/subsystems.yml" "$D/sub.orig"
check "missing files still created around the kept ones" 0 scaffold_complete "$D"

echo "templates"
D="$(repo none)"
"$I" --force-ci none "$D" >/dev/null 2>&1
check "README describes the 9 layers" 0 grep -q '^## Layer 9' "$D/.prumo/README.md"
check "README has no tenth layer" 1 grep -q '^## Layer 10' "$D/.prumo/README.md"
check "fail-closed.patterns declares no pattern" 1 grep -qv '^#' "$D/.prumo/fail-closed.patterns"

echo "fresh repository against the checks"
D="$(repo gitlab)"
"$I" "$D" >/dev/null 2>&1
check_output "fresh rules are read, CORE-01 waits for its test" 1 "CORE-01" "$T" --root "$D"
mkdir -p "$D/tests"
printf '#!/bin/sh\n# PRUMO: CORE-01\ntest "$(echo ok)" = ok\n' >"$D/tests/core_test.sh"
check_output "one tagged test passes prumo-trace" 0 "1 declared (1 active" "$T" --root "$D"
check_output "skeleton subsystems.yml is read and needs user input" 1 "no subsystem declared" "$M" "$D"
mkdir -p "$D/src/billing"
printf '  - name: billing\n    path: src/billing\n    usage_metric: invoices created per day\n    since: 2026-09-01\n' \
  >>"$D/.prumo/subsystems.yml"
check_output "subsystems filled by the user pass metabolic" 0 "1 subsystem(s) declared" "$M" "$D"
printf 'def serve():\n    return 0\n' >"$D/src/billing/app.py"
check_output "comment-only fail-closed.patterns is accepted" 0 "fail-closed: OK" "$FC" "$D"

finish
