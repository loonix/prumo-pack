#!/usr/bin/env bash
# Project-scope agent gates: prumo-init vendors the PreToolUse hooks and
# registers them in the repository's .claude/settings.json, so a session opened
# in that repository is gated without anyone installing the plugin at user
# scope. The registration is proven live: the command taken out of the written
# settings.json is executed with a real PreToolUse event and must block.
. "$(dirname "$0")/lib.sh"

I="$PACK_ROOT/bin/prumo-init"
V=".prumo/vendor"
HK="$PACK_ROOT/agent/claude-plugin/hooks"
SETTINGS=".claude/settings.json"
HOOKS="_common.py no_em_dash.py ci_soft_fail.py protected_push.py"

DASH="$(printf '\xe2\x80\x94')"

repo() {
  local d
  d="$(tmpdir)"
  printf 'stages: [test]\n' >"$d/.gitlab-ci.yml"
  git init -q "$d"
  printf '%s' "$d"
}

snapshot() {
  (cd "$1" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | while read -r f; do
    printf '%s ' "$f"; cksum <"$f"
  done)
}

same_bytes() { cmp "$HK/$1" "$2"; }

# exactly <n> <pattern> <file>: the pattern occurs exactly n times.
exactly() {
  local n
  n="$(grep -c -- "$2" "$3")"
  [ "$n" = "$1" ] || { echo "occurrences of '$2': $n, want $1"; return 1; }
}

# absent <path>
absent() { if [ -e "$1" ]; then echo "$1 exists"; return 1; fi; }

# not_contains <pattern> <file>
not_contains() {
  if grep -qF -- "$1" "$2"; then echo "'$1' found in $2"; return 1; fi
}

# output_not_contains <pattern> <command...>: the command's output, stdout and
# stderr together, does not carry the pattern.
output_not_contains() {
  local pat="$1" out
  shift
  out="$("$@" 2>&1)"
  if printf '%s' "$out" | grep -qF -- "$pat"; then
    echo "'$pat' appeared in the output"; return 1
  fi
}

# commands <settings.json>: every PreToolUse command, one per line.
commands() {
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
for e in d.get("hooks", {}).get("PreToolUse", []):
    for h in e.get("hooks", []):
        print(h.get("command", ""))
' "$1"
}

# matcher_of <settings.json> <hook basename>: the matcher of the entry that
# registers that hook.
matcher_of() {
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
for e in d.get("hooks", {}).get("PreToolUse", []):
    for h in e.get("hooks", []):
        if sys.argv[2] in h.get("command", ""):
            print(e.get("matcher", ""))
' "$1" "$2"
}

# fire <repo> <hook basename> <event json>: runs the command the generated
# settings.json registers for that hook, the way Claude Code runs it.
fire() {
  local cmd
  cmd="$(commands "$1/$SETTINGS" | grep -F -- "$2" | head -1)"
  if [ -z "$cmd" ]; then echo "no registered command for $2"; return 9; fi
  printf '%s' "$3" | (cd "$1" && CLAUDE_PROJECT_DIR="$1" bash -c "$cmd")
}

write_event() {
  printf '{"tool_name":"Write","tool_input":{"file_path":"t.md","content":"%s"},"cwd":"%s"}' "$2" "$1"
}

echo "vendored hooks"
D="$(repo)"
check_output "vendor run reports the settings file" 0 "created $SETTINGS" "$I" "$D"
for f in $HOOKS; do
  check "$f vendored byte for byte" 0 same_bytes "$f" "$D/$V/hooks/$f"
done
check "vendored hooks verify against the MANIFEST" 0 "$D/$V/bin/prumo-vendor-verify"
check "MANIFEST lists the vendored hooks" 0 exactly 1 "hooks/no_em_dash.py" "$D/$V/MANIFEST"

echo "registration shape"
check "settings.json parses as JSON" 0 python3 -m json.tool "$D/$SETTINGS"
check_output "no_em_dash registered" 0 "$V/hooks/no_em_dash.py" commands "$D/$SETTINGS"
check_output "ci_soft_fail registered" 0 "$V/hooks/ci_soft_fail.py" commands "$D/$SETTINGS"
check_output "protected_push registered" 0 "$V/hooks/protected_push.py" commands "$D/$SETTINGS"
check_output "file hooks match Write|Edit|MultiEdit" 0 "Write|Edit|MultiEdit" matcher_of "$D/$SETTINGS" no_em_dash.py
check_output "push hook matches Bash" 0 "Bash" matcher_of "$D/$SETTINGS" protected_push.py
check_output "registration is project-relative, not absolute" 0 'CLAUDE_PROJECT_DIR' commands "$D/$SETTINGS"
check "each hook registered exactly once" 0 exactly 1 "no_em_dash.py" "$D/$SETTINGS"

