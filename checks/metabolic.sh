#!/usr/bin/env bash
# Rule METABOLIC: every subsystem declares how its usage is measured, or it does
# not grow.
#
# Origin: a system where most tables stayed empty and one subsystem logged tens
# of thousands of health checks and zero real requests, because nothing forced a
# subsystem to say how its use would be measured before it grew.
#
# The manifest, .prumo/subsystems.yml by default, is a small YAML subset:
#
#   roots: [src, services]          # or a block list of "- dir" lines
#   subsystems:
#     - name: billing
#       path: src/billing
#       usage_metric: invoices created per day (table invoices)
#       since: 2026-09-01           # optional
#
# Contract checked:
#   - every subsystem has name, path and a usage_metric that is not a placeholder;
#   - every declared path exists, and no name is declared twice;
#   - every directory directly under a root is declared (a new directory is a
#     subsystem growing without a metric), and no subsystem covers a whole root.
#
# Fails closed on itself: a missing manifest, no roots, no subsystems, a root
# that does not exist or holds zero directories, an unknown key or a line it
# cannot parse is an error. A checker that checked nothing cannot say OK.
#
# It checks declarations, not usage: it does not read any metric.
#
# Usage: checks/metabolic.sh [--manifest FILE] [repo root]   (default root: .)
# Exit:  0 compliant, 1 violation, 2 usage error.
set -euo pipefail

manifest=""
if [ "${1:-}" = "--manifest" ]; then
  if [ "$#" -lt 2 ]; then
    echo "metabolic: --manifest needs a file" >&2
    exit 2
  fi
  manifest="$2"
  shift 2
fi
root="${1:-.}"
if [ "$#" -gt 1 ]; then
  echo "usage: checks/metabolic.sh [--manifest FILE] [repo root]" >&2
  exit 2
fi
if [ ! -d "$root" ]; then
  echo "metabolic: repository root '$root' does not exist." >&2
  exit 2
fi
if [ -z "$manifest" ]; then manifest="$root/.prumo/subsystems.yml"; fi

exec python3 - "$root" "$manifest" <<'PY'
import os
import re
import sys

root, manifest = sys.argv[1], sys.argv[2]
REQUIRED = ("name", "path", "usage_metric")
KNOWN_TOP = {"roots", "subsystems"}
PLACEHOLDERS = {"", "todo", "tbd", "tba", "none", "null", "n/a", "na", "-", "?",
                "unknown", "later", "fixme", "xxx", "~"}
PLACEHOLDER_PREFIX = re.compile(r"^(todo|tbd|fixme|xxx)\b", re.I)
IGNORED_DIRS = {"node_modules", "__pycache__", "target", "dist", "build", "vendor"}


def refuse(message):
    print("metabolic: " + message, file=sys.stderr)
    sys.exit(1)


def unquote(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        v = v[1:-1]
    return v.strip()


def norm(p):
    p = os.path.normpath(unquote(p))
    return "" if p == "." else p


if not os.path.isfile(manifest):
    refuse("REFUSED, no manifest at %s. Every subsystem declares its usage_metric there." % manifest)

TOP = re.compile(r"^([A-Za-z_][\w-]*)\s*:\s*(.*)$")
ITEM = re.compile(r"^\s+-\s+(.+)$")
FIELD = re.compile(r"^\s+([A-Za-z_]\w*)\s*:\s*(.*)$")
ITEM_FIELD = re.compile(r"^\s+-\s+([A-Za-z_]\w*)\s*:\s*(.*)$")

roots, entries, errors = [], [], []
section, current = None, None
with open(manifest, encoding="utf-8") as fh:
    for n, raw in enumerate(fh, 1):
        line = raw.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        m = TOP.match(line)
        if m:
            section, value = m.group(1), m.group(2).strip()
            if section not in KNOWN_TOP:
                refuse("unknown key '%s' at line %d of %s." % (section, n, manifest))
            if section == "roots" and value:
                if not (value.startswith("[") and value.endswith("]")):
                    refuse("cannot parse line %d of %s: roots must be [a, b] or a list." % (n, manifest))
                roots += [norm(r) for r in value[1:-1].split(",") if r.strip()]
            elif section == "subsystems" and value:
                refuse("cannot parse line %d of %s: subsystems must be a list." % (n, manifest))
            continue
        if section == "roots":
            m = ITEM.match(line)
            if m:
                roots.append(norm(m.group(1)))
                continue
        elif section == "subsystems":
            m = ITEM_FIELD.match(line)
            if m:
                current = {m.group(1): unquote(m.group(2)), "_line": n}
                entries.append(current)
                continue
            m = FIELD.match(line)
            if m and current is not None:
                current[m.group(1)] = unquote(m.group(2))
                continue
        refuse("cannot parse line %d of %s: %s" % (n, manifest, line.strip()))

if not roots:
    refuse("REFUSED, no roots declared in %s. Without roots an undeclared "
           "subsystem is invisible." % manifest)
if not entries:
    refuse("REFUSED, no subsystem declared in %s." % manifest)

names = {}
declared = set()
no_since = []
for e in entries:
    label = e.get("name") or "<entry at line %d>" % e["_line"]
    for key in REQUIRED:
        if not e.get(key, "").strip():
            errors.append("%s has no %s" % (label, key))
    metric = e.get("usage_metric", "")
    if metric.strip() and (metric.strip().lower().strip(".!") in PLACEHOLDERS
                           or PLACEHOLDER_PREFIX.match(metric.strip())):
        errors.append("%s: usage_metric '%s' is a placeholder, not a measurement" % (label, metric))
    if e.get("name"):
        if e["name"] in names:
            errors.append("%s declared twice (lines %d and %d)" % (e["name"], names[e["name"]], e["_line"]))
        else:
            names[e["name"]] = e["_line"]
    if e.get("path"):
        p = norm(e["path"])
        declared.add(p)
        if not os.path.isdir(os.path.join(root, p)):
            errors.append("%s: path %s does not exist" % (label, p))
        for r in roots:
            if p == r or r.startswith(p + os.sep) or p == "":
                errors.append("%s: path '%s' covers the whole root '%s'" % (label, p or ".", r))
    if not e.get("since", "").strip():
        no_since.append(label)

scanned = 0
for r in roots:
    full = os.path.join(root, r)
    if not os.path.isdir(full):
        errors.append("root '%s' does not exist" % r)
        continue
    children = sorted(d for d in os.listdir(full)
                      if os.path.isdir(os.path.join(full, d))
                      and not d.startswith(".") and d not in IGNORED_DIRS)
    if not children:
        errors.append("root '%s' holds zero directories, nothing to check" % r)
    for d in children:
        scanned += 1
        rel = os.path.normpath(os.path.join(r, d))
        if rel not in declared and not any(rel.startswith(p + os.sep) for p in declared):
            errors.append("%s is not declared: it grows without a usage_metric" % rel)

if errors:
    print("metabolic: violations in %s:" % manifest, file=sys.stderr)
    for e in errors:
        print("  - " + e, file=sys.stderr)
    print("Every subsystem declares how its usage is measured before it grows.", file=sys.stderr)
    sys.exit(1)
print("metabolic: OK, %d subsystem(s) declared, %d directory(ies) under %d root(s) covered."
      % (len(entries), scanned, len(roots)))
if no_since:
    print("  note: no 'since' for " + ", ".join(no_since))
PY
