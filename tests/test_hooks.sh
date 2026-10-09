#!/usr/bin/env bash
# agent/claude-plugin: the Claude Code plugin. Every hook gets the real stdin
# JSON Claude Code sends on PreToolUse. A block is exit 2 with the reason on
# stderr; malformed input blocks too (a hook that cannot read must not allow).
. "$(dirname "$0")/lib.sh"

P="$PACK_ROOT/agent/claude-plugin"
H="$P/hooks"

# The banned character is built at runtime, never written literally here.
DASH="$(printf '\xe2\x80\x94')"
# The same character as a JSON escape, and the en dash that must stay allowed.
ESC="$(printf '\\u%s' 2014)"
ENESC="$(printf '\\u%s' 2013)"

# hook <script> <stdin>: runs one hook the way Claude Code does.
hook() {
  printf '%s' "$2" | python3 "$H/$1"
}

# plugin_check <what>: structural checks on the plugin and on the pack docs that
# repeat its version, in python3 stdlib.
plugin_check() {
  python3 - "$P" "$PACK_ROOT/VERSION" "$1" <<'PY'
import json, os, re, sys

root, version_file, what = sys.argv[1], sys.argv[2], sys.argv[3]

def fail(msg):
    print("FAIL: " + msg)
    sys.exit(1)

if what == "manifest":
    path = os.path.join(root, ".claude-plugin", "plugin.json")
    try:
        m = json.load(open(path, encoding="utf-8"))
    except Exception as e:
        fail("plugin.json does not parse: %s" % e)
    want = open(version_file, encoding="utf-8").read().strip()
    if m.get("name") != "prumo":
        fail("name is %r, want 'prumo'" % m.get("name"))
    if m.get("version") != want:
        fail("version is %r, VERSION says %r" % (m.get("version"), want))
    if not m.get("description"):
        fail("no description")
    print("manifest ok: prumo %s" % want)

elif what == "hooks":
    path = os.path.join(root, "hooks", "hooks.json")
    try:
        h = json.load(open(path, encoding="utf-8"))
    except Exception as e:
        fail("hooks.json does not parse: %s" % e)
    entries = h.get("hooks", {}).get("PreToolUse", [])
    if not entries:
        fail("no PreToolUse hook declared")
    count = 0
    for e in entries:
        if not e.get("matcher"):
            fail("PreToolUse entry without matcher")
        for c in e.get("hooks", []):
            cmd = c.get("command", "")
            refs = re.findall(r"\$\{CLAUDE_PLUGIN_ROOT\}/([^\"' ]+)", cmd)
            if not refs:
                fail("command does not reference a plugin file: %s" % cmd)
            for r in refs:
                if not os.path.isfile(os.path.join(root, r)):
                    fail("command references a missing file: %s" % r)
            count += 1
    print("hooks ok: %d command(s)" % count)

elif what.startswith("routes:"):
    # routes:<tool>:<script>: the script runs when Claude Code calls <tool>.
    _, tool, script = what.split(":")
    h = json.load(open(os.path.join(root, "hooks", "hooks.json"), encoding="utf-8"))
    for e in h.get("hooks", {}).get("PreToolUse", []):
        if re.fullmatch(e.get("matcher", ""), tool):
            if any(script in c.get("command", "") for c in e.get("hooks", [])):
                print("%s routes to %s" % (tool, script))
                sys.exit(0)
    fail("%s does not route to %s" % (tool, script))

elif what.startswith("skills:"):
    # skills:<dir>:<expected,names>: every SKILL.md opens with frontmatter
    # holding its own name and a description; the expected skills exist.
    _, skills_dir, expected = what.split(":")
    found = []
    if os.path.isdir(skills_dir):
        for name in sorted(os.listdir(skills_dir)):
            path = os.path.join(skills_dir, name, "SKILL.md")
            if not os.path.isfile(path):
                continue
            lines = open(path, encoding="utf-8").read().split("\n")
            if lines[0] != "---" or "---" not in lines[1:]:
                fail("%s has no frontmatter" % path)
            meta = {}
            for line in lines[1:lines.index("---", 1)]:
                m = re.fullmatch(r"([A-Za-z_-]+):\s*(.*)", line)
                if not m:
                    fail("%s frontmatter line is not key: value: %r" % (path, line))
                value = m.group(2).strip()
                quoted = len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'"
                if not quoted and (": " in value or " #" in value or value[:1] in "[{&*!|>%@`"):
                    fail("%s: %s needs quotes to be valid YAML" % (path, m.group(1)))
                meta[m.group(1)] = value[1:-1] if quoted else value
            if meta.get("name") != name:
                fail("%s name is %r, directory is %r" % (path, meta.get("name"), name))
            if len(meta.get("description", "")) < 20:
                fail("%s has no real description" % path)
            found.append(name)
    if not found:
        fail("zero SKILL.md found in %s" % skills_dir)
    missing = [n for n in expected.split(",") if n and n not in found]
    if missing:
        fail("missing skills: %s" % ", ".join(missing))
    print("skills ok: %d" % len(found))

elif what == "marketplace":
    # The marketplace catalog lives at the pack root, two levels above the plugin.
    pack = os.path.dirname(os.path.dirname(os.path.abspath(root)))
    path = os.path.join(pack, ".claude-plugin", "marketplace.json")
    try:
        m = json.load(open(path, encoding="utf-8"))
    except Exception as e:
        fail("marketplace.json does not parse: %s" % e)
    name = m.get("name", "")
    if not re.match(r"^[a-z0-9][a-z0-9-]*$", name):
        fail("marketplace name %r is not kebab-case" % name)
    if not (m.get("owner") or {}).get("name"):
        fail("owner.name missing")
    plugins = m.get("plugins") or []
    entries = [p for p in plugins if p.get("name") == "prumo"]
    if len(entries) != 1:
        fail("want exactly one plugin named prumo, got %d" % len(entries))
    e = entries[0]
    if e.get("source") != "./agent/claude-plugin":
        fail("prumo source is %r, want './agent/claude-plugin'" % e.get("source"))
    if not os.path.isfile(os.path.join(pack, e["source"], ".claude-plugin", "plugin.json")):
        fail("source does not resolve to a plugin")
    # plugin.json and VERSION are the only version; a second copy here drifts.
    if "version" in e:
        fail("marketplace entry carries a version; plugin.json is the single source")
    print("marketplace ok: %s/prumo" % name)

elif what == "readme":
    # The status heading carries a version by hand, and a hand-maintained copy
    # rots: it read v0.2.0 while VERSION and plugin.json said 0.3.0. Check it
    # against VERSION the way plugin.json is checked, so a release that forgets
    # the heading fails instead of shipping a stale claim.
    pack = os.path.dirname(os.path.dirname(os.path.abspath(root)))
    path = os.path.join(pack, "README.md")
    try:
        text = open(path, encoding="utf-8").read()
    except OSError as e:
        fail("README.md does not read: %s" % e)
    want = open(version_file, encoding="utf-8").read().strip()
    m = re.search(r"^## Status \(v([0-9][0-9.]*)\)[ \t]*$", text, re.M)
    if not m:
        fail("README has no '## Status (vX.Y.Z)' heading")
    if m.group(1) != want:
        fail("README status heading says v%s, VERSION says %s" % (m.group(1), want))
    print("readme ok: status heading v%s" % want)

else:
    fail("unknown check %s" % what)
PY
}