echo "the registration bites"
check "registered no_em_dash blocks an em dash Write" 2 fire "$D" no_em_dash.py "$(write_event "$D" "hello ${DASH} world")"
check "registered no_em_dash allows a clean Write" 0 fire "$D" no_em_dash.py "$(write_event "$D" "hello, world")"
check "registered ci_soft_fail blocks a soft-failing pipeline" 2 fire "$D" ci_soft_fail.py \
  "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"bitbucket-pipelines.yml\",\"content\":\"script:\\n  - ./anti-leak.sh || true\\n\"},\"cwd\":\"$D\"}"
check "registered protected_push blocks a push to main" 2 fire "$D" protected_push.py \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push origin main\"},\"cwd\":\"$D\"}"
check "registered protected_push allows a topic branch" 0 fire "$D" protected_push.py \
  "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git push origin feat/x\"},\"cwd\":\"$D\"}"

echo "idempotent"
check_output "second run keeps the settings file" 0 "kept $SETTINGS" "$I" "$D"
before="$(snapshot "$D")"; "$I" "$D" >/dev/null 2>&1; after="$(snapshot "$D")"
check "a third run changes not one byte" 0 test "$before" = "$after"
check "still registered exactly once after three runs" 0 exactly 1 "no_em_dash.py" "$D/$SETTINGS"

echo "an existing settings.json is merged, not clobbered"
D="$(repo)"
mkdir -p "$D/.claude"
cat >"$D/$SETTINGS" <<'JSON'
{
  "model": "opus",
  "permissions": {"allow": ["Bash(ls:*)"]},
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "/opt/other/guard.sh"}]},
      {"matcher": "Write|Edit|MultiEdit", "hooks": [{"type": "command", "command": "/opt/other/lint.py"}]}
    ],
    "PostToolUse": [{"matcher": "Write", "hooks": [{"type": "command", "command": "/opt/other/after.sh"}]}]
  }
}
JSON
check_output "merge run updates the settings file" 0 "updated $SETTINGS" "$I" "$D"
check_output "an unrelated key survives" 0 '"model": "opus"' cat "$D/$SETTINGS"
check_output "an unrelated permission survives" 0 'Bash(ls:*)' cat "$D/$SETTINGS"
check_output "a foreign PreToolUse hook survives" 0 '/opt/other/guard.sh' cat "$D/$SETTINGS"
check_output "a foreign PostToolUse hook survives" 0 '/opt/other/after.sh' cat "$D/$SETTINGS"
check_output "prumo hooks were added" 0 "$V/hooks/protected_push.py" commands "$D/$SETTINGS"
check "registered no_em_dash still blocks after a merge" 2 fire "$D" no_em_dash.py "$(write_event "$D" "x ${DASH} y")"
check "a merged registration is not duplicated" 0 exactly 1 "no_em_dash.py" "$D/$SETTINGS"
before="$(snapshot "$D")"; "$I" "$D" >/dev/null 2>&1; after="$(snapshot "$D")"
check "merging twice changes not one byte" 0 test "$before" = "$after"

echo "refusals"
D="$(repo)"
mkdir -p "$D/.claude"
printf '{ not json\n' >"$D/$SETTINGS"
check_output "malformed settings.json is a refusal" 1 "REFUSED" "$I" "$D"
check_output "the malformed file is left untouched" 0 '{ not json' cat "$D/$SETTINGS"
check "a refusal vendored no hooks" 0 absent "$D/$V/hooks/no_em_dash.py"
check "a refusal left the repository untouched" 0 absent "$D/$V"
check_output "--no-agent-hooks does not read the settings file" 0 "created $V/MANIFEST" "$I" --no-agent-hooks "$D"
check_output "the malformed file survives an opted-out run" 0 '{ not json' cat "$D/$SETTINGS"

