"""Shared helpers for the Prumo PreToolUse hooks.

Contract with Claude Code: the hook reads one JSON object on stdin
({"tool_name": ..., "tool_input": {...}, "cwd": ...}). Exit 0 allows the
tool call. Exit 2 blocks it and stderr is fed back to the model as the reason.

Every hook fails closed: input it cannot read is a block, never an allow.
Standard library only, no network, no LLM.
"""
import json
import sys


def block(reason):
    """Block the tool call: reason on stderr, exit 2."""
    sys.stderr.write("prumo: blocked: " + reason + "\n")
    sys.exit(2)


def read_event():
    """Parse the hook input. Anything unexpected blocks."""
    try:
        raw = sys.stdin.buffer.read().decode("utf-8")
        event = json.loads(raw)
    except (UnicodeDecodeError, ValueError) as exc:
        block("cannot read hook input (%s); refusing rather than allowing" % exc.__class__.__name__)
    if not isinstance(event, dict):
        block("cannot read hook input (not a JSON object); refusing rather than allowing")
    if not isinstance(event.get("tool_name"), str) or not isinstance(event.get("tool_input"), dict):
        block("cannot read hook input (no tool_name or tool_input); refusing rather than allowing")
    return event


def new_texts(event):
    """Return the text a Write, Edit or MultiEdit call would put in the file.

    Returns a list of (old, new) pairs: Write has old None, Edit has one pair,
    MultiEdit one per edit. Returns None for tools that write no file content.
    A guarded tool with missing or mistyped fields blocks.
    """
    tool = event["tool_name"]
    ti = event["tool_input"]
    if tool == "Write":
        if not isinstance(ti.get("content"), str):
            block("cannot read hook input (Write without string content)")
        return [(None, ti["content"])]
    if tool == "Edit":
        if not isinstance(ti.get("new_string"), str):
            block("cannot read hook input (Edit without string new_string)")
        old = ti.get("old_string")
        return [(old if isinstance(old, str) else "", ti["new_string"])]
    if tool == "MultiEdit":
        edits = ti.get("edits")
        if not isinstance(edits, list):
            block("cannot read hook input (MultiEdit edits is not a list)")
        pairs = []
        for e in edits:
            if not isinstance(e, dict) or not isinstance(e.get("new_string"), str):
                block("cannot read hook input (MultiEdit edit without string new_string)")
            old = e.get("old_string")
            pairs.append((old if isinstance(old, str) else "", e["new_string"]))
        return pairs
    return None


def file_path(event):
    """The target path of a file tool, or '?' when absent."""
    p = event["tool_input"].get("file_path")
    return p if isinstance(p, str) and p else "?"