echo "plugin structure"
check_output "plugin.json parses, name prumo, version from VERSION" 0 "manifest ok" plugin_check manifest
check_output "marketplace.json lists prumo from ./agent/claude-plugin, no second version" 0 "marketplace ok" plugin_check marketplace
check_output "hooks.json parses and every command file exists" 0 "hooks ok" plugin_check hooks
check_output "Write routes to the em-dash hook" 0 "routes to" plugin_check routes:Write:no_em_dash.py
check_output "Edit routes to the em-dash hook" 0 "routes to" plugin_check routes:Edit:no_em_dash.py
check_output "MultiEdit routes to the em-dash hook" 0 "routes to" plugin_check routes:MultiEdit:no_em_dash.py

echo "pack docs"
# Same ladder as plugin.json: the version is declared once, everything that
# repeats it is checked against VERSION instead of trusted.
check_output "README status heading carries the VERSION number" 0 "readme ok" plugin_check readme

echo "em-dash hook: blocks"
check_output "Write with raw U+2014 is blocked" 2 "U+2014" \
  hook no_em_dash.py '{"tool_name":"Write","tool_input":{"file_path":"/r/a.md","content":"one\ntwo '"$DASH"' three\n"}}'
check_output "the reason names the file and line" 2 "/r/a.md:2" \
  hook no_em_dash.py '{"tool_name":"Write","tool_input":{"file_path":"/r/a.md","content":"one\ntwo '"$DASH"' three\n"}}'
