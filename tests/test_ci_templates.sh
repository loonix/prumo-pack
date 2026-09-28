#!/usr/bin/env bash
# CI templates: the GitLab include, the GitHub reusable workflow, its consumer
# stub and the pack's own CI. A template that parses but cannot fail, or that
# calls a script the pack does not ship, is a gate that bites nothing.
. "$(dirname "$0")/lib.sh"

GITLAB="templates/ci/gitlab/prumo.yml"
GH_REUSABLE=".github/workflows/prumo.yml"
GH_STUB="templates/ci/github/prumo.yml"
GH_CI=".github/workflows/ci.yml"
GITLAB_VENDORED="templates/ci/gitlab/prumo-vendored.yml"
GH_VENDORED="templates/ci/github/prumo-vendored.yml"
TEMPLATES="$GITLAB $GH_REUSABLE $GH_STUB $GH_CI $GITLAB_VENDORED $GH_VENDORED"

# Scripts built in parallel on other branches (anti-leak has landed, the other
# two may not have). A template may call them before they land; any other
# missing path is a failure.
PENDING_SCRIPTS="checks/anti-leak.sh bin/prumo-init bin/prumo-certify"

HAVE_YAML=0
if python3 -c 'import yaml' 2>/dev/null; then HAVE_YAML=1; fi

# yaml_parses <file>: full parse with PyYAML.
yaml_parses() {
  python3 -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1]))' "$PACK_ROOT/$1"
}

# yaml_structure <file>: minimal stdlib check used whether or not PyYAML is
# present. Not a parser: non-empty, no tabs, even indentation, at least one top
# level key, balanced ${{ }} expressions.
yaml_structure() {
  python3 - "$PACK_ROOT/$1" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
errors = []
if not text.strip():
    errors.append("empty file")
top = 0
for n, line in enumerate(text.splitlines(), 1):
    if "\t" in line:
        errors.append("line %d: tab character" % n)
    body = line.lstrip(" ")
    if not body or body.startswith("#"):
        continue
    indent = len(line) - len(body)
    if indent % 2:
        errors.append("line %d: odd indentation (%d)" % (n, indent))
    if indent == 0 and re.match(r"^[A-Za-z_.][A-Za-z0-9_.-]*:", body):
        top += 1
    if line.count("${{") != line.count("}}"):
        errors.append("line %d: unbalanced ${{ }}" % n)
if top == 0:
    errors.append("no top level key")
for e in errors:
    print(e)
sys.exit(1 if errors else 0)
PY
}

# no_soft_failure <file>: no allow_failure: true, no continue-on-error: true.
# A missing file is exit 2, not a pass.
no_soft_failure() {
  [ -f "$PACK_ROOT/$1" ] || return 2
  ! grep -nE '^[^#]*(allow_failure|continue-on-error):[[:space:]]*(true|"true"|yes)' "$PACK_ROOT/$1"
}

# script_refs_resolve <file>: every bin/... or checks/... path the file names
# exists in the pack or is one of the pending scripts. Zero references is a
# failure for files that are supposed to run the checks.
script_refs_resolve() {
  python3 - "$PACK_ROOT" "$1" "$PENDING_SCRIPTS" <<'PY'
import os, re, sys
root, rel, pending = sys.argv[1], sys.argv[2], set(sys.argv[3].split())
text = open(os.path.join(root, rel)).read()
# A dot that ends a sentence is not part of the path.
refs = sorted(set(r.rstrip(".") for r in re.findall(r"(?<![A-Za-z0-9_.-])((?:bin|checks)/[A-Za-z0-9_.-]+)", text)))
bad = [r for r in refs if not os.path.exists(os.path.join(root, r)) and r not in pending]
for r in bad:
    print("unknown script path: " + r)
if not refs:
    print("no bin/ or checks/ path referenced")
sys.exit(1 if bad or not refs else 0)
PY
}

