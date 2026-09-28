#!/usr/bin/env bash
# checks/metabolic.sh: every subsystem declares how its usage is measured, or it
# does not grow. Each rule has a fixture that breaks it on purpose.
. "$(dirname "$0")/lib.sh"

C="$PACK_ROOT/checks/metabolic.sh"
F="$PACK_ROOT/tests/fixtures/metabolic"

echo "violations"
check_output "subsystem without usage_metric fails" 1 "voice" "$C" "$F/missing-metric"
check_output "placeholder usage_metric fails" 1 "placeholder" "$C" "$F/placeholder-metric"
check_output "directory under a root with no declaration fails" 1 "src/voice" "$C" "$F/undeclared-dir"
check_output "declared path that does not exist fails" 1 "src/legacy" "$C" "$F/ghost-path"
check_output "name declared twice fails" 1 "billing declared twice" "$C" "$F/duplicate-name"
check_output "subsystem covering a whole root fails" 1 "covers the whole root" "$C" "$F/root-as-subsystem"
check_output "unknown top level key fails (typo is not silence)" 1 "unknown key 'subsytems'" "$C" "$F/unknown-key"
D="$(tmpdir)"
mkdir -p "$D/.prumo" "$D/src/billing"
printf 'roots: [src]\nsubsystems:\n  - name: billing\n    path: src/billing\n    usage_metric: invoices per day\nthis is not yaml\n' \
  >"$D/.prumo/subsystems.yml"
check_output "unparsable line fails" 1 "cannot parse line 6" "$C" "$D"

echo "good cases"
check_output "compliant repository passes" 0 "2 subsystem(s) declared" "$C" "$F/good"
check_output "block list roots pass, missing since is only a note" 0 "no 'since'" "$C" "$F/block-roots"
check_output "--manifest reads another file" 0 "2 subsystem(s) declared" \
  "$C" --manifest "$F/good/.prumo/subsystems.yml" "$F/good"

echo "fails closed on itself"
check_output "missing manifest fails" 1 "no manifest" "$C" "$F/no-manifest"
check_output "manifest without roots fails" 1 "no roots" "$C" "$F/no-roots"
check_output "manifest without subsystems fails" 1 "no subsystem" "$C" "$F/no-subsystems"
check_output "declared root that does not exist fails" 1 "root 'services' does not exist" "$C" "$F/missing-root"
D="$(tmpdir)"
mkdir -p "$D/.prumo" "$D/src"
printf 'roots: [src]\nsubsystems:\n  - name: x\n    path: src/x\n    usage_metric: y per day\n' >"$D/.prumo/subsystems.yml"
check_output "root with zero directories fails (nothing scanned)" 1 "zero directories" "$C" "$D"
check_output "missing repository root is a usage error" 2 "does not exist" "$C" "$F/does-not-exist"
check_output "missing --manifest file fails" 1 "no manifest" "$C" --manifest "$F/good/nope.yml" "$F/good"

finish
