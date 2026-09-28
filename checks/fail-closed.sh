#!/usr/bin/env bash
# Rule FAIL CLOSED: a missing protection refuses to start. It never degrades
# into a log line and keeps going.
#
# Origin: a sandbox stayed off in production for months because the code logged
# a line saying it was running without it, and carried on. The message existed
# and nobody read it. This check fails the build when production code contains a
# warning call whose message announces that execution continues without the
# protection.
#
# Language agnostic and line based: a line is suspect when it contains a
# warning call (anything matching "warn") AND a degradation phrase from the
# list below. Project phrases go in <dir>/.prumo/fail-closed.patterns, one
# extended regex per line, "#" starts a comment. Test files, test directories,
# docs, prose and vendored or generated directories are not scanned.
#
# Fails closed on itself: a missing directory, an unreadable patterns file or
# zero files scanned is an error. A checker that checked nothing cannot say OK.
#
# Usage: checks/fail-closed.sh [dir ...]      (default: .)
# Exit:  0 compliant, 1 violation or nothing scanned, 2 usage error.
set -euo pipefail

if [ "$#" -eq 0 ]; then set -- .; fi

exec python3 - "$@" <<'PY'
import os
import re
import sys

# Phrases that announce execution continues without a protection. The
# Portuguese ones are detection patterns: they match real code.
DEGRADATION_PHRASES = [
    r"running without", r"run without", r"continuing without", r"proceeding without",
    r"starting without", r"without sandbox", r"sandbox (is )?disabled",
    r"degraded mode", r"insecure mode", r"falling back to (an? )?insecure",
    r"fail(ing)? open",
    r"skipping (auth|authentication|verification|validation|signature|tls)",
    r"(auth|verification|validation|tls) (is )?disabled,? (continuing|proceeding)",
    # Portuguese
    r"sem sandbox", r"a continuar sem", r"arrancar sem", r"modo degradado",
]
WARNING_CALL = re.compile(r"warn", re.I)
SKIPPED_DIRS = {
    ".git", "node_modules", "target", "vendor", "dist", "build", ".venv", "venv",
    "__pycache__", ".prumo", "docs", "tests", "test", "__tests__", "spec",
    "testdata", "fixtures", ".dart_tool",
}
PROSE_EXTENSIONS = {".md", ".markdown", ".rst", ".txt", ".adoc"}
TEST_FILE = re.compile(r"(_test\.|\.test\.|_spec\.|\.spec\.|^test_)")
MAX_BYTES = 5 * 1024 * 1024


def fail(code, message):
    print("fail-closed: " + message, file=sys.stderr)
    sys.exit(code)


def project_patterns(root):
    path = os.path.join(root, ".prumo", "fail-closed.patterns")
    if not os.path.exists(path):
        return []
    try:
        with open(path, encoding="utf-8") as fh:
            lines = [l.strip() for l in fh]
    except (OSError, UnicodeDecodeError) as e:
        fail(2, "cannot read %s (%s)." % (path, e))
    out = [l for l in lines if l and not l.startswith("#")]
    for p in out:
        try:
            re.compile(p)
        except re.error as e:
            fail(2, "invalid pattern %r in %s (%s)." % (p, path, e))
    return out


targets = sys.argv[1:]
for t in targets:
    if not os.path.isdir(t):
        fail(2, "directory '%s' does not exist." % t)

findings = []
scanned = 0
for root in targets:
    phrases = re.compile("|".join(DEGRADATION_PHRASES + project_patterns(root)), re.I)
    for base, dirs, names in os.walk(root):
        dirs[:] = sorted(d for d in dirs if d not in SKIPPED_DIRS)
        for name in sorted(names):
            if os.path.splitext(name)[1].lower() in PROSE_EXTENSIONS or TEST_FILE.search(name):
                continue
            path = os.path.join(base, name)
            try:
                with open(path, "rb") as fh:
                    data = fh.read(MAX_BYTES)
            except OSError:
                continue
            if b"\0" in data[:8192]:
                continue  # binary
            scanned += 1
            for n, line in enumerate(data.decode("utf-8", "replace").splitlines(), 1):
                if WARNING_CALL.search(line) and phrases.search(line):
                    findings.append("  %s:%d: %s" % (os.path.relpath(path), n, line.strip()[:160]))

if scanned == 0:
    fail(1, "REFUSED, zero files scanned in %s. Nothing checked is not OK." % " ".join(targets))
if findings:
    print("fail-closed: protections that log and continue instead of refusing to start:",
          file=sys.stderr)
    for f in findings:
        print(f, file=sys.stderr)
    print("A missing protection must be fatal (an error that stops startup).", file=sys.stderr)
    sys.exit(1)
print("fail-closed: OK, %d file(s) scanned, no protection logs and continues." % scanned)
PY
