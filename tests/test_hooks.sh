#!/usr/bin/env bash
# agent/claude-plugin: the Claude Code plugin. Every hook gets the real stdin
# JSON Claude Code sends on PreToolUse. A block is exit 2 with the reason on
# stderr; malformed input blocks too (a hook that cannot read must not allow).
. "$(dirname "$0")/lib.sh"

P="$PACK_ROOT/agent/claude-plugin"
H="$P/hooks"

# The banned character is built at runtime, never written literally here.
DASH="$(printf '\xe2\x80\x94')"
# The same character as a JSON escape, and the en dash that must stay allowed.
ESC="$(printf '\\u%s' 2014)"
ENESC="$(printf '\\u%s' 2013)"

# hook <script> <stdin>: runs one hook the way Claude Code does.
hook() {
  printf '%s' "$2" | python3 "$H/$1"
}

# plugin_check <what>: structural checks on the plugin, in python3 stdlib.
plugin_check() {
  python3 - "$P" "$PACK_ROOT/VERSION" "$1" <<'PY'
import json, os, re, sys

root, version_file, what = sys.argv[1], sys.argv[2], sys.argv[3]

def fail(msg):
    print("FAIL: " + msg)
    sys.exit(1)

if what == "manifest":
    path = os.path.join(root, ".claude-plugin", "plugin.json")
    try:
        m = json.load(open(path, encoding="utf-8"))
    except Exception as e:
        fail("plugin.json does not parse: %s" % e)
    want = open(version_file, encoding="utf-8").read().strip()
    if m.get("name") != "prumo":
        fail("name is %r, want 'prumo'" % m.get("name"))
    if m.get("version") != want:
        fail("version is %r, VERSION says %r" % (m.get("version"), want))
    if not m.get("description"):
        fail("no description")
    print("manifest ok: prumo %s" % want)

elif what == "hooks":
    path = os.path.join(root, "hooks", "hooks.json")
    try:
        h = json.load(open(path, encoding="utf-8"))
    except Exception as e:
        fail("hooks.json does not parse: %s" % e)
    entries = h.get("hooks", {}).get("PreToolUse", [])
    if not entries:
        fail("no PreToolUse hook declared")
    count = 0
    for e in entries:
        if not e.get("matcher"):
            fail("PreToolUse entry without matcher")
        for c in e.get("hooks", []):
            cmd = c.get("command", "")
            refs = re.findall(r"\$\{CLAUDE_PLUGIN_ROOT\}/([^\"' ]+)", cmd)
            if not refs:
                fail("command does not reference a plugin file: %s" % cmd)
            for r in refs:
                if not os.path.isfile(os.path.join(root, r)):
                    fail("command references a missing file: %s" % r)
            count += 1
    print("hooks ok: %d command(s)" % count)

elif what.startswith("routes:"):
    # routes:<tool>:<script>: the script runs when Claude Code calls <tool>.
    _, tool, script = what.split(":")
    h = json.load(open(os.path.join(root, "hooks", "hooks.json"), encoding="utf-8"))
    for e in h.get("hooks", {}).get("PreToolUse", []):
        if re.fullmatch(e.get("matcher", ""), tool):
            if any(script in c.get("command", "") for c in e.get("hooks", [])):
                print("%s routes to %s" % (tool, script))
                sys.exit(0)
    fail("%s does not route to %s" % (tool, script))

else:
    fail("unknown check %s" % what)
PY
}

echo "plugin structure"
check_output "plugin.json parses, name prumo, version from VERSION" 0 "manifest ok" plugin_check manifest
check_output "hooks.json parses and every command file exists" 0 "hooks ok" plugin_check hooks
check_output "Write routes to the em-dash hook" 0 "routes to" plugin_check routes:Write:no_em_dash.py
check_output "Edit routes to the em-dash hook" 0 "routes to" plugin_check routes:Edit:no_em_dash.py
check_output "MultiEdit routes to the em-dash hook" 0 "routes to" plugin_check routes:MultiEdit:no_em_dash.py

echo "em-dash hook: blocks"
check_output "Write with raw U+2014 is blocked" 2 "U+2014" \
  hook no_em_dash.py '{"tool_name":"Write","tool_input":{"file_path":"/r/a.md","content":"one\ntwo '"$DASH"' three\n"}}'
check_output "the reason names the file and line" 2 "/r/a.md:2" \
  hook no_em_dash.py '{"tool_name":"Write","tool_input":{"file_path":"/r/a.md","content":"one\ntwo '"$DASH"' three\n"}}'
check_output "Write with JSON escaped \\u2014 is blocked" 2 "U+2014" \
  hook no_em_dash.py '{"tool_name":"Write","tool_input":{"file_path":"/r/a.md","content":"a '"$ESC"' b"}}'
check_output "Edit new_string with U+2014 is blocked" 2 "U+2014" \
  hook no_em_dash.py '{"tool_name":"Edit","tool_input":{"file_path":"/r/a.py","old_string":"x","new_string":"y '"$ESC"' z"}}'
check_output "MultiEdit with U+2014 in the second edit is blocked" 2 "U+2014" \
  hook no_em_dash.py '{"tool_name":"MultiEdit","tool_input":{"file_path":"/r/a.py","edits":[{"old_string":"a","new_string":"b"},{"old_string":"c","new_string":"d '"$ESC"'"}]}}'

echo "em-dash hook: allows"
check "Write without U+2014 passes" 0 \
  hook no_em_dash.py '{"tool_name":"Write","tool_input":{"file_path":"/r/a.md","content":"a - b, c: d (e)"}}'
check "Edit removing a U+2014 passes (only new text counts)" 0 \
  hook no_em_dash.py '{"tool_name":"Edit","tool_input":{"file_path":"/r/a.md","old_string":"a '"$ESC"' b","new_string":"a, b"}}'
check "en dash U+2013 is not the banned character" 0 \
  hook no_em_dash.py '{"tool_name":"Write","tool_input":{"file_path":"/r/a.md","content":"1'"$ENESC"'2"}}'
check "a tool it does not guard passes" 0 \
  hook no_em_dash.py '{"tool_name":"Read","tool_input":{"file_path":"/r/a.md"}}'

echo "em-dash hook: fails closed"
check_output "malformed JSON blocks" 2 "cannot read" hook no_em_dash.py '{"tool_name":"Write",'
check_output "empty stdin blocks" 2 "cannot read" hook no_em_dash.py ''
check_output "JSON that is not an object blocks" 2 "cannot read" hook no_em_dash.py '[1,2]'
check_output "Write without content blocks" 2 "cannot read" \
  hook no_em_dash.py '{"tool_name":"Write","tool_input":{"file_path":"/r/a.md"}}'
check_output "MultiEdit with edits not a list blocks" 2 "cannot read" \
  hook no_em_dash.py '{"tool_name":"MultiEdit","tool_input":{"file_path":"/r/a.md","edits":"x"}}'

finish