check_output "Write with JSON escaped \\u2014 is blocked" 2 "U+2014" \
  hook no_em_dash.py '{"tool_name":"Write","tool_input":{"file_path":"/r/a.md","content":"a '"$ESC"' b"}}'
check_output "Edit new_string with U+2014 is blocked" 2 "U+2014" \
  hook no_em_dash.py '{"tool_name":"Edit","tool_input":{"file_path":"/r/a.py","old_string":"x","new_string":"y '"$ESC"' z"}}'
check_output "MultiEdit with U+2014 in the second edit is blocked" 2 "U+2014" \
  hook no_em_dash.py '{"tool_name":"MultiEdit","tool_input":{"file_path":"/r/a.py","edits":[{"old_string":"a","new_string":"b"},{"old_string":"c","new_string":"d '"$ESC"'"}]}}'

echo "em-dash hook: allows"
check "Write without U+2014 passes" 0 \
  hook no_em_dash.py '{"tool_name":"Write","tool_input":{"file_path":"/r/a.md","content":"a - b, c: d (e)"}}'
check "Edit removing a U+2014 passes (only new text counts)" 0 \
  hook no_em_dash.py '{"tool_name":"Edit","tool_input":{"file_path":"/r/a.md","old_string":"a '"$ESC"' b","new_string":"a, b"}}'
check "en dash U+2013 is not the banned character" 0 \
  hook no_em_dash.py '{"tool_name":"Write","tool_input":{"file_path":"/r/a.md","content":"1'"$ENESC"'2"}}'
check "a tool it does not guard passes" 0 \
  hook no_em_dash.py '{"tool_name":"Read","tool_input":{"file_path":"/r/a.md"}}'

echo "em-dash hook: fails closed"
check_output "malformed JSON blocks" 2 "cannot read" hook no_em_dash.py '{"tool_name":"Write",'
check_output "empty stdin blocks" 2 "cannot read" hook no_em_dash.py ''
check_output "JSON that is not an object blocks" 2 "cannot read" hook no_em_dash.py '[1,2]'
check_output "Write without content blocks" 2 "cannot read" \
  hook no_em_dash.py '{"tool_name":"Write","tool_input":{"file_path":"/r/a.md"}}'
check_output "MultiEdit with edits not a list blocks" 2 "cannot read" \
  hook no_em_dash.py '{"tool_name":"MultiEdit","tool_input":{"file_path":"/r/a.md","edits":"x"}}'

# push <command> [cwd]: runs the push hook on a Bash call, JSON built by python.
push() {
  python3 -c 'import json,sys; print(json.dumps({"session_id":"t","cwd":sys.argv[2],"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"t"}}))' \
    "$1" "${2:-/}" | python3 "$H/protected_push.py"
}

# repo <branch> [upstream]: a scratch repository checked out on <branch>.
repo() {
  local d
  d="$(tmpdir)"
  git init -q "$d"
  git -C "$d" symbolic-ref HEAD "refs/heads/$1"
  if [ -n "${2:-}" ]; then
    git -C "$d" config "branch.$1.remote" origin
    git -C "$d" config "branch.$1.merge" "refs/heads/$2"
  fi
  printf '%s' "$d"
}
MAIN="$(repo main)"
FEATURE="$(repo feature/x)"
TRACKS_MAIN="$(repo feature/y main)"
NOREPO="$(tmpdir)"