# jobs_call_scripts <file> <job...>: each named job exists at the expected
# nesting and its block names at least one bin/ or checks/ path or a make target.
jobs_call_scripts() {
  python3 - "$PACK_ROOT/$1" "${@:2}" <<'PY'
import re, sys
path, jobs = sys.argv[1], sys.argv[2:]
lines = open(path).read().splitlines()
bad = []
for job in jobs:
    start = None
    for i, l in enumerate(lines):
        m = re.match(r"^( *)" + re.escape(job) + r":\s*$", l)
        if m:
            start, indent = i, len(m.group(1))
            break
    if start is None:
        bad.append("job %s not found" % job)
        continue
    block = []
    for l in lines[start + 1:]:
        body = l.lstrip(" ")
        if body and not body.startswith("#") and len(l) - len(body) <= indent:
            break
        if not body.startswith("#"):
            block.append(l)
    text = "\n".join(block)
    if not re.search(r"(bin|checks)/[A-Za-z0-9_.-]+|\bmake [a-z]", text):
        bad.append("job %s calls no pack script" % job)
for b in bad:
    print(b)
sys.exit(1 if bad else 0)
PY
}

# make_targets_exist <file>: every `make <target>` names a Makefile target.
make_targets_exist() {
  python3 - "$PACK_ROOT" "$1" <<'PY'
import os, re, sys
root, rel = sys.argv[1], sys.argv[2]
targets = set(re.findall(r"^([A-Za-z0-9_.-]+):", open(os.path.join(root, "Makefile")).read(), re.M))
used = set(re.findall(r"\bmake ([A-Za-z0-9_.-]+)", open(os.path.join(root, rel)).read()))
bad = sorted(used - targets)
for b in bad:
    print("unknown make target: " + b)
if not used:
    print("no make target used")
sys.exit(1 if bad or not used else 0)
PY
}

# declares_workflow_call <file>: `on:` at top level with workflow_call under it.
# A missing file is exit 2, so "does not declare" cannot pass on absence.
declares_workflow_call() {
  [ -f "$PACK_ROOT/$1" ] || return 2
  python3 - "$PACK_ROOT/$1" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
m = re.search(r"^on:\s*\n((?:[ #].*\n|\n)*)", text, re.M)
sys.exit(0 if m and re.search(r"^  workflow_call:", m.group(1), re.M) else 1)
PY
}

echo "templates exist and are structurally sound"
for t in $TEMPLATES; do
  check "$t exists" 0 test -f "$PACK_ROOT/$t"
  check "$t passes the minimal structure check" 0 yaml_structure "$t"
  if [ "$HAVE_YAML" = 1 ]; then
    check "$t parses as YAML" 0 yaml_parses "$t"
  else
    skip "$t parses as YAML" "PyYAML not installed, only the minimal structure check ran"
  fi
done

echo "no soft failure"
for t in $TEMPLATES; do
  check "$t has no allow_failure/continue-on-error true" 0 no_soft_failure "$t"
done
D="$(tmpdir)"
mkdir -p "$D/t"
printf 'job:\n  script: [x]\n  allow_failure: true\n' >"$D/t/bad.yml"
check "the soft failure check bites on allow_failure: true" 1 env PACK_ROOT="$D" bash -c "$(declare -f no_soft_failure); no_soft_failure t/bad.yml"

echo "script paths resolve"
for t in $GITLAB $GH_REUSABLE $GITLAB_VENDORED $GH_VENDORED; do
  check "$t names only shipped or pending scripts" 0 script_refs_resolve "$t"
