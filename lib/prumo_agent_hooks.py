#!/usr/bin/env python3
"""prumo_agent_hooks: registers the vendored Prumo hooks in a repository's
.claude/settings.json, so a Claude Code session opened in that repository is
gated at project scope.

Why this exists: `claude plugin install` is user scope, and a project
`.claude/settings.json` carrying `extraKnownMarketplaces` plus `enabledPlugins`
does not register the marketplace (measured on claude 2.1.285: `plugin list`
stays empty and the hook never runs). A plain `hooks` block in the project
settings does run, which makes it the only path by which a repository gates
every session opened in it rather than one person's machine.

The block is derived from agent/claude-plugin/hooks/hooks.json, so the plugin
and the vendored registration cannot drift: each `${CLAUDE_PLUGIN_ROOT}` in a
command becomes `$CLAUDE_PROJECT_DIR/<vendor root>`, and the hooks/ subpath
hooks.json already carries is what puts the scripts at <vendor root>/hooks/.

Merging is conservative and idempotent. An entry is prumo-owned when every
command in it points into the vendored hooks directory; a foreign entry is
never edited, and a foreign hook sharing a matcher is left where it is. Our own
entries are extended or created, never duplicated, so a second run writes
nothing and a hook deleted by hand comes back.

The file is rewritten with json.dump(indent=2) when it changes, which
normalises the indentation of a hand-written settings.json. Keys, values and
foreign hooks are preserved; formatting is not.

Fail closed: a hooks.json that is missing or unparsable, an entry without a
matcher or a command, and an existing .claude/settings.json that is not a JSON
object (or whose hooks or PreToolUse have the wrong shape, or that is a
directory or a symlink) are refusals. Nothing is written on a refusal.

Usage: prumo_agent_hooks.py check     <repo> [vendor_root]
       prumo_agent_hooks.py install   <repo> [vendor_root]
       prumo_agent_hooks.py uninstall <repo> [vendor_root]
       (vendor_root defaults to .prumo/vendor, relative to the repository)
Exit:  0 ok, 1 refusal, 2 usage error.
"""
import json
import os
import sys

USAGE = "usage: prumo_agent_hooks.py check|install|uninstall <repo> [vendor_root]"
DEFAULT_ROOT = ".prumo/vendor"
SETTINGS = os.path.join(".claude", "settings.json")
PLUGIN_ROOT_VAR = "${CLAUDE_PLUGIN_ROOT}"
PROJECT_ROOT_VAR = "$CLAUDE_PROJECT_DIR"


def fail(code, msg):
    print("prumo-agent-hooks: " + msg, file=sys.stderr)
    sys.exit(code)


def refuse(msg):
    fail(1, "REFUSED, " + msg)


def plugin_hooks_json():
    """The path of the pack's hooks.json, found relative to this file."""
    here = os.path.dirname(os.path.abspath(__file__))
    p = os.path.join(here, "..", "agent", "claude-plugin", "hooks", "hooks.json")
    return os.path.normpath(p)


def desired(vendor_root):
    """The PreToolUse entries to register, as (matcher, [hook dicts]).

    Derived from the plugin's hooks.json so there is one declaration of which
    hook guards which tool. Anything unreadable is a refusal.
    """
    path = plugin_hooks_json()
    try:
        with open(path, encoding="utf-8") as fh:
            src = json.load(fh)
    except (OSError, ValueError) as exc:
        refuse("cannot read %s (%s), so there is nothing to register"
               % (path, exc.__class__.__name__))
    entries = src.get("hooks", {}).get("PreToolUse") if isinstance(src, dict) else None
    if not isinstance(entries, list) or not entries:
        refuse("%s declares no PreToolUse hooks" % path)
    replacement = "%s/%s" % (PROJECT_ROOT_VAR, vendor_root.strip("/"))
    out = []
    for e in entries:
        if not isinstance(e, dict) or not isinstance(e.get("matcher"), str):
            refuse("%s has a PreToolUse entry without a matcher" % path)
        hooks = []
        for h in e.get("hooks", []):
            cmd = h.get("command") if isinstance(h, dict) else None
            if not isinstance(cmd, str) or PLUGIN_ROOT_VAR not in cmd:
                refuse("%s has a hook without a ${CLAUDE_PLUGIN_ROOT} command" % path)
            nh = dict(h)
            nh["command"] = cmd.replace(PLUGIN_ROOT_VAR, replacement)
            hooks.append(nh)
        if not hooks:
            refuse("%s has a PreToolUse entry with no hooks" % path)
        out.append((e["matcher"], hooks))
    return out


def marker(vendor_root):
    """The substring that identifies a command as ours."""
    return "%s/%s/hooks/" % (PROJECT_ROOT_VAR, vendor_root.strip("/"))