echo "push hook: wiring"
check_output "Bash routes to the push hook" 0 "routes to" plugin_check routes:Bash:protected_push.py

echo "push hook: blocks"
check_output "git push origin main is blocked" 2 "main" push "git push origin main"
check_output "git push origin master is blocked" 2 "master" push "git push origin master"
check_output "git push origin develop is blocked" 2 "develop" push "git push origin develop"
check_output "HEAD:main is blocked" 2 "main" push "git push origin HEAD:main"
check_output "force refspec +main is blocked" 2 "main" push "git push origin +main"
check_output "src:refs/heads/master is blocked" 2 "master" push "git push origin feature:refs/heads/master"
check_output "-f origin develop is blocked" 2 "develop" push "git push -f origin develop"
check_output "deleting main with :main is blocked" 2 "main" push "git push origin :main"
check_output "--delete main is blocked" 2 "main" push "git push origin --delete main"
check_output "second refspec main is blocked" 2 "main" push "git push -u origin feature main"
check_output "push after && is blocked" 2 "main" push "make test && git push origin main"
check_output "push on its own line is blocked" 2 "main" push "git status
git push origin main"
check_output "git -C dir push is blocked" 2 "main" push "git -C /tmp push origin main"
check_output "push inside bash -c is blocked" 2 "main" push "bash -c 'git push origin main'"
check_output "--all is blocked (pushes every branch)" 2 "--all" push "git push --all origin"
check_output "--mirror is blocked" 2 "--mirror" push "git push --mirror origin"
check_output "wildcard refspec that covers main is blocked" 2 "main" push "git push origin 'refs/heads/*:refs/heads/*'"
check_output "a wildcard that cannot be proved to miss release/* is blocked" 2 "release/*" \
  push "git push origin 'refs/heads/feature/*:refs/heads/feature/*'"
check_output "unresolvable \$BRANCH is blocked" 2 "cannot resolve" push 'git push origin $BRANCH'
check_output "bare git push on main is blocked" 2 "main" push "git push" "$MAIN"
check_output "git push origin with no refspec on main is blocked" 2 "main" push "git push origin" "$MAIN"
check_output "git push origin HEAD on main is blocked" 2 "main" push "git push origin HEAD" "$MAIN"
check_output "cd into a repo on main then bare push is blocked" 2 "main" push "cd $MAIN && git push" "/"
check_output "bare push of a branch whose upstream is main is blocked" 2 "main" push "git push" "$TRACKS_MAIN"
PRUMO_PROTECTED_BRANCHES="release, main" \
  check_output "PRUMO_PROTECTED_BRANCHES adds a branch" 2 "release" push "git push origin release"
check_output "release/1.2 is blocked by default" 2 "release/1.2" push "git push origin release/1.2"
check_output "HEAD:release/x is blocked" 2 "release" push "git push origin HEAD:release/x"
check_output "deleting release/9.9 is blocked" 2 "release" push "git push origin :release/9.9"
PRUMO_PROTECTED_BRANCHES="hotfix/*" \
  check_output "a glob in PRUMO_PROTECTED_BRANCHES matches" 2 "hotfix" push "git push origin hotfix/x"

echo "push hook: allows"
check "push to a feature branch passes" 0 push "git push origin feature/x"
check "push -u origin HEAD on a feature branch passes" 0 push "git push -u origin HEAD" "$FEATURE"
check "bare git push on a feature branch passes" 0 push "git push" "$FEATURE"
check "main:feature pushes to feature and passes" 0 push "git push origin main:feature"
check "maintenance is not main" 0 push "git push origin maintenance"
check "pushing a tag passes" 0 push "git push origin v1.0"
check "release-candidate is not release/*" 0 push "git push origin release-candidate"
check "hotfix/x is not release/*" 0 push "git push origin hotfix/x"
PRUMO_PROTECTED_BRANCHES="release/*" \
  check "a glob protects only what it matches" 0 push "git push origin main"
