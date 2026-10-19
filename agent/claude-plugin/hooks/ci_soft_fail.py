#!/usr/bin/env python3
"""PreToolUse on Write|Edit|MultiEdit of CI files: block new soft failures.

Guarded files, two kinds:

- pipelines: `.gitlab-ci.yml` (and included `*.gitlab-ci.yml`),
  `.github/workflows/*.yml|*.yaml`, `bitbucket-pipelines.yml`, and any
  `Jenkinsfile`, with or without a `.suffix`, at the root or under `pipelines/`.
  A shared library file such as `vars/build.groovy` is not a pipeline and is not
  guarded.
- task runners: `Justfile`, `justfile`, `Makefile`, `makefile`, `Taskfile.yml`,
  `Taskfile.yaml` and `package.json`. This is where a local CI mirror lives, and
  a gate softened there hides from the same reader for the same reason.

What counts as a soft failure:
- YAML: `allow_failure: true` (also yes/on, quoted or not) or
  `continue-on-error: true` or an expression (`${{ ... }}`, which can evaluate
  to true). `allow_failure: {exit_codes: [...]}` is not blocked: it tolerates
  named exit codes only, not every failure.
- Groovy: `catchError`, whose default `buildResult` is SUCCESS, unless it
  names FAILURE explicitly; `unstable(...)`; `currentBuild.result` set to
  anything that is not a failure; and `sh(returnStatus: true, ...)` whose
  variable nothing reads afterwards, which is the gate's exit code collected
  and dropped.
- Any of them: a Prumo gate followed by `||`, which replaces its exit code
  with whatever follows. `|| exit 1` is not blocked, it fails again.
- Task runners: a gate command (`cargo test`, `cargo clippy`, `npm run lint`,
  `make test`, `just ci`, `pytest`, `vitest`, the pack's own gates, ...)
  followed by `||`, and the make/just `-` recipe prefix on a gate command,
  which is the same soft failure spelled natively. The gate set is a list of
  test and lint runners, not every command, so `rm -rf build || true` stays
  allowed in a recipe for the same reason it is allowed in a pipeline.

`rm -rf build || true` is not blocked either, and that is the point: cleanup
that may legitimately find nothing to clean is not a gate, and a blanket
`|| true` rule would refuse ordinary pipeline edits. A gate that blocks the
work gets switched off, and then it guards nothing.

Comments do not count: `#` in YAML, Makefile, Justfile and Taskfile, `//` and
`/* */` in Groovy. `package.json` is JSON, which has no comments, so none are
stripped there.

"Introducing" is counted, not guessed: the new text must not have more soft
failures than the text it replaces (old_string for Edit, the file on disk for
Write). Counting happens inside the text the tool writes, not the whole file,
so a check that lives further down is not seen; keep an assignment and the
test of its result in the same edit. A job that fails must fail the pipeline;
a red gate turned yellow is a gate that stopped biting.
"""
import os
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _common import block, new_texts, read_event  # noqa: E402

END = r"""["']?(?=\s*(?:[,}\]]|$))"""
# The gates the pack ships, under the names a pipeline invokes them by.
GATE = (r"(?:prumo-trace|prumo-vendor-verify|prumo-certify"
        r"|fail-closed\.sh|metabolic\.sh|anti-leak\.sh)")
# The gate runners a task recipe invokes. Kept to test and lint steps: a build
# step that is softened is a defect too, but it is not this one, and a wider
# list would refuse recipes that legitimately tolerate a missing tool.
TASK_GATE = (
    r"(?:cargo\s+(?:test|clippy|check)"
    r"|npm\s+(?:run\s+)?(?:test|lint|check)"
    r"|npx\s+(?:vitest|jest|tsc|eslint)"
    r"|pnpm\s+(?:run\s+)?(?:test|lint|check)"
    r"|yarn\s+(?:run\s+)?(?:test|lint|check)"
    r"|pytest|tox|nox|rspec|phpunit|vitest|jest|eslint|ruff|mypy|tsc"
    r"|go\s+(?:test|vet)"
    r"|dotnet\s+test"
    r"|(?:mvn|\./mvnw|gradle|\./gradlew)\s+\S+"
    r"|make\s+(?:test|lint|check)"
    r"|just\s+(?:test|lint|check|ci)"
    r"|" + GATE + r")"
)
# `||` that replaces the exit code, except `|| exit 1` and `|| exit $?`, which
# fail again.
SOFTENED = r"[^\n]*?\|\|\s*(?!\s*exit\s+(?:[1-9]|\$))"
JENKINSFILE = re.compile(r"^Jenkinsfile(?:\..+)?$")
TASK_RUNNER = re.compile(
    r"^(?:Justfile|justfile|Makefile|makefile|Taskfile\.ya?ml|package\.json)$")

# Patterns are scoped by file kind: a pipeline file has no recipes, and a
# Makefile has no YAML keys, so a pattern only runs where it can mean something.
PIPELINE = frozenset({"pipeline"})
TASK = frozenset({"task"})
BOTH = frozenset({"pipeline", "task"})

RETURN_ANY = re.compile(r"returnStatus\s*:\s*true", re.I)
RETURN_ASSIGN = re.compile(
    r"(?:def\s+|final\s+)?(\w+)\s*=\s*\w+\s*\([^)]*?returnStatus\s*:\s*true",
    re.I | re.S)


