#!/usr/bin/env python3
"""prumo-trace: links every invariant declared in .prumo/regression-rules/ to
the test that proves it, through a text tag.

Contract (mechanical, no judgment):

  * an ACTIVE invariant has at least one `PRUMO: <id>` tag outside prose
    (code, CI, scripts);
  * a REVOKED invariant has no tag at all: a guard defending a dead rule
    blocks the business instead of protecting it;
  * an OPEN invariant cites an issue and has no tag (once it has proof, it
    becomes ACTIVE);
  * no tag cites an id the rules do not declare;
  * no id is declared twice;
  * a rules file with no invariants is an error: the checker went blind.

Format of an invariant, on one markdown list line:

    - `BIZ-03` : **ACTIVE** : text
    - `BIZ-02` : **REVOKED 2026-09-18 (who)** : text
    - `BIZ-07` : **OPEN** (issue #3) : text

The separator between fields is free; only the id between backticks and the
bold status count (ACTIVA, REVOGADA and ABERTA are accepted as legacy).
Language agnostic: what gets scanned is text.

Declared limit: a tag proves that a test points at the rule, not that the
test passed nor that it bites. That is the job of the test runner and of
mutation testing.

Stdlib only. Exits 0 when compliant, 1 on a contract violation, 2 on a usage
error.
"""

import argparse
import fnmatch
import os
import re
import sys

MARKER = "PRUMO:"
IGNORED_DIRS = {
    ".git", "target", "node_modules", ".prumo", "docs", ".claude",
    "vendor", "dist", "build", ".venv", "venv", "__pycache__", ".dart_tool",
}
PROSE_EXTS = {".md", ".markdown", ".rst", ".txt", ".adoc"}
MAX_SIZE = 5 * 1024 * 1024
RE_ISSUE = re.compile(r"\(issue\s+[^)\s]+")


def valid_id(s):
    """PREFIX-NN with an optional one lowercase letter suffix: BIZ-04b."""
    if "-" not in s:
        return False
    prefix, rest = s.split("-", 1)
    if len(prefix) < 3 or not all("A" <= c <= "Z" for c in prefix):
        return False
    digits = ""
    for c in rest:
        if c.isdigit() and c.isascii():
            digits += c
        else:
            break
    if not digits:
        return False
    suffix = rest[len(digits):]
    return suffix == "" or (len(suffix) == 1 and "a" <= suffix <= "z")


def declared_status(rest):
    """The bold status. The Portuguese names are accepted as legacy."""
    for status, marks in (("ACTIVE", ("**ACTIVE", "**ACTIVA")),
                          ("REVOKED", ("**REVOKED", "**REVOGADA")),
                          ("OPEN", ("**OPEN**", "**ABERTA**"))):
        if any(m in rest for m in marks):
            return status
    return None


class Invariant:
    def __init__(self, ident, status, location):
        self.id = ident
        self.status = status
        self.location = location


def read_invariants(files, root, errors):
    out = []
    for path in files:
        rel = os.path.relpath(path, root)
        with open(path, encoding="utf-8", errors="replace") as fh:
            lines = fh.read().splitlines()
        for n, line in enumerate(lines, 1):
            line = line.strip()
            if not line.startswith("- `"):
                continue
            rest = line[3:]
            if "`" not in rest:
                continue
            ident, rest = rest.split("`", 1)
            if not valid_id(ident):
                continue
            location = "%s:%d" % (rel, n)
            status = declared_status(rest)
            if status is None:
                errors.append(
                    "  %s (%s) declares no status. Write `- `%s` : **ACTIVE** : ...` "
                    "or **REVOKED <date> (<who>)** or **OPEN** (issue #N)." % (ident, location, ident))
                continue
            if status == "OPEN" and not RE_ISSUE.search(rest):
                errors.append(
                    "  %s (%s) is OPEN without an issue. Debt with nowhere to be "
                    "discussed is not declared debt, it is forgetting." % (ident, location))
            out.append(Invariant(ident, status, location))
    return out


def load_ignore_patterns(root):
    patterns = []
    path = os.path.join(root, ".prumo", "trace-ignore")
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if line and not line.startswith("#"):
                    patterns.append(line)
    return patterns


def matches_ignore(rel, patterns):
    for p in patterns:
        if p.endswith("/"):
            if rel == p[:-1] or rel.startswith(p):
                return True
        elif fnmatch.fnmatch(rel, p) or rel == p:
            return True
    return False


def is_binary(path):
    try:
        if os.path.getsize(path) > MAX_SIZE:
            return True
        with open(path, "rb") as fh:
            return b"\0" in fh.read(8192)
    except OSError:
        return True


