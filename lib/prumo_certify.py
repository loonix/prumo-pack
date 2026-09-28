#!/usr/bin/env python3
"""prumo-certify: certifies a live deployment, not the repository.

Three layers, all measured against the base url, none against the source tree:

  1. files      every declared local build file is byte for byte what the site
                serves (sha256 of the local file vs GET of its url);
  2. backend    live HTTP requests answer with the declared status and body;
  3. frontend   each page, rendered in a real browser, shows the declared text
                in its visible innerText, does not show the texts declared
                absent (case-insensitive), renders the declared selectors
                visible, has the declared images decoded and logs no console
                error.

Origin: a change was reported done after measuring the file in the repository,
while production still served the old copy. Two true measurements, neither of
them of the thing in question. Nothing is reported done without this exit 0
against the live site.

Manifest (prumo-certify.json by default), English keys, every layer optional:

  {
    "files":    [ {"local": "web/index.html", "url": "/index.html"},
                  {"local_dir": "web", "url_prefix": "/",
                   "private_prefixes": ["/legal/"], "min_count": 40} ],
    "backend":  [ {"name": "...", "method": "POST", "path": "/api/items",
                   "headers": {"Authorization": "Bearer ${API_TOKEN}"},
                   "body": {...}, "expect_status": 400,
                   "expect_body_contains": "..."} ],
    "frontend": [ {"name": "...", "path": "/", "expect_text": ["..."],
                   "expect_absent": ["..."],
                   "expect_visible_selector": ["#signup"],
                   "expect_image_loaded": ["img.logo"]} ]
  }

Local paths are relative to the manifest. Keys starting with "_" are comments.
A local_dir file whose url starts with one of its private_prefixes is not
compared: the site must answer 404 for it, any other status fails. A private
prefix that matches no file under its local_dir is a manifest error. A local_dir
holding fewer than min_count files (private ones included) is refused, so a
build step that emptied the directory cannot pass on the few files left.
"${NAME}" in a path, header value or body string is read from the environment;
an unset variable fails the check instead of sending an empty secret.

A frontend selector is visible when the first element it matches is rendered
(no display:none on it or an ancestor), has a non-zero box and computed
visibility "visible". No match or an invalid selector fails. An image is loaded
when the first element its selector matches is an <img> with complete true and
naturalWidth above 0: a broken src still has a box, so visibility alone would
pass it.

Backend writes should be INVALID requests the service must refuse (a price of
zero, a missing field, a wrong key): the rule is exercised and production is not
polluted. A write that should be refused and is accepted fails loudly, because a
resource may now exist in production.

Fails closed on itself: a missing, unparsable or empty manifest (zero checks),
an unknown key, a local_dir with zero files (or fewer than its min_count), or a
declared frontend layer whose browser tool is missing (SKIPPED) is a failure. A
certifier that checked nothing cannot say OK.

Usage: prumo-certify --base-url URL [--manifest FILE]
Exit:  0 every declared check ran and passed, 1 failure or skipped check,
       2 usage error.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request

PROG = "prumo-certify"
TIMEOUT = 30
DOM_RUNNER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "prumo_certify_dom.mjs")
LAYERS = ("files", "backend", "frontend")
KEYS = {
    "files": ({"local", "url", "local_dir", "url_prefix", "private_prefixes",
               "min_count"}, set()),
    "backend": ({"name", "method", "path", "body", "headers", "expect_status",
                 "expect_body_contains"}, {"name", "method", "path", "expect_status"}),
    "frontend": ({"name", "path", "expect_text", "expect_absent", "expect_visible_selector",
                  "expect_image_loaded"},
                 {"name", "path"}),
}
# Frontend assertions, each a list of non-empty strings, passed to the DOM runner.
FRONTEND_LISTS = ("expect_text", "expect_absent", "expect_visible_selector",
                  "expect_image_loaded")
ENV_REF = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}")


def refuse(message):
    print("%s: %s" % (PROG, message), file=sys.stderr)
    sys.exit(1)


class UsageParser(argparse.ArgumentParser):
    def error(self, message):
        self.print_usage(sys.stderr)
        print("%s: %s" % (PROG, message), file=sys.stderr)
        sys.exit(2)


# ---------------------------------------------------------------- manifest

def load_manifest(path):
    if not os.path.isfile(path):
        refuse("REFUSED, no manifest at %s. Declare what the live site must prove there." % path)
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (ValueError, UnicodeDecodeError) as e:
        refuse("cannot parse %s: %s" % (path, e))
    if not isinstance(data, dict):
        refuse("cannot parse %s: the top level must be an object." % path)

    errors = []
    for key in data:
        if not key.startswith("_") and key not in LAYERS:
            errors.append("unknown key '%s' at the top level" % key)
    base = os.path.dirname(os.path.abspath(path))
    checks = {layer: [] for layer in LAYERS}
    for layer in LAYERS:
        entries = data.get(layer, [])
        if not isinstance(entries, list):
            errors.append("'%s' must be a list" % layer)
            continue
        allowed, required = KEYS[layer]
        for i, e in enumerate(entries):
            where = "%s[%d]" % (layer, i)
            if not isinstance(e, dict):
                errors.append("%s must be an object" % where)
                continue
            for k in e:
                if not k.startswith("_") and k not in allowed:
                    errors.append("%s: unknown key '%s'" % (where, k))
            for k in sorted(required):
                if k not in e:
                    errors.append("%s: missing %s" % (where, k))
            if layer == "files":
                checks["files"] += expand_files(e, where, base, errors)
            elif layer == "backend":
                validate_backend(e, where, errors)
                checks["backend"].append(e)
            else:
                validate_frontend(e, where, errors)
                checks["frontend"].append(e)
    if errors:
        print("%s: invalid manifest %s:" % (PROG, path), file=sys.stderr)
        for e in errors:
            print("  - " + e, file=sys.stderr)
        sys.exit(1)
    if not any(checks.values()):
        refuse("REFUSED, no checks declared in %s. A certifier that checked nothing "
               "cannot say OK." % path)
    return checks


def check_url_path(value, where, key, errors):
    if not isinstance(value, str) or not value.startswith("/"):
        errors.append("%s: %s must be a string starting with /" % (where, key))
        return False
    return True


def expand_files(e, where, base, errors):
    if ("local" in e) == ("local_dir" in e):
        errors.append("%s: declare exactly one of local or local_dir" % where)
        return []
    if "local" in e:
        for k in ("url_prefix", "private_prefixes", "min_count"):
            if k in e:
                errors.append("%s: %s goes with local_dir, not local" % (where, k))
        if not check_url_path(e.get("url"), where, "url", errors):
            return []
        if not isinstance(e["local"], str):
            errors.append("%s: local must be a string" % where)
            return []
        return [(os.path.join(base, e["local"]), e["url"], False)]
    if "url" in e:
        errors.append("%s: url goes with local, not local_dir" % where)
    prefix = e.get("url_prefix", "/")
    if not isinstance(e["local_dir"], str) or not check_url_path(prefix, where, "url_prefix", errors):
        return []
    private = e.get("private_prefixes", [])
    if "private_prefixes" in e and (not isinstance(private, list) or not private or not all(
            isinstance(p, str) and p.startswith("/") for p in private)):
        errors.append("%s: private_prefixes must be a non-empty list of strings starting with /"
                      % where)
        return []
    minimum = e.get("min_count", 1)
    if not isinstance(minimum, int) or isinstance(minimum, bool) or minimum < 1:
        errors.append("%s: min_count must be a positive integer" % where)
        return []
    root = os.path.join(base, e["local_dir"])
    if not os.path.isdir(root):
        errors.append("%s: local_dir %s does not exist" % (where, e["local_dir"]))
        return []
    found = []
    for d, dirs, files in os.walk(root):
        dirs.sort()
        for f in sorted(files):
            full = os.path.join(d, f)
            rel = os.path.relpath(full, root).replace(os.sep, "/")
            url = prefix.rstrip("/") + "/" + rel
            found.append((full, url, any(url.startswith(p) for p in private)))
    if not found:
        errors.append("%s: local_dir %s holds zero files, nothing to compare"
                      % (where, e["local_dir"]))
    elif len(found) < minimum:
        errors.append("%s: local_dir %s holds %d files, fewer than min_count %d"
                      % (where, e["local_dir"], len(found), minimum))
    for p in private:
        if found and not any(url.startswith(p) for _, url, _ in found):
            errors.append("%s: private prefix %s matches no file under local_dir %s, "
                          "nothing would be checked" % (where, p, e["local_dir"]))
    return found


def validate_backend(e, where, errors):
    for k in ("name", "method"):
        if k in e and (not isinstance(e[k], str) or not e[k].strip()):
            errors.append("%s: %s must be a non-empty string" % (where, k))
    if "path" in e:
        check_url_path(e["path"], where, "path", errors)
    if "expect_status" in e and (not isinstance(e["expect_status"], int)
                                 or isinstance(e["expect_status"], bool)):
        errors.append("%s: expect_status must be an integer" % where)
    if "headers" in e and (not isinstance(e["headers"], dict)
                           or not all(isinstance(v, str) for v in e["headers"].values())):
        errors.append("%s: headers must map names to strings" % where)
    if "expect_body_contains" in e and not isinstance(e["expect_body_contains"], str):
        errors.append("%s: expect_body_contains must be a string" % where)


def validate_frontend(e, where, errors):
    if "name" in e and (not isinstance(e["name"], str) or not e["name"].strip()):
        errors.append("%s: name must be a non-empty string" % where)
    if "path" in e:
        check_url_path(e["path"], where, "path", errors)
    for k in FRONTEND_LISTS:
        t = e.get(k)
        if k in e and (not isinstance(t, list) or not t
                       or not all(isinstance(x, str) and x for x in t)):
            errors.append("%s: %s must be a non-empty list of non-empty strings" % (where, k))
    # expect_text is optional, but a page that asserts nothing proves nothing.
    if not any(k in e for k in FRONTEND_LISTS):
        errors.append("%s: declares no assertion, give at least one of %s"
                      % (where, ", ".join(FRONTEND_LISTS)))


# ---------------------------------------------------------------- http

class NoRedirect(urllib.request.HTTPRedirectHandler):
    """Statuses are checked literally: a 302 is a 302, not the page it points to."""

    def redirect_request(self, *args, **kwargs):
        return None


OPENER = urllib.request.build_opener(NoRedirect)


def fetch(url, method="GET", headers=None, data=None):
    """Returns (status, body bytes). Raises OSError when nothing answered."""
    req = urllib.request.Request(url, data=data, method=method, headers=headers or {})
    try:
        with OPENER.open(req, timeout=TIMEOUT) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def unreachable(e):
    reason = getattr(e, "reason", e)
    return "no answer: %s" % reason


class MissingEnv(Exception):
    pass


def expand(value):
    if isinstance(value, str):
        def sub(m):
            if m.group(1) not in os.environ:
                raise MissingEnv(m.group(1))
            return os.environ[m.group(1)]
        return ENV_REF.sub(sub, value)
    if isinstance(value, list):
        return [expand(v) for v in value]
    if isinstance(value, dict):
        return {k: expand(v) for k, v in value.items()}
    return value


# ---------------------------------------------------------------- layers

class Tally:
    def __init__(self):
        self.passed = self.failed = self.skipped = 0

    def record(self, verdict, layer, name, detail=""):
        setattr(self, verdict, getattr(self, verdict) + 1)
        label = {"passed": "PASS", "failed": "FAIL", "skipped": "SKIPPED"}[verdict]
        print("  %-7s %-8s %s%s" % (label, layer, name, " (%s)" % detail if detail else ""))


def run_files(base_url, files, tally):
    for local, url, private in files:
        if private:
            try:
                status, _ = fetch(base_url + url)
            except OSError as e:
                tally.record("failed", "files", url, unreachable(e))
                continue
            if status == 404:
                tally.record("passed", "files", url, "private, 404")
            else:
                tally.record("failed", "files", url,
                             "served HTTP %d, a private path must answer 404" % status)
            continue
        if not os.path.isfile(local):
            tally.record("failed", "files", url, "local file %s does not exist" % local)
            continue
        with open(local, "rb") as fh:
            local_sha = hashlib.sha256(fh.read()).hexdigest()
        try:
            status, body = fetch(base_url + url)
        except OSError as e:
            tally.record("failed", "files", url, unreachable(e))
            continue
        if status != 200:
            tally.record("failed", "files", url, "served HTTP %d, not the file" % status)
            continue
        served_sha = hashlib.sha256(body).hexdigest()
        if served_sha == local_sha:
            tally.record("passed", "files", url)
        else:
            tally.record("failed", "files", url, "differs: local sha256 %s, served %s"
                         % (local_sha[:12], served_sha[:12]))


def run_backend(base_url, requests, tally):
    for r in requests:
        name, method = r["name"], r["method"].upper()
        try:
            path = expand(r["path"])
            headers = expand(r.get("headers", {}))
            body = expand(r.get("body"))
        except MissingEnv as e:
            tally.record("failed", "backend", name, "%s is not set, request not sent" % e)
            continue
        data = None
        if isinstance(body, str):
            data = body.encode()
        elif body is not None:
            data = json.dumps(body).encode()
            if not any(k.lower() == "content-type" for k in headers):
                headers["Content-Type"] = "application/json"
        try:
            status, resp = fetch(base_url + path, method, headers, data)
        except OSError as e:
            tally.record("failed", "backend", name, unreachable(e))
            continue
        want = r["expect_status"]
        text = resp.decode("utf-8", "replace")
        if status != want:
            detail = "expected %d, got %d" % (want, status)
            if method not in ("GET", "HEAD", "OPTIONS") and 200 <= status < 300 and want >= 400:
                detail += "; the write was accepted, a resource may have been created: clean it up"
            tally.record("failed", "backend", name, detail)
        elif "expect_body_contains" in r and r["expect_body_contains"] not in text:
            tally.record("failed", "backend", name, "body does not contain %s; got %s"
                         % (json.dumps(r["expect_body_contains"]), json.dumps(text[:120])))
        else:
            tally.record("passed", "backend", name)


def run_frontend(base_url, pages, manifest_dir, tally):
    node = shutil.which(os.environ.get("PRUMO_CERTIFY_NODE", "node"))
    reason = None
    if not node:
        reason = "node not found, the rendered DOM was not checked"
    else:
        job = {"base_url": base_url, "resolve_from": [manifest_dir, os.getcwd()],
               "checks": [dict({"name": p["name"], "path": p["path"]},
                               **{k: p[k] for k in FRONTEND_LISTS if k in p})
                          for p in pages]}
        try:
            proc = subprocess.run([node, DOM_RUNNER], input=json.dumps(job), text=True,
                                  capture_output=True, timeout=60 + 45 * len(pages))
        except (OSError, subprocess.TimeoutExpired) as e:
            proc = None
            reason = "browser runner did not finish: %s" % e
        if proc is not None and proc.returncode == 3:
            reason = (proc.stderr.strip().splitlines() or ["browser tool missing"])[-1]
    if reason:
        for p in pages:
            tally.record("skipped", "frontend", p["name"], reason)
        return
    results = {}
    if proc is not None:
        for line in proc.stdout.splitlines():
            try:
                item = json.loads(line)
                results[item["name"]] = item
            except (ValueError, KeyError, TypeError):
                continue
    crash = (proc.stderr.strip().splitlines() or ["no output"])[-1] if proc else "no output"
    for p in pages:
        item = results.get(p["name"])
        if item is None:
            tally.record("failed", "frontend", p["name"], "runner returned no result: %s" % crash)
        elif item.get("ok"):
            tally.record("passed", "frontend", p["name"])
        else:
            tally.record("failed", "frontend", p["name"], item.get("detail", ""))


# ---------------------------------------------------------------- main

def main():
    ap = UsageParser(prog=PROG, description="Certify a live deployment against a manifest.")
    ap.add_argument("--base-url", required=True, help="live site, e.g. https://example.com")
    ap.add_argument("--manifest", default="prumo-certify.json",
                    help="manifest file (default: prumo-certify.json)")
    args = ap.parse_args()
    base_url = args.base_url.rstrip("/")
    if not re.match(r"^https?://[^/\s]+", base_url):
        ap.error("--base-url must be an http:// or https:// url, got %r" % args.base_url)

    checks = load_manifest(args.manifest)
    declared = sum(len(v) for v in checks.values())
    tally = Tally()
    print("%s @ %s, manifest %s" % (PROG, base_url, args.manifest))
    if checks["files"]:
        print("== files: the site serves what the build holds ==")
        run_files(base_url, checks["files"], tally)
    if checks["backend"]:
        print("== backend: live requests answer as declared ==")
        run_backend(base_url, checks["backend"], tally)
    if checks["frontend"]:
        print("== frontend: rendered pages show the declared text ==")
        run_frontend(base_url, checks["frontend"],
                     os.path.dirname(os.path.abspath(args.manifest)), tally)

    print("\n%s @ %s: %d declared, %d passed, %d failed, %d skipped"
          % (PROG, base_url, declared, tally.passed, tally.failed, tally.skipped))
    if tally.failed == 0 and tally.skipped == 0 and tally.passed == declared:
        print("CERTIFIED: every declared check ran and passed.")
        return 0
    print("REFUSED: a failed or skipped check is not a pass. Do not report this as done.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
