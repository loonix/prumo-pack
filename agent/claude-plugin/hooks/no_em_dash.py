#!/usr/bin/env python3
"""PreToolUse on Write|Edit|MultiEdit: block new text containing U+2014.

Only the text being written counts: an Edit that removes the character from
old_string passes. The character is built with chr() so this file does not
contain it and does not trip its own rule.
"""
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import block, file_path, new_texts, read_event  # noqa: E402

BANNED = chr(0x2014)


def main():
    event = read_event()
    pairs = new_texts(event)
    if pairs is None:
        return 0
    path = file_path(event)
    for _old, new in pairs:
        for n, line in enumerate(new.splitlines(), 1):
            if BANNED in line:
                block(
                    "U+2014 (em dash) in %s:%d of the new text. The em dash is banned; "
                    "use a comma, colon, parentheses or a full stop." % (path, n)
                )
    return 0


if __name__ == "__main__":
    sys.exit(main())
