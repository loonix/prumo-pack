#!/usr/bin/env python3
"""PreToolUse on Write|Edit|MultiEdit of CI files: block new soft failures.

Guarded files: `.gitlab-ci.yml` (and included `*.gitlab-ci.yml`) and
`.github/workflows/*.yml|*.yaml`. A soft failure is `allow_failure: true`
(also yes/on, quoted or not) or `continue-on-error: true` or an expression
(`${{ ... }}`, which can evaluate to true). YAML comments do not count.

"Introducing" is counted, not guessed: the new text must not have more soft
failures than the text it replaces (old_string for Edit, the file on disk for
Write). A job that fails must fail the pipeline; a red gate turned yellow is
a gate that stopped biting.

`allow_failure: {exit_codes: [...]}` is not blocked: it tolerates named exit
codes only, not every failure.
"""
import os
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import block, new_texts, read_event  # noqa: E402

END = r"""["']?(?=\s*(?:[,}\]]|$))"""
PATTERNS = [
    ("allow_failure: true", re.compile(
        r"(?<![\w-])allow_failure\s*:\s*[\"']?(?:true|yes|on)" + END, re.I | re.M)),
    ("continue-on-error: true", re.compile(
        r"(?<![\w-])continue-on-error\s*:\s*(?:[\"']?(?:true|yes|on)" + END + r"|[\"']?\$\{\{)",
        re.I | re.M)),
]


def guarded(path):
    norm = path.replace("\\", "/")
    name = os.path.basename(norm)
    if name == ".gitlab-ci.yml" or name.endswith(".gitlab-ci.yml"):
        return True
    parts = norm.split("/")
    return (
        len(parts) >= 3
        and parts[-3] == ".github"
        and parts[-2] == "workflows"
        and name.endswith((".yml", ".yaml"))
    )


def strip_comments(text):
    return "\n".join(re.sub(r"(^|\s)#.*$", r"\1", line) for line in text.splitlines())


def count(text):
    text = strip_comments(text or "")
    return {label: len(rx.findall(text)) for label, rx in PATTERNS}


def main():
    event = read_event()
    pairs = new_texts(event)
    if pairs is None:
        return 0
    path = event["tool_input"].get("file_path")
    if not isinstance(path, str) or not path:
        block("cannot read hook input (%s without file_path)" % event["tool_name"])
    if not guarded(path):
        return 0

    before = {label: 0 for label, _ in PATTERNS}
    after = {label: 0 for label, _ in PATTERNS}
    for old, new in pairs:
        if old is None:  # Write replaces the whole file on disk.
            try:
                with open(path, encoding="utf-8") as fh:
                    old = fh.read()
            except (OSError, UnicodeDecodeError):
                old = ""
        for label, n in count(old).items():
            before[label] += n
        for label, n in count(new).items():
            after[label] += n

    for label, _ in PATTERNS:
        if after[label] > before[label]:
            block(
                "%s introduces `%s` (%d before, %d after). A failing job must fail the "
                "pipeline; fix the job or remove it instead of making it soft."
                % (path, label, before[label], after[label])
            )
    return 0


if __name__ == "__main__":
    sys.exit(main())
