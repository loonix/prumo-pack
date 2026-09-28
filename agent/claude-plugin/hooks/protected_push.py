#!/usr/bin/env python3
"""PreToolUse on Bash: block `git push` that would update a protected branch.

Protected by default: main, master, develop. PRUMO_PROTECTED_BRANCHES (comma or
space separated) replaces the list; an empty value keeps the default, so the
gate cannot be switched off by an empty variable.

What counts as a push to a protected branch:
- an explicit refspec whose destination is protected: `main`, `+main`,
  `HEAD:main`, `x:refs/heads/main`, `:main` (delete), `--delete main`, or a
  wildcard destination that matches a protected name;
- `--all`, `--mirror` or `--branches` (they push every branch);
- no refspec, or `HEAD`/`@`, while the current branch is protected or its
  upstream (branch.<name>.merge) is protected.

Decision: `--dry-run` / `-n` is allowed. It contacts the remote but updates
nothing, and it is the way to check what a push would do.

Fails closed: unparsable commands, refspecs with shell expansions ($, `) and
an unknown current branch block.
"""
import fnmatch
import os
import re
import shlex
import subprocess
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import block, read_event  # noqa: E402

DEFAULT = ["main", "master", "develop"]
SEPARATORS = {";", "&&", "||", "|", "&", "\n", "(", ")", "|&", ";;"}
SHELLS = {"sh", "bash", "zsh", "dash", "ksh"}
# git options (before the subcommand) that take the next token as value.
GIT_OPTS_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env"}
# git push options that take the next token as value.
PUSH_OPTS_WITH_VALUE = {"-o", "--push-option", "--repo", "--receive-pack", "--exec"}
EVERYTHING = {"--all", "--mirror", "--branches"}


def protected_list():
    raw = os.environ.get("PRUMO_PROTECTED_BRANCHES", "")
    names = [n for n in re.split(r"[,\s]+", raw) if n]
    return names or DEFAULT


def tokenize(command):
    lex = shlex.shlex(command, posix=True, punctuation_chars="();<>|&\n")
    lex.whitespace = " \t\r"
    lex.whitespace_split = True
    lex.commenters = ""
    try:
        return list(lex)
    except ValueError as exc:
        block("cannot parse the command (%s); refusing rather than allowing" % exc)


def segments(tokens):
    seg = []
    for t in tokens:
        if t in SEPARATORS:
            if seg:
                yield seg
            seg = []
        else:
            seg.append(t)
    if seg:
        yield seg


def git(cwd, *args):
    try:
        r = subprocess.run(
            ["git", "-C", cwd] + list(args),
            capture_output=True, text=True, timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout.strip() if r.returncode == 0 else None


def strip_heads(ref):
    return ref[len("refs/heads/"):] if ref.startswith("refs/heads/") else ref


def implicit_targets(cwd):
    """Branches a push without refspec (or with HEAD) would update."""
    branch = git(cwd, "symbolic-ref", "--short", "-q", "HEAD")
    if not branch:
        block(
            "cannot determine the current branch in %s for a push without an explicit "
            "refspec; name the destination branch explicitly" % cwd
        )
    targets = [branch]
    upstream = git(cwd, "config", "--get", "branch.%s.merge" % branch)
    if upstream:
        targets.append(strip_heads(upstream))
    return targets


def check_push(args, cwd, protected):
    """args: tokens after `push`. Returns the reason to block, or None."""
    positionals = []
    i = 0
    while i < len(args):
        a = args[i]
        if a in ("-n", "--dry-run") or (re.fullmatch(r"-[A-Za-z]+", a) and "n" in a and "o" not in a):
            return None
        if a in EVERYTHING:
            return "%s pushes every branch, including %s" % (a, ", ".join(protected))
        if a in PUSH_OPTS_WITH_VALUE:
            i += 2
            continue
        if a.startswith("-"):
            i += 1
            continue
        positionals.append(a)
        i += 1

    refspecs = positionals[1:]
    for r in positionals:
        if "$" in r or "`" in r:
            return "cannot resolve %r before it runs (shell expansion); name the branch literally" % r

    targets = []
    if not refspecs:
        targets = implicit_targets(cwd)
    for spec in refspecs:
        spec = spec.lstrip("+")
        if spec == ":":
            return "':' pushes all matching branches, including protected ones"
        if ":" in spec:
            dst = spec.split(":", 1)[1]
        else:
            dst = spec
        if dst in ("HEAD", "@"):
            targets.extend(implicit_targets(cwd))
            continue
        dst = strip_heads(dst)
        if any(ch in dst for ch in "*?["):
            hit = [p for p in protected if fnmatch.fnmatchcase(p, dst)]
            if hit:
                return "wildcard refspec %r covers protected branch %s" % (spec, hit[0])
            continue
        targets.append(dst)

    for t in targets:
        if t in protected:
            return "push to protected branch %s" % t
    return None


def scan(command, cwd, protected, depth=0):
    if depth > 3:
        block("command nests shells too deeply to check")
    for seg in segments(tokenize(command)):
        if len(seg) >= 2 and seg[0] == "cd":
            cwd = os.path.normpath(os.path.join(cwd, os.path.expanduser(seg[1])))
            continue
        for i, tok in enumerate(seg):
            base = os.path.basename(tok)
            if base in SHELLS and "-c" in seg[i + 1:]:
                j = seg.index("-c", i + 1)
                if j + 1 < len(seg):
                    scan(seg[j + 1], cwd, protected, depth + 1)
            if base == "eval" and i + 1 < len(seg):
                scan(" ".join(seg[i + 1:]), cwd, protected, depth + 1)
            if base != "git":
                continue
            # git global options, then the subcommand.
            here = cwd
            k = i + 1
            while k < len(seg) and seg[k].startswith("-"):
                if seg[k] in GIT_OPTS_WITH_VALUE:
                    if seg[k] == "-C" and k + 1 < len(seg):
                        here = os.path.join(here, os.path.expanduser(seg[k + 1]))
                    k += 2
                else:
                    k += 1
            if k < len(seg) and seg[k] == "push":
                reason = check_push(seg[k + 1:], here, protected)
                if reason:
                    block(
                        "%s. Protected branches (%s) change only through a reviewed merge; "
                        "push a feature branch and open a merge request instead."
                        % (reason, ", ".join(protected))
                    )


def main():
    event = read_event()
    if event["tool_name"] != "Bash":
        return 0
    command = event["tool_input"].get("command")
    if not isinstance(command, str):
        block("cannot read hook input (Bash without string command)")
    cwd = event.get("cwd")
    if not isinstance(cwd, str) or not cwd:
        cwd = os.getcwd()
    scan(command, cwd, protected_list())
    return 0


if __name__ == "__main__":
    sys.exit(main())
