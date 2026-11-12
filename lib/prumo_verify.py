#!/usr/bin/env python3
"""prumo-verify: an ACTIVE invariant counts only when the test runner reports
a PASS for the tests bound to it.

prumo-trace proves a tag points at a rule. That is not verification: a tag
on an ignored, skipped or failing test still satisfies it. This checker reads
what the runner actually reported and closes that gap (whitepaper §2.1).

Binding (mechanical, no judgment):

  * a `PRUMO: <id>` tag binds to the test declared on the same line or on
    the first line after it that is not blank, a comment, an attribute or a
    decorator: Rust `fn`, Python `def`, Go `func Test...`, JS/TS
    `it("...")` / `test("...")`, bats `@test "..."`;
  * a test whose reported name carries the id as a whole token
    (`test_sec_01_x`, `TestSEC_01`) is bound to it too;
  * a bound test name matches a reported name when it is the whole name or
    its last segment after `::`, `.`, `/`, a space or `>`.

Contract, for every ACTIVE invariant:

  * at least one test is bound to it;
  * every bound test appears in the results;
  * every result that matches passed. Failed fails; skipped or ignored did
    not run, and a test that did not run proves nothing.

Results: JUnit XML (pytest, nextest, vitest, jest, gradle), libtest JSON
(`cargo test -- -Z unstable-options --format json`) and `go test -json`.
Several files are one run. Results with no test case are a refusal: the
checker went blind.

Declared limit: a PASS proves the test ran green, not that it bites. That is
the job of mutation testing. A function name shared by two modules binds to
both, and both must pass: conservative, never lenient.

Stdlib only. Exits 0 when compliant, 1 on a contract violation, 2 on a usage
error.
"""

import argparse
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prumo_trace  # noqa: E402  (shares the rules parser and the file walk)

MARKER = prumo_trace.MARKER
LOOKAHEAD = 12

DECLARATIONS = [
    re.compile(r"^\s*(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?(?:unsafe\s+)?fn\s+([A-Za-z_]\w*)"),
    re.compile(r"^\s*(?:async\s+)?def\s+([A-Za-z_]\w*)"),
    re.compile(r"^\s*func\s+(Test\w*)\s*\("),
    re.compile(r"""^\s*(?:it|test)(?:\.\w+)*\s*\(\s*(['"`])(.+?)\1"""),
    re.compile(r"""^\s*@test\s+(['"])(.+?)\1"""),
]
SKIPPABLE = re.compile(r"^\s*(?:$|//|#|/\*|\*|--|@)")
SEGMENT = r"(?:^|::|[./ >›])"


def declared_test(line):
    """The test name a declaration line introduces, or None."""
    for rx in DECLARATIONS:
        m = rx.search(line)
        if m:
            return m.group(m.lastindex)
    return None


def bind_tags(root):
    """{id: [(test name or None, location)]} for every tag in scannable files."""
    patterns = prumo_trace.load_ignore_patterns(root)
    binds = {}
    for path, rel in prumo_trace.scannable_files(root, patterns):
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                text = fh.read()
        except OSError:
            continue
        if MARKER not in text:
            continue
        lines = text.splitlines()
        for i, line in enumerate(lines):
            if MARKER not in line:
                continue
            ids = [raw.strip().rstrip(".:;")
                   for raw in re.split(r"[,\s]+", line.split(MARKER, 1)[1])]
            ids = [x for x in ids if prumo_trace.valid_id(x)]
            if not ids:
                continue
            name = declared_test(line.split(MARKER, 1)[0])
            j = i + 1
            while name is None and j < len(lines) and j <= i + LOOKAHEAD:
                candidate = lines[j]
                name = declared_test(candidate)
                if name is None and not SKIPPABLE.match(candidate):
                    break
                j += 1
            for ident in ids:
                binds.setdefault(ident, []).append((name, "%s:%d" % (rel, i + 1)))
    return binds