def scannable_files(root, patterns):
    for base, dirs, names in os.walk(root):
        rel_base = os.path.relpath(base, root)
        rel_base = "" if rel_base == "." else rel_base + "/"
        dirs[:] = sorted(
            d for d in dirs
            if d not in IGNORED_DIRS and not matches_ignore(rel_base + d + "/", patterns)
        )
        for name in sorted(names):
            rel = rel_base + name
            if os.path.splitext(name)[1].lower() in PROSE_EXTS:
                continue
            if matches_ignore(rel, patterns):
                continue
            path = os.path.join(base, name)
            if os.path.islink(path) or is_binary(path):
                continue
            yield path, rel


def collect_tags(root):
    patterns = load_ignore_patterns(root)
    tags = {}
    scanned = 0
    for path, rel in scannable_files(root, patterns):
        scanned += 1
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                text = fh.read()
        except OSError:
            continue
        if MARKER not in text:
            continue
        for n, line in enumerate(text.splitlines(), 1):
            if MARKER not in line:
                continue
            rest = line.split(MARKER, 1)[1]
            for raw in re.split(r"[,\s]+", rest):
                ident = raw.strip().rstrip(".:;")
                if valid_id(ident):
                    tags.setdefault(ident, []).append("%s:%d" % (rel, n))
    return tags, scanned


def main(argv):
    ap = argparse.ArgumentParser(prog="prumo-trace", description=__doc__.split("\n\n")[0])
    ap.add_argument("--root", default=None, help="repository root (default: cwd)")
    ap.add_argument("--rules-dir", default=".prumo/regression-rules",
                    help="rules directory, relative to the root")
    ap.add_argument("--valid-id", metavar="ID", help="only validate an id and exit 0/1")
    args = ap.parse_args(argv)

    if args.valid_id is not None:
        return 0 if valid_id(args.valid_id) else 1

    root = os.path.abspath(args.root or os.getcwd())
    if not os.path.isdir(root):
        print("prumo-trace: root %s does not exist" % root, file=sys.stderr)
        return 2

    rules_dir = os.path.join(root, args.rules_dir)
    files = []
    if os.path.isdir(rules_dir):
        files = sorted(
            os.path.join(rules_dir, f) for f in os.listdir(rules_dir)
            if f.endswith(".md") and os.path.isfile(os.path.join(rules_dir, f))
        )
    if not files:
        print("prumo-trace: REFUSED, no rules file in %s. With no declared rules "
              "there is nothing to check, and that is not OK." % args.rules_dir)
        return 1

    format_errors = []
    declared = read_invariants(files, root, format_errors)
    if not declared and not format_errors:
        print("prumo-trace: REFUSED, the rules in %s declare no invariant at all: "
              "the format changed or nothing was declared, and the checker went blind."
              % args.rules_dir)
        return 1

    used, scanned = collect_tags(root)
    violations = []

    if format_errors:
        violations.append(("badly declared invariants", format_errors))

    seen = {}
    repeated = []
    for inv in declared:
        if inv.id in seen:
            repeated.append("  %s declared in %s and in %s" % (inv.id, seen[inv.id], inv.location))
        else:
            seen[inv.id] = inv.location
    if repeated:
        violations.append(("ids declared more than once (two wordings are two rules)",
                           repeated))

    orphans = ["  %s (%s) has no `PRUMO: %s` tag" % (i.id, i.location, i.id)
               for i in declared if i.status == "ACTIVE" and i.id not in used]
    if orphans:
        violations.append(("ACTIVE invariants without proof (tag the test or revoke with date and author)",
                           orphans))

    zombies = ["  %s still guarded in %s" % (i.id, ", ".join(used[i.id]))
               for i in declared if i.status == "REVOKED" and i.id in used]
    if zombies:
        violations.append(("REVOKED invariants with a live guard (delete the guard or reactivate)",
                           zombies))

    proven = ["  %s already proven in %s" % (i.id, ", ".join(used[i.id]))
              for i in declared if i.status == "OPEN" and i.id in used]
    if proven:
        violations.append(("OPEN invariants that have proof after all (make it ACTIVE and close the issue)",
                           proven))

    ids = set(seen)
    ghosts = ["  %s cited in %s" % (k, ", ".join(v))
              for k, v in sorted(used.items()) if k not in ids]
    if ghosts:
        violations.append(("tags citing undeclared invariants", ghosts))

    count = {"ACTIVE": 0, "REVOKED": 0, "OPEN": 0}
    for i in declared:
        count[i.status] += 1
    summary = "%d declared (%d active, %d revoked, %d open), %d ids tagged, %d files scanned" % (
        len(declared), count["ACTIVE"], count["REVOKED"], count["OPEN"], len(used), scanned)

    if violations:
        for title, lines in violations:
            print("%s:" % title)
            for line in lines:
                print(line)
            print()
        print("prumo-trace: FAIL, %s" % summary)
        return 1
    print("prumo-trace: OK, %s" % summary)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