PRUMO_PROTECTED_BRANCHES="main, master" \
  check "a wildcard refspec passes when no protected entry is a glob" 0 \
  push "git push origin 'refs/heads/feature/*:refs/heads/feature/*'"
REL="$(repo release/2.0)"
check_output "a bare push on release/2.0 is blocked" 2 "release/2.0" push "git push" "$REL"
check "--dry-run to main passes (the remote is not touched)" 0 push "git push --dry-run origin main"
check "-n to main passes" 0 push "git push -n origin main"
check "git pull origin main passes" 0 push "git pull origin main"
check "a commit message mentioning git push origin main passes" 0 push "git commit -m 'then git push origin main'"
check "a command without git passes" 0 push "ls -la"
PRUMO_PROTECTED_BRANCHES="release" \
  check "PRUMO_PROTECTED_BRANCHES replaces the default list" 0 push "git push origin main"

echo "push hook: fails closed"
check_output "malformed JSON blocks" 2 "cannot read" hook protected_push.py '{"tool_name":"Bash","tool_input":'
check_output "Bash without command blocks" 2 "cannot read" hook protected_push.py '{"tool_name":"Bash","tool_input":{}}'
check_output "bare push outside a repository blocks (branch unknown)" 2 "cannot determine" push "git push" "$NOREPO"
check_output "unbalanced quotes block" 2 "cannot parse" push "git push origin 'main"

# ci <Write|Edit> <path> <new text> [old text]: runs the CI hook, JSON built by python.
ci() {
  python3 -c '
import json, sys
tool, path, new = sys.argv[1], sys.argv[2], sys.argv[3]
old = sys.argv[4] if len(sys.argv) > 4 else ""
ti = {"file_path": path, "content": new} if tool == "Write" else {"file_path": path, "old_string": old, "new_string": new}
print(json.dumps({"session_id": "t", "cwd": "/", "hook_event_name": "PreToolUse", "tool_name": tool, "tool_input": ti}))
' "$@" | python3 "$H/ci_soft_fail.py"
}
SOFT='test:
  script: make test
  allow_failure: true
'
HARD='test:
  script: make test
  allow_failure: false
'
CI="$(tmpdir)"
printf '%s' "$SOFT" >"$CI/.gitlab-ci.yml"

echo "ci hook: wiring"
check_output "Write routes to the CI hook" 0 "routes to" plugin_check routes:Write:ci_soft_fail.py
check_output "Edit routes to the CI hook" 0 "routes to" plugin_check routes:Edit:ci_soft_fail.py
check_output "MultiEdit routes to the CI hook" 0 "routes to" plugin_check routes:MultiEdit:ci_soft_fail.py

echo "ci hook: blocks"
check_output "Write .gitlab-ci.yml with allow_failure: true is blocked" 2 "allow_failure" \
  ci Write /r/.gitlab-ci.yml "$SOFT"
check_output "the reason names the file" 2 "/r/.gitlab-ci.yml" ci Write /r/.gitlab-ci.yml "$SOFT"
check_output "an included *.gitlab-ci.yml is guarded" 2 "allow_failure" \
  ci Write /r/ci/lint.gitlab-ci.yml "$SOFT"
check_output "quoted \"true\" is blocked" 2 "allow_failure" \
  ci Write /r/.gitlab-ci.yml 'test: { script: x, allow_failure: "true" }'
check_output "Edit introducing allow_failure: true is blocked" 2 "allow_failure" \
  ci Edit /r/.gitlab-ci.yml "  allow_failure: true" "  allow_failure: false"
check_output "workflow .yml with continue-on-error: true is blocked" 2 "continue-on-error" \
  ci Write /r/.github/workflows/ci.yml 'jobs:
  t:
    continue-on-error: true
'
check_output "workflow .yaml is guarded" 2 "continue-on-error" \
  ci Write /r/.github/workflows/ci.yaml '    continue-on-error: true'
