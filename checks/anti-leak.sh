#!/usr/bin/env bash
# Rule NO LEAK: a generic pack carries no private data. Hosts, addresses and
# names of the projects it came from stay out of it.
#
# Origin: the gates in this pack were extracted from private projects. Copying a
# deploy script also copies the server address it names, and a real example
# also copies the client in it. This check fails the build when that happens.
#
# Findings, per line of every text file:
#   - an IPv4 address, private ranges included (they map real infrastructure).
#     Loopback, 0.0.0.0, 255.x masks and the documentation ranges 192.0.2.0/24,
#     198.51.100.0/24 and 203.0.113.0/24 are allowed;
#   - an email address outside the example domains (example.com, .org, .net);
#   - a word whose sha256 is in the deny list. The list holds hashes, not the
#     words, so the check does not leak what it guards. Default list:
#     <dir>/.prumo/anti-leak.sha256, one lowercase sha256 per line, "#" starts
#     a comment. Words are the lowercase runs of [a-z0-9] in the text.
#
# Fails closed on itself: a missing directory, a malformed deny list or zero
# files scanned is an error.
#
# Usage: checks/anti-leak.sh [--deny-file FILE] [--exclude PATH ...] [dir]
#        (default dir: .; PATH is a prefix relative to dir)
# Exit:  0 compliant, 1 finding or nothing scanned, 2 usage error.
set -euo pipefail

exec python3 - "$@" <<'PY'
import hashlib
import os
import re
import sys

SKIPPED_DIRS = {
    ".git", ".claude", "node_modules", "target", "vendor", "dist", "build",
    ".venv", "venv", "__pycache__", ".dart_tool",
}
MAX_BYTES = 5 * 1024 * 1024
IPV4 = re.compile(r"(?<![\d.])(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(?![\d.])")
EMAIL = re.compile(r"[\w.+-]+@((?:[\w-]+\.)+[A-Za-z]{2,})")
EXAMPLE_DOMAINS = {"example.com", "example.org", "example.net"}
DOC_RANGES = ("192.0.2.", "198.51.100.", "203.0.113.")
WORD = re.compile(r"[a-z0-9]+")
SHA256 = re.compile(r"^[0-9a-f]{64}$")


def fail(code, message):
    print("anti-leak: " + message, file=sys.stderr)
    sys.exit(code)


def parse_args(argv):
    deny_file, excludes, dirs = None, [], []
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg in ("--deny-file", "--exclude"):
            if i + 1 >= len(argv):
                fail(2, arg + " needs a value")
            if arg == "--deny-file":
                deny_file = argv[i + 1]
            else:
                excludes.append(argv[i + 1].strip("/"))
            i += 2
        elif arg.startswith("--"):
            fail(2, "unknown option " + arg)
        else:
            dirs.append(arg)
            i += 1
    if len(dirs) > 1:
        fail(2, "one directory at a time")
    return deny_file, excludes, dirs[0] if dirs else "."


def load_denied(path, explicit):
    if not os.path.exists(path):
        if explicit:
            fail(1, "deny list " + path + " does not exist")
        return set()
    denied = set()
    with open(path, encoding="utf-8") as fh:
        for n, raw in enumerate(fh, 1):
            line = raw.split("#", 1)[0].strip().lower()
            if not line:
                continue
            if not SHA256.match(line):
                fail(1, "%s:%d is not a sha256" % (path, n))
            denied.add(line)
    return denied


def ip_allowed(parts):
    if any(int(p) > 255 for p in parts):
        return True  # not an address
    ip = ".".join(parts)
    return (parts[0] in ("127", "255") or ip == "0.0.0.0"
            or ip.startswith(DOC_RANGES))


def email_allowed(domain):
    domain = domain.lower()
    return domain in EXAMPLE_DOMAINS or any(domain.endswith("." + d) for d in EXAMPLE_DOMAINS)


def excluded(rel, excludes):
    return any(rel == e or rel.startswith(e + "/") for e in excludes)


def scan_line(line, denied):
    found = []
    for m in IPV4.finditer(line):
        if not ip_allowed(m.groups()):
            found.append("IPv4 address " + m.group(0))
    for m in EMAIL.finditer(line):
        if not email_allowed(m.group(1)):
            found.append("email address " + m.group(0))
    if denied:
        for word in set(WORD.findall(line.lower())):
            if hashlib.sha256(word.encode()).hexdigest() in denied:
                found.append("denied word (hash %s...)" % hashlib.sha256(word.encode()).hexdigest()[:12])
    return found


def main():
    deny_file, excludes, root = parse_args(sys.argv[1:])
    if not os.path.isdir(root):
        fail(2, "directory " + root + " does not exist")
    default_deny = os.path.join(root, ".prumo", "anti-leak.sha256")
    denied = load_denied(deny_file or default_deny, deny_file is not None)
    skip_files = {os.path.abspath(deny_file or default_deny)}

    scanned, findings = 0, []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIPPED_DIRS)
        for name in sorted(filenames):
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, root)
            if excluded(rel, excludes) or os.path.abspath(path) in skip_files:
                continue
            try:
                if os.path.getsize(path) > MAX_BYTES:
                    continue
                with open(path, "rb") as fh:
                    data = fh.read()
            except OSError as err:
                fail(1, "cannot read %s: %s" % (rel, err))
            if b"\0" in data:
                continue  # binary
            scanned += 1
            for n, line in enumerate(data.decode("utf-8", "replace").splitlines(), 1):
                for what in scan_line(line, denied):
                    findings.append("%s:%d: %s" % (rel, n, what))

    if scanned == 0:
        fail(1, "zero files scanned in " + root + "; a check that read nothing cannot say OK")
    for f in findings:
        print("LEAK " + f)
    print("anti-leak: %d file(s) scanned, %d finding(s), %d denied hash(es)"
          % (scanned, len(findings), len(denied)))
    sys.exit(1 if findings else 0)


main()
PY