done
# The pack's own CI calls make targets; the scripts behind them are in the Makefile.
check "Makefile names only shipped or pending scripts" 0 script_refs_resolve Makefile
printf 'job:\n  script: [bin/prumo-ghost]\n' >"$D/t/ghost.yml"
mkdir -p "$D/bin"
check "the path check bites on a script that does not exist" 1 env PACK_ROOT="$D" PENDING_SCRIPTS="" bash -c "$(declare -f script_refs_resolve); script_refs_resolve t/ghost.yml"
check "$GITLAB jobs each call a pack script" 0 jobs_call_scripts "$GITLAB" prumo-trace prumo-fail-closed prumo-metabolic prumo-anti-leak
check "$GH_REUSABLE jobs each call a pack script" 0 jobs_call_scripts "$GH_REUSABLE" prumo-trace prumo-fail-closed prumo-metabolic prumo-anti-leak
check "$GH_CI make targets exist in the Makefile" 0 make_targets_exist "$GH_CI"
# The pack's own fixtures contain addresses on purpose, so its CI runs the
# Makefile target that carries the hashed deny list and the fixture excludes.
check "$GH_CI runs make leak unguarded" 0 grep -qE '^ *run: make leak$' "$PACK_ROOT/$GH_CI"
check "$GH_STUB calls the reusable workflow by its real path" 0 grep -qE "uses: loonix/prumo-pack/$GH_REUSABLE@" "$PACK_ROOT/$GH_STUB"

echo "vendored templates"
check "$GITLAB_VENDORED jobs each call a pack script" 0 jobs_call_scripts "$GITLAB_VENDORED" prumo-trace prumo-fail-closed prumo-metabolic prumo-anti-leak
check "$GH_VENDORED jobs each call a pack script" 0 jobs_call_scripts "$GH_VENDORED" prumo-trace prumo-fail-closed prumo-metabolic prumo-anti-leak
check "$GITLAB_VENDORED verifies the MANIFEST before every job" 0 grep -qE 'before_script:' "$PACK_ROOT/$GITLAB_VENDORED"
check "$GH_VENDORED verifies the MANIFEST in all 4 jobs" 0 test "$(grep -c 'bin/prumo-vendor-verify' "$PACK_ROOT/$GH_VENDORED")" = 4
for t in $GITLAB_VENDORED $GH_VENDORED; do
  check "$t reaches no network for the pack" 1 grep -nE '^[^#]*(remote:|git (clone|fetch)|repository: *loonix)' "$PACK_ROOT/$t"
done
check "$GH_VENDORED gates anti-leak on a step, not a job level env if" 1 grep -qE '^    if: env\.' "$PACK_ROOT/$GH_VENDORED"

echo "reusable workflow"
check "$GH_REUSABLE declares workflow_call" 0 declares_workflow_call "$GH_REUSABLE"
check "$GH_REUSABLE declares input fail_closed_dirs" 0 grep -qE '^      fail_closed_dirs:' "$PACK_ROOT/$GH_REUSABLE"
for i in pack_ref anti_leak anti_leak_args; do
  check "$GH_REUSABLE declares input $i" 0 grep -qE "^      $i:" "$PACK_ROOT/$GH_REUSABLE"
done
check "$GH_CI does not declare workflow_call" 1 declares_workflow_call "$GH_CI"

echo "gitlab variables"
for v in PRUMO_PACK_URL PRUMO_PACK_REF PRUMO_FAIL_CLOSED_DIRS PRUMO_ANTI_LEAK PRUMO_ANTI_LEAK_ARGS; do
  check "$GITLAB declares $v" 0 grep -qE "^  $v:" "$PACK_ROOT/$GITLAB"
done
check "$GITLAB pins the pack at v0 by default" 0 grep -qE '^  PRUMO_PACK_REF: "?v0"?$' "$PACK_ROOT/$GITLAB"
# anti-leak is opt in (a project needs its own deny list first), but once on
# it is a gate like the others: no allow_failure, covered above.
check "$GITLAB anti-leak job is off by default" 0 grep -qE '^  PRUMO_ANTI_LEAK: "?off"?$' "$PACK_ROOT/$GITLAB"
check "$GITLAB anti-leak job runs only when switched on" 0 grep -qF '$PRUMO_ANTI_LEAK == "on"' "$PACK_ROOT/$GITLAB"
check "$GH_REUSABLE anti-leak job runs only when switched on" 0 grep -qF 'if: inputs.anti_leak' "$PACK_ROOT/$GH_REUSABLE"

finish