check_output "continue-on-error from an expression is blocked" 2 "continue-on-error" \
  ci Write /r/.github/workflows/ci.yml '    continue-on-error: ${{ matrix.experimental }}'
check_output "Write adding a second soft fail over an existing file is blocked" 2 "allow_failure" \
  ci Write "$CI/.gitlab-ci.yml" "$SOFT$SOFT"
check_output "MultiEdit introducing a soft fail is blocked" 2 "allow_failure" \
  hook ci_soft_fail.py '{"tool_name":"MultiEdit","tool_input":{"file_path":"/r/.gitlab-ci.yml","edits":[{"old_string":"a","new_string":"b"},{"old_string":"c","new_string":"allow_failure: true"}]}}'

echo "ci hook: Jenkins and Bitbucket"
J_CATCH='stage("build") {
  catchError(buildResult: "SUCCESS") { sh "./gradlew test" }
}
'
check_output "a Jenkinsfile gaining catchError is blocked" 2 "catchError" \
  ci Write /r/Jenkinsfile "$J_CATCH"
check_output "a Jenkinsfile under pipelines/ is guarded" 2 "catchError" \
  ci Write /r/pipelines/Jenkinsfile.build "$J_CATCH"
check_output "a Jenkinsfile.e2e suffix is guarded" 2 "catchError" \
  ci Write /r/Jenkinsfile.e2e "$J_CATCH"
check_output "an unstable call is blocked" 2 "unstable" \
  ci Write /r/Jenkinsfile 'sh "make test"
unstable("flaky")
'
check_output "an unchecked returnStatus is blocked" 2 "returnStatus" \
  ci Write /r/Jenkinsfile 'def rc = sh(returnStatus: true, script: "./gate.sh")
'
check_output "a gate softened with || true is blocked in a Jenkinsfile" 2 "|| true" \
  ci Write /r/Jenkinsfile 'sh ".prumo/vendor/bin/prumo-trace --root . || true"
'
check_output "a gate softened with || true is blocked in GitLab YAML" 2 "|| true" \
  ci Write /r/.gitlab-ci.yml 'test:
  script:
    - bin/prumo-trace --root . || true
'
check_output "a gate softened with || true is blocked in a GitHub workflow" 2 "|| true" \
  ci Write /r/.github/workflows/ci.yml 'jobs:
  t:
    steps:
      - run: ./checks/metabolic.sh . || true
'
check_output "bitbucket-pipelines.yml is guarded" 2 "|| true" \
  ci Write /r/bitbucket-pipelines.yml 'pipelines:
  default:
    - step:
        script:
          - .prumo/vendor/bin/prumo-trace --root . || true
'
check_output "currentBuild.result set to UNSTABLE is blocked" 2 "currentBuild.result" \
  ci Write /r/Jenkinsfile 'sh "make test"
currentBuild.result = "UNSTABLE"
'
check_output "a gate softened with || echo is blocked" 2 "softened" \
  ci Write /r/.gitlab-ci.yml 'test:
  script:
    - bin/prumo-trace --root . || echo "ignored, moving on"
'
check_output "a gate piped into tee and then softened is blocked" 2 "softened" \
  ci Write /r/Jenkinsfile 'sh ".prumo/vendor/bin/prumo-trace --root . | tee gates.log || true"
'

echo "ci hook: allows"
check "a checked returnStatus passes" 0 \
  ci Write /r/Jenkinsfile 'def rc = sh(returnStatus: true, script: "./gate.sh")
if (rc != 0) { error "gate failed with $rc" }
'
check "a cleanup || true passes, it softens no gate" 0 \
  ci Write /r/Jenkinsfile 'sh "rm -rf build || true"
sh "chmod -R 755 out || true"
sh "security delete-keychain x || true"
'
check "a commented Groovy soft failure passes" 0 \
  ci Write /r/Jenkinsfile '// catchError(buildResult: "SUCCESS") { sh "x" }