echo "opt out and remote"
D="$(repo)"
check "--no-agent-hooks exits 0" 0 "$I" --no-agent-hooks "$D"
check "--no-agent-hooks wrote no settings file" 0 absent "$D/$SETTINGS"
check "--no-agent-hooks vendored no hooks" 0 absent "$D/$V/hooks/no_em_dash.py"
check_output "a value after --no-agent-hooks is a usage error" 2 "usage" "$I" --no-agent-hooks yes "$D"
D="$(repo)"
check "--source remote exits 0" 0 "$I" --source remote "$D"
check "--source remote installed no agent gates" 0 absent "$D/$SETTINGS"
check "--source remote vendored no hooks" 0 absent "$D/$V/hooks/no_em_dash.py"

echo "opting out deregisters, so nothing dangles"
D="$(repo)"
"$I" "$D" >/dev/null 2>&1
check "hooks are registered before the opt-out" 0 exactly 1 "no_em_dash.py" "$D/$SETTINGS"
check_output "the opt-out run reports the settings file" 0 "updated $SETTINGS" "$I" --no-agent-hooks "$D"
check "no prumo hook stays registered" 0 not_contains "prumo/vendor/hooks" "$D/$SETTINGS"
check "the settings file still parses" 0 python3 -m json.tool "$D/$SETTINGS"
check "the vendored hooks are gone" 0 absent "$D/$V/hooks/no_em_dash.py"
check "the vendor MANIFEST still verifies" 0 "$D/$V/bin/prumo-vendor-verify"
before="$(snapshot "$D")"; "$I" --no-agent-hooks "$D" >/dev/null 2>&1; after="$(snapshot "$D")"
check "a second opt-out run changes not one byte" 0 test "$before" = "$after"

echo "opting out keeps foreign hooks"
D="$(repo)"
mkdir -p "$D/.claude"
cat >"$D/$SETTINGS" <<'JSON'
{
  "model": "opus",
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "/opt/other/guard.sh"}]}
    ],
    "PostToolUse": [{"matcher": "Write", "hooks": [{"type": "command", "command": "/opt/other/after.sh"}]}]
  }
}
JSON
"$I" "$D" >/dev/null 2>&1
check "the foreign hook is registered alongside ours" 0 exactly 1 "/opt/other/guard.sh" "$D/$SETTINGS"
check "and so is ours" 0 exactly 1 "protected_push.py" "$D/$SETTINGS"
"$I" --no-agent-hooks "$D" >/dev/null 2>&1
check_output "the foreign PreToolUse hook survives the opt-out" 0 '/opt/other/guard.sh' cat "$D/$SETTINGS"
check_output "the foreign PostToolUse hook survives the opt-out" 0 '/opt/other/after.sh' cat "$D/$SETTINGS"
check_output "an unrelated key survives the opt-out" 0 '"model": "opus"' cat "$D/$SETTINGS"
check "no prumo hook survives the opt-out" 0 not_contains "prumo/vendor/hooks" "$D/$SETTINGS"

echo "a registration git ignores reaches nobody"
D="$(repo)"
printf '.claude/\n' >"$D/.gitignore"
check_output "a gitignored settings file is warned about" 0 "gitignored" "$I" "$D"
check_output "the warning says who it reaches" 0 "this machine" "$I" "$D"
D="$(repo)"
check "no warning when the file is not ignored" 0 output_not_contains "gitignored" "$I" "$D"
D="$(repo)"
printf '.claude/\n' >"$D/.gitignore"
check "no warning when the gates are opted out" 0 output_not_contains "gitignored" "$I" --no-agent-hooks "$D"

echo "the MANIFEST covers the hooks"
D="$(repo)"
"$I" "$D" >/dev/null 2>&1
printf 'import sys\nsys.exit(0)\n' >"$D/$V/hooks/no_em_dash.py"
check "a stubbed hook stops blocking" 0 fire "$D" no_em_dash.py "$(write_event "$D" "x ${DASH} y")"
check "and the MANIFEST catches the stub" 1 "$D/$V/bin/prumo-vendor-verify"
check_output "a rerun restores the tampered hook" 0 "updated $V/MANIFEST" "$I" "$D"
check "the restored hook matches the pack again" 0 same_bytes no_em_dash.py "$D/$V/hooks/no_em_dash.py"

finish