def rx_counter(pattern, flags=0):
    """A counter for one regex, so PATTERNS stays a list of (label, counter)."""
    rx = re.compile(pattern, flags)
    return lambda text: len(rx.findall(text))


def unchecked_return_status(text):
    """`returnStatus: true` whose exit code nothing looks at afterwards.

    A step that collects the status instead of failing on it is only a gate
    while something reads the variable. Anything that mentions it again after
    the assignment counts as read: this is a heuristic, not a data flow
    analysis, and it errs towards letting a checked call through.
    """
    total = len(RETURN_ANY.findall(text))
    checked = 0
    for m in RETURN_ASSIGN.finditer(text):
        var = m.group(1)
        if re.search(r"(?<!\w)%s(?!\w)" % re.escape(var), text[m.end():]):
            checked += 1
    return max(total - checked, 0)


PATTERNS = [
    ("allow_failure: true", rx_counter(
        r"(?<![\w-])allow_failure\s*:\s*[\"']?(?:true|yes|on)" + END, re.I | re.M),
     PIPELINE),
    ("continue-on-error: true", rx_counter(
        r"(?<![\w-])continue-on-error\s*:\s*(?:[\"']?(?:true|yes|on)" + END +
        r"|[\"']?\$\{\{)", re.I | re.M), PIPELINE),
    ("catchError without buildResult: FAILURE", rx_counter(
        r"catchError\s*(?!\(\s*buildResult\s*:\s*[\"']?FAILURE)", re.I), PIPELINE),
    ("unstable(...) instead of a failure", rx_counter(
        r"(?<![\w.])unstable\s*\(", re.I), PIPELINE),
    ("currentBuild.result set to something that is not a failure", rx_counter(
        r"currentBuild\s*\.\s*(?:result\s*=|setResult\s*\()\s*[\"']?"
        r"(?:UNSTABLE|SUCCESS|NOT_BUILT|ABORTED)", re.I), PIPELINE),
    ("unchecked returnStatus: true", unchecked_return_status, PIPELINE),
    ("a Prumo gate softened with || true", rx_counter(
        GATE + SOFTENED, re.I), BOTH),
    ("a gate command softened with || true", rx_counter(
        TASK_GATE + SOFTENED, re.I), TASK),
    ("a recipe line that ignores a gate with the '-' prefix", rx_counter(
        r"(?m)^[ \t]+-[ \t]*(?:" + TASK_GATE + r")", re.I), TASK),
]


def kind(path):
    name = os.path.basename(path.replace("\\", "/"))
    return "task" if TASK_RUNNER.match(name) else "pipeline"


def guarded(path):
    norm = path.replace("\\", "/")
    name = os.path.basename(norm)
    if TASK_RUNNER.match(name):
        return True
    if name == ".gitlab-ci.yml" or name.endswith(".gitlab-ci.yml"):
        return True
    if name == "bitbucket-pipelines.yml" or JENKINSFILE.match(name):
        return True
    parts = norm.split("/")
    return (
        len(parts) >= 3
        and parts[-3] == ".github"
        and parts[-2] == "workflows"
        and name.endswith((".yml", ".yaml"))
    )


def language(path):
    """Comments are stripped per language: `#` in YAML and recipe files, `//`
    and `/* */` in Groovy, nothing in JSON, which has no comments."""
    name = os.path.basename(path.replace("\\", "/"))
    if JENKINSFILE.match(name):
        return "groovy"
    if name == "package.json":
        return "json"
    if TASK_RUNNER.match(name):
        return "make"
    return "yaml"


BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.S)
LINE_COMMENT = re.compile(r"(^|[^:])//.*$")
HASH_COMMENT = re.compile(r"(^|\s)#.*$")


def strip_comments(text, lang):
    if lang == "json":
        return text or ""
    lines = (text or "").splitlines()
    if lang != "groovy":
        return "\n".join(HASH_COMMENT.sub(r"\1", line) for line in lines)
    joined = BLOCK_COMMENT.sub(" ", text or "")
    out = []
    for line in joined.splitlines():
        line = LINE_COMMENT.sub(r"\1", line)
        # A leading '#' is a shebang. One inside a Groovy string is not worth
        # the risk of eating the code after it, so only the leading form goes.
        out.append(re.sub(r"^\s*#.*$", "", line))
    return "\n".join(out)


def count(text, lang, kind_name):
    text = strip_comments(text, lang)
    return {label: counter(text) for label, counter, kinds in PATTERNS
            if kind_name in kinds}


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
    lang = language(path)
    kind_name = kind(path)
    labels = [label for label, _, kinds in PATTERNS if kind_name in kinds]

    before = {label: 0 for label in labels}
    after = {label: 0 for label in labels}
    for old, new in pairs:
        if old is None:  # Write replaces the whole file on disk.
            try:
                with open(path, encoding="utf-8") as fh:
                    old = fh.read()
            except (OSError, UnicodeDecodeError):
                old = ""
        for label, n in count(old, lang, kind_name).items():
            before[label] += n
        for label, n in count(new, lang, kind_name).items():
            after[label] += n

    for label in labels:
        if after[label] > before[label]:
            block(
                "%s introduces `%s` (%d before, %d after). A failing job must fail the "
                "pipeline; fix the job or remove it instead of making it soft."
                % (path, label, before[label], after[label])
            )
    return 0


if __name__ == "__main__":
    sys.exit(main())