sh "make test"
'
check "Edit keeping an existing catchError passes" 0 \
  ci Edit /r/Jenkinsfile 'catchError(buildResult: "SUCCESS") { sh "b" }' \
  'catchError(buildResult: "SUCCESS") { sh "a" }'
check "a shared library groovy file is not a Jenkinsfile" 0 \
  ci Write /r/vars/build.groovy "$J_CATCH"
check "make test || true is not a Prumo gate" 0 \
  ci Write /r/.gitlab-ci.yml 'test:
  script:
    - make lint || true
'
check "a gate that fails again with || exit 1 passes" 0 \
  ci Write /r/.gitlab-ci.yml 'test:
  script:
    - bin/prumo-trace --root . || exit 1
'
check "currentBuild.result set to FAILURE passes" 0 \
  ci Write /r/Jenkinsfile 'sh "make test"
currentBuild.result = "FAILURE"
'

echo "ci hook: allows (continued)"
check "allow_failure: false passes" 0 ci Write /r/.gitlab-ci.yml "$HARD"
check "a commented soft fail passes" 0 ci Write /r/.gitlab-ci.yml '# allow_failure: true
test:
  script: make test # continue-on-error: true
'
check "other YAML files are not guarded" 0 ci Write /r/config.yml "$SOFT"
check "a non-YAML file under workflows is not guarded" 0 ci Write /r/.github/workflows/README.md "$SOFT"
check "Edit keeping an existing soft fail passes (nothing introduced)" 0 \
  ci Edit /r/.gitlab-ci.yml "  script: make check
  allow_failure: true" "  script: make test
  allow_failure: true"
check "Edit removing a soft fail passes" 0 ci Edit /r/.gitlab-ci.yml "  allow_failure: false" "  allow_failure: true"
check "Write rewriting a file that already had it passes (nothing introduced)" 0 \
  ci Write "$CI/.gitlab-ci.yml" "$SOFT"
check "allow_failure with exit_codes is not a blanket soft fail" 0 ci Write /r/.gitlab-ci.yml 'test:
  allow_failure:
    exit_codes: 137
'
check "a tool it does not guard passes" 0 hook ci_soft_fail.py '{"tool_name":"Read","tool_input":{"file_path":"/r/.gitlab-ci.yml"}}'

echo "ci hook: fails closed"
check_output "malformed JSON blocks" 2 "cannot read" hook ci_soft_fail.py '{"tool_name":"Write"'
check_output "Write of .gitlab-ci.yml without content blocks" 2 "cannot read" \
  hook ci_soft_fail.py '{"tool_name":"Write","tool_input":{"file_path":"/r/.gitlab-ci.yml"}}'
check_output "Write without file_path blocks" 2 "cannot read" \
  hook ci_soft_fail.py '{"tool_name":"Write","tool_input":{"content":"allow_failure: true"}}'

echo "skills"
check_output "every SKILL.md has frontmatter with its name and a description" 0 "skills ok: 3" \
  plugin_check "skills:$P/skills:prumo-certify-before-done,prumo-trace,prumo-worktree"
D="$(tmpdir)"
check_output "zero skills found fails (the check does not pass blind)" 1 "zero SKILL.md" \
  plugin_check "skills:$D:"
mkdir -p "$D/bad"
printf 'no frontmatter here\n' >"$D/bad/SKILL.md"
check_output "SKILL.md without frontmatter fails" 1 "no frontmatter" plugin_check "skills:$D:"
printf -- '---\nname: bad\n---\nbody\n' >"$D/bad/SKILL.md"
check_output "SKILL.md without description fails" 1 "no real description" plugin_check "skills:$D:"
printf -- '---\nname: other\ndescription: a description that is long enough\n---\n' >"$D/bad/SKILL.md"
check_output "name that differs from the directory fails" 1 "name is 'other'" plugin_check "skills:$D:"
printf -- '---\nname: bad\ndescription: Use when: the value breaks YAML\n---\n' >"$D/bad/SKILL.md"
check_output "unquoted description with ': ' fails (invalid YAML)" 1 "needs quotes" plugin_check "skills:$D:"

finish