def read_results(path):
    """[(name, status)] with status in pass/fail/skip. Raises ValueError on an
    unknown format."""
    with open(path, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    if text.lstrip().startswith("<"):
        try:
            tree = ET.fromstring(text.lstrip())
        except ET.ParseError as e:
            raise ValueError("%s: not well-formed JUnit XML (%s)" % (path, e))
        out = []
        for case in tree.iter("testcase"):
            name = case.get("name", "")
            cls = case.get("classname")
            full = "%s::%s" % (cls, name) if cls else name
            tags = {child.tag for child in case}
            if tags & {"failure", "error"}:
                status = "fail"
            elif "skipped" in tags:
                status = "skip"
            else:
                status = "pass"
            out.append((full, status))
        return out
    out = []
    parsed = 0
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        if not isinstance(ev, dict):
            continue
        parsed += 1
        if ev.get("type") == "test" and "name" in ev:
            status = {"ok": "pass", "failed": "fail", "timeout": "fail",
                      "ignored": "skip"}.get(ev.get("event"))
            if status:
                out.append((ev["name"], status))
        elif "Action" in ev and ev.get("Test"):
            status = {"pass": "pass", "fail": "fail", "skip": "skip"}.get(ev["Action"])
            if status:
                out.append(("%s/%s" % (ev.get("Package", ""), ev["Test"]), status))
    if not parsed:
        raise ValueError("%s: unknown format, expected JUnit XML, libtest JSON "
                         "or go test -json" % path)
    return out


def name_matches(bound, reported):
    return re.search(SEGMENT + re.escape(bound) + r"$", reported) is not None


def id_token(ident):
    """A regex for the id as a whole token of a test name: SEC-01 matches
    test_sec_01_x and TestSEC_01, never sec_010 or sec_01b."""
    prefix, rest = ident.split("-", 1)
    return re.compile(r"(?<![A-Za-z0-9])%s[-_]?%s(?![A-Za-z0-9])"
                      % (re.escape(prefix), re.escape(rest)), re.IGNORECASE)


def tail(name):
    return re.split(SEGMENT, name)[-1] if name else name


def main(argv):
    ap = argparse.ArgumentParser(prog="prumo-verify", description=__doc__.split("\n\n")[0])
    ap.add_argument("--root", default=None, help="repository root (default: cwd)")
    ap.add_argument("--rules-dir", default=".prumo/regression-rules",
                    help="rules directory, relative to the root")
    ap.add_argument("--results", action="append", default=[], metavar="FILE",
                    help="test runner output; repeat for several files")
    args = ap.parse_args(argv)

    root = os.path.abspath(args.root or os.getcwd())
    if not os.path.isdir(root):
        print("prumo-verify: root %s does not exist" % root, file=sys.stderr)
        return 2
    if not args.results:
        print("prumo-verify: --results is required: with no runner output there "
              "is nothing to verify against", file=sys.stderr)
        return 2

    results = []
    for path in args.results:
        if not os.path.isfile(path):
            print("prumo-verify: results file %s does not exist" % path, file=sys.stderr)
            return 2
        try:
            results.extend(read_results(path))
        except ValueError as e:
            print("prumo-verify: %s" % e, file=sys.stderr)
            return 2
    if not results:
        print("prumo-verify: REFUSED, the results hold no test case. A run that "
              "ran nothing cannot verify anything.")
        return 1

    rules_dir = os.path.join(root, args.rules_dir)
    files = []
    if os.path.isdir(rules_dir):
        files = sorted(os.path.join(rules_dir, f) for f in os.listdir(rules_dir)
                       if f.endswith(".md") and os.path.isfile(os.path.join(rules_dir, f)))
    if not files:
        print("prumo-verify: REFUSED, no rules file in %s." % args.rules_dir)
        return 1
    errors = []
    active = [i for i in prumo_trace.read_invariants(files, root, errors)
              if i.status == "ACTIVE"]
    if not active:
        print("prumo-verify: REFUSED, the rules in %s declare no ACTIVE invariant: "
              "there is nothing to verify, and that is not OK." % args.rules_dir)
        return 1

    binds = bind_tags(root)
    problems = []
    for inv in active:
        tags = binds.get(inv.id, [])
        bound = sorted({n for n, _ in tags if n})
        token = id_token(inv.id)
        matched = [(n, s) for n, s in results if token.search(n)]
        lines = []
        for b in bound:
            hits = [(n, s) for n, s in results if name_matches(b, n)]
            if not hits:
                lines.append("not in the results: %s (it did not run, or the results "
                             "are from another run)" % b)
            matched.extend(h for h in hits if h not in matched)
        if not bound and not matched:
            unbound = [loc for n, loc in tags if not n]
            if unbound:
                lines.append("tag not on a test, put it on the line above the test: %s"
                             % ", ".join(unbound))
            else:
                lines.append("no test bound to it (no tag, and no test named with the id)")
        lines += ["failed: %s" % n for n, s in matched if s == "fail"]
        lines += ["did not run (skipped or ignored): %s" % n for n, s in matched if s == "skip"]
        if lines:
            problems.append((inv, lines))

    summary = "%d active, %d test results read from %d file(s)" % (
        len(active), len(results), len(args.results))
    if problems:
        print("ACTIVE invariants without a PASS from the runner:")
        for inv, lines in problems:
            print("  %s (%s)" % (inv.id, inv.location))
            for line in lines:
                print("    %s" % line)
        print()
        print("prumo-verify: FAIL, %d of %s" % (len(problems), summary))
        return 1
    print("prumo-verify: OK, %s" % summary)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