def load_existing(path):
    """The parsed settings, or None when there is no file. Refuses on anything
    this tool would have to guess at."""
    if not os.path.lexists(path):
        return None
    if not os.path.isfile(path):
        refuse("%s is not a regular file, so it is not rewritten" % path)
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        refuse("%s does not parse as JSON (%s). Fix it by hand and run again;"
               " this tool never rewrites a file it cannot read"
               % (path, exc.__class__.__name__))
    if not isinstance(data, dict):
        refuse("%s is not a JSON object" % path)
    hooks = data.get("hooks")
    if hooks is not None and not isinstance(hooks, dict):
        refuse("%s has a 'hooks' key that is not an object" % path)
    if isinstance(hooks, dict):
        pre = hooks.get("PreToolUse")
        if pre is not None and not isinstance(pre, list):
            refuse("%s has hooks.PreToolUse that is not a list" % path)
        for e in pre or []:
            if not isinstance(e, dict) or not isinstance(e.get("hooks", []), list):
                refuse("%s has a PreToolUse entry this tool cannot merge into" % path)
    return data


def merge(data, wanted, mark):
    """Add the missing prumo hooks to the settings dict. Returns True on change.

    A foreign entry is never touched: an entry is prumo-owned only when every
    command in it is ours, and only such an entry is extended.
    """
    hooks = data.setdefault("hooks", {})
    existing = hooks.setdefault("PreToolUse", [])
    present = set()
    for e in existing:
        for h in e.get("hooks", []):
            cmd = h.get("command", "")
            if isinstance(cmd, str) and mark in cmd:
                present.add(cmd)
    changed = False
    for matcher, wanted_hooks in wanted:
        missing = [h for h in wanted_hooks if h["command"] not in present]
        if not missing:
            continue
        target = None
        for e in existing:
            if e.get("matcher") != matcher:
                continue
            eh = e.get("hooks", [])
            if eh and all(mark in h.get("command", "") for h in eh):
                target = e
                break
        if target is None:
            target = {"matcher": matcher, "hooks": []}
            existing.append(target)
        target.setdefault("hooks", []).extend(missing)
        changed = True
    return changed


def strip(data, mark):
    """Remove our hooks from the settings dict. Returns True on change.

    Only prumo-owned commands go, and an entry is dropped once it has none
    left; a foreign hook sharing a matcher stays where it is. An empty
    PreToolUse list, and then an empty hooks object, are removed rather than
    left behind as {} and [].
    """
    hooks = data.get("hooks")
    if not isinstance(hooks, dict):
        return False
    pre = hooks.get("PreToolUse")
    if not isinstance(pre, list):
        return False
    changed = False
    kept_entries = []
    for e in pre:
        if not isinstance(e, dict):
            kept_entries.append(e)
            continue
        hs = e.get("hooks", [])
        remain = [h for h in hs
                  if not (isinstance(h, dict) and mark in str(h.get("command", "")))]
        if len(remain) != len(hs):
            changed = True
        if remain:
            e["hooks"] = remain
            kept_entries.append(e)
        elif hs:
            continue
        else:
            kept_entries.append(e)
    if changed:
        if kept_entries:
            hooks["PreToolUse"] = kept_entries
        else:
            del hooks["PreToolUse"]
        if not hooks:
            del data["hooks"]
    return changed


def main(argv):
    if len(argv) < 3 or len(argv) > 4 or argv[1] not in ("check", "install", "uninstall"):
        print(USAGE, file=sys.stderr)
        return 2
    mode, repo = argv[1], argv[2]
    vendor_root = argv[3] if len(argv) == 4 else DEFAULT_ROOT
    if not os.path.isdir(repo):
        fail(2, "'%s' is not a directory" % repo)
    path = os.path.join(repo, SETTINGS)
    if mode == "uninstall":
        # Opting out must not leave a registration pointing at scripts this run
        # did not vendor: python3 on a missing file exits 2, and 2 is the block
        # code, so a dangling hook would refuse every tool call it matches.
        if not os.path.lexists(path):
            print("kept")
            return 0
        try:
            with open(path, encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, ValueError):
            print("prumo-agent-hooks: WARNING, %s does not parse, so it was left"
                  " alone. If it registers prumo hooks, they now point at scripts"
                  " this run did not vendor, and python3 on a missing file exits"
                  " 2, which blocks. Remove those entries by hand." % path,
                  file=sys.stderr)
            print("kept")
            return 0
        if not isinstance(data, dict) or not strip(data, marker(vendor_root)):
            print("kept")
            return 0
        text = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
        try:
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(text)
        except OSError as exc:
            refuse("cannot write %s (%s)" % (path, exc.__class__.__name__))
        print("updated")
        return 0
    wanted = desired(vendor_root)
    data = load_existing(path)
    if mode == "check":
        return 0
    if data is None:
        data, status = {}, "created"
    else:
        status = "updated"
    if not merge(data, wanted, marker(vendor_root)):
        print("kept")
        return 0
    text = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    if status == "updated":
        try:
            with open(path, encoding="utf-8") as fh:
                if fh.read() == text:
                    print("kept")
                    return 0
        except OSError as exc:
            refuse("cannot read %s (%s)" % (path, exc.__class__.__name__))
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)
    except OSError as exc:
        refuse("cannot write %s (%s)" % (path, exc.__class__.__name__))
    print(status)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
