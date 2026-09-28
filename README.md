# prumo-pack

The Prumo gates, packaged to install in any repository (GitLab, GitHub or anything else).
One source, N consumers, instead of scripts copied by hand between projects.

Prumo is an engineering paradigm for working with agents. The rule behind this pack:
**a gate whose satisfaction token is produced by the model is not a gate.** Everything here is
mechanical, no check calls an LLM, and nothing gets in until it has been measured biting in a
real project.

The paradigm itself, in full (chapters 1 to 9, English): [docs/whitepaper.md](docs/whitepaper.md).

## Status (v0.1.0)

| Piece | Status |
|---|---|
| `bin/prumo-trace` | Works, 31 tests |
| `checks/fail-closed.sh` | Works, 12 tests |
| `checks/metabolic.sh` | Works, 19 tests |
| `checks/anti-leak.sh` | Works, 14 tests |
| `bin/prumo-init` (scaffolds `.prumo/`, vendors the gates, wires CI, idempotent) | Works, 91 tests |
| `bin/prumo-vendor-verify` (vendored gates against their MANIFEST) | Works, 27 tests |
| `bin/prumo-certify` (file parity, live back end, rendered DOM) | Works, 35 tests plus 9 that need a browser |
| CI templates (vendored and remote, GitLab and GitHub) | Structure tested, 52 tests plus 6 that need PyYAML; vendored jobs replayed locally from the YAML; not run on a real runner |
| Claude Code plugin (skills and hooks) | Works, 91 tests; not loaded in a live session yet |

Skipped tests are reported as skipped, never counted as passed.

## prumo-trace

Links every invariant declared in `.prumo/regression-rules/` to the test that proves it, through
the text tag `PRUMO: <id>`. It scans plain text, so it works for any language.

Declare an invariant as one markdown list line, with status `ACTIVE`, `REVOKED` or `OPEN`:

```markdown
- `BIZ-03` : **ACTIVE** : price is never negative
- `BIZ-02` : **REVOKED 2026-09-18 (Daniel)** : text
- `BIZ-07` : **OPEN** (issue #3) : text
```

Tag the test that proves it, in any code or CI file:

```rust
// PRUMO: BIZ-03
#[test]
fn price_never_negative() { ... }
```

Contract checked:

- an ACTIVE invariant has at least one tag outside prose;
- a REVOKED invariant has no tag (a guard defending a dead rule blocks the business);
- an OPEN invariant cites an issue and has no tag yet;
- no tag cites an id the rules do not declare;
- no id is declared twice;
- a rules file with no invariants is an error (a blind checker does not get to say OK).

```sh
bin/prumo-trace --root /path/to/repo
```

Exits 0 when compliant, 1 on a violation, 2 on a usage error.

**Limit:** a tag proves that a test points at the rule, not that the test passes or that it
bites. That is the job of the test runner and of mutation testing.

## checks/fail-closed.sh

A missing protection must refuse to start, never log a warning and carry on. The check flags
any line in production code that contains a warning call (anything matching `warn`) and a
degradation phrase (`running without`, `degraded mode`, `skipping auth`, `sem sandbox`, ...).
Add project phrases to `<dir>/.prumo/fail-closed.patterns`, one extended regex per line.
Tests, `docs/`, prose files and vendored directories are not scanned.

```sh
checks/fail-closed.sh src services     # default: .
```

Exits 0 when compliant, 1 on a finding or when zero files were scanned, 2 when a directory
does not exist.

**Limit:** line based and phrase based. A warning whose message sits on the next line, a
degradation logged at info level, or a phrase not in the list is not seen.

## checks/metabolic.sh

Every subsystem declares how its usage is measured, or it does not grow. Declare them in
`.prumo/subsystems.yml`:

```yaml
roots: [src]
subsystems:
  - name: billing
    path: src/billing
    usage_metric: invoices created per day (table invoices)
    since: 2026-09-01
```

Contract checked:

- every subsystem has `name`, `path` and a `usage_metric` that is not a placeholder
  (`TODO`, `TBD`, `n/a`, ...);
- every declared path exists and no name is declared twice;
- every directory directly under a root is declared, and no subsystem covers a whole root;
- a missing manifest, no roots, no subsystems, a root with zero directories, an unknown key
  or an unparsable line is an error.

```sh
checks/metabolic.sh [--manifest FILE] /path/to/repo
```

Exits 0 when compliant, 1 on a violation, 2 when the repository root does not exist.

**Limit:** it checks declarations, not usage. It does not read the metric, so it cannot tell
whether the metric is collected, whether usage is zero, or whether the text describes a real
measurement. Only directories directly under a root count as subsystems.

## checks/anti-leak.sh

A generic pack carries no private data. The check flags, per line of every text file:

- an IPv4 address, private ranges included. Loopback, `0.0.0.0`, `255.x` masks and the
  documentation ranges `192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24` are allowed;
- an email address outside `example.com`, `example.org` and `example.net`;
- a word whose sha256 is in the deny list (default `.prumo/anti-leak.sha256`). The list holds
  hashes, not words, so it does not leak what it guards: `printf word | shasum -a 256`.

```sh
checks/anti-leak.sh [--deny-file FILE] [--exclude PATH ...] [dir]
```

Exits 0 when compliant, 1 on a finding, a malformed deny list or zero files scanned, 2 on a
usage error. `make leak` runs it over this pack with `ci/anti-leak.sha256`.

**Limit:** a four part version string reads as an address, a word is only caught whole
(`[a-z0-9]` runs) and in the list, and hostnames or names not in the list are not seen.

## prumo-init

Scaffolds `.prumo/` in a repository from `templates/.prumo/` and wires the gates into its CI.

```sh
bin/prumo-init [--source vendor|remote] [--force-ci gitlab|github|none] /path/to/repo
```

It creates each missing file and keeps each existing one byte for byte, printing `created` or
`kept` per file, so a second run creates nothing and exits 0. It writes:

- `README.md` with the 9 layers of Prumo;
- `regression-rules/RR-001-core-invariants.md` with one placeholder, `CORE-01`, declared ACTIVE;
- `specs/SPEC-template.md`, `environment-contracts/`, `execution-contracts/`;
- a `subsystems.yml` skeleton and an empty `fail-closed.patterns`.

`--source vendor` (the default) also copies the gates into `.prumo/vendor/` with a `MANIFEST`
of sha256, mode and the pack commit (a 40 hex sha, never a tag). CI runs them from there, so it
needs no network and no token, works while the pack is private, and a tag moved upstream cannot
change what runs. The vendor directory belongs to the pack: a rerun replaces it when it differs,
which is how it is upgraded or restored. The pack must be a git checkout, or init refuses.
`--source remote` keeps the older form, where CI fetches the pack at tag `v0`.

CI is detected: `.gitlab-ci.yml` means GitLab, `.github/` means GitHub, both means both.

- **GitLab:** gets `include: - local: .prumo/vendor/ci/gitlab.yml` (vendor) or the remote
  include of `templates/ci/gitlab/prumo.yml` at tag `v0` (remote), added once. An existing block list `include:` gets one more item. Any other `include:` form is
  refused, with the snippet to add by hand.
- **GitHub:** gets `templates/ci/github/prumo-vendored.yml` (vendor) or
  `templates/ci/github/prumo.yml` (remote) copied to `.github/workflows/prumo.yml`.
- **No CI detected:** refused. Gates that no CI runs are decorative Prumo. `--force-ci gitlab`
  or `--force-ci github` creates the CI file; `--force-ci none` accepts it with a warning.

A refusal writes nothing. Exits 0 when done, 1 on a refusal, 2 on a usage error.

After init, `prumo-trace` fails until a test carries `PRUMO: CORE-01` (or the rule is replaced
or revoked), and `checks/metabolic.sh` fails until `.prumo/subsystems.yml` declares a subsystem
for every directory under its roots. Both failures are intended: the pack does not know the
repository's invariants or subsystems, and an empty declaration must not pass.

**Limit:** the GitLab edit is line based. It extends only a top level block list `include:`,
and it takes any mention of `templates/ci/gitlab/prumo.yml` in the file as "already wired".

## prumo-certify

Certifies the live deployment, not the repository. A change measured in the source tree
while production still serves the old copy is two true measurements, neither of them of
the thing in question. Declare what the live site must prove in `prumo-certify.json`:

```json
{
  "files": [
    { "local_dir": "web", "url_prefix": "/", "private_prefixes": ["/legal/"], "min_count": 40 }
  ],
  "backend": [
    { "name": "item priced at zero is refused", "method": "POST", "path": "/api/items",
      "headers": { "Authorization": "Bearer ${API_TOKEN}" },
      "body": { "title": "CERTIFICATION invalid on purpose", "price_cents": 0 },
      "expect_status": 400, "expect_body_contains": "price" }
  ],
  "frontend": [
    { "name": "home shows the price", "path": "/", "expect_text": ["Plans start at 10"],
      "expect_absent": ["Sold out"], "expect_visible_selector": ["#signup"],
      "expect_image_loaded": ["img.logo"] }
  ]
}
```

Three layers, each optional:

- `files`: sha256 of each local build file equals what the site serves at its url
  (`local` + `url`, or `local_dir` + `url_prefix`; paths relative to the manifest).
  On a `local_dir`, `private_prefixes` lists url prefixes the site must NOT serve: a
  build file under one of them must answer 404, any other status fails, and a prefix
  that matches no file is a manifest error. `min_count` refuses a `local_dir` holding
  fewer files (private ones included), so a build that lost most of its output cannot
  pass on what is left;
- `backend`: live requests answer with `expect_status` and, if given,
  `expect_body_contains`. Statuses are literal, redirects are not followed;
- `frontend`: each page, rendered in a real browser, shows every `expect_text` in its
  visible `innerText`, answers HTTP 200 and logs no console error. Optional lists:
  `expect_absent`, texts the visible `innerText` must not contain (case-insensitive);
  `expect_visible_selector`, CSS selectors whose first match is rendered, has a
  non-zero box and computed `visibility: visible`; `expect_image_loaded`, CSS selectors
  whose first match is an `<img>` with `complete` and `naturalWidth > 0` (a broken
  image still has a box, so visibility alone would pass it). No match or an invalid
  selector fails.

**Prefer invalid writes.** A backend check that POSTs a request the service must refuse
exercises the rule without polluting production. If such a write is accepted, the check
fails and warns that a resource may have been created; cleanup is manual.

Secrets never go in the manifest: `${NAME}` in a path, header or body is read from the
environment, and an unset variable fails the check instead of sending an empty value.

```sh
bin/prumo-certify --base-url https://example.com [--manifest prumo-certify.json]
```

Prints one line per check and a tally (`N declared, P passed, F failed, S skipped`).
Exits 0 only when every declared check ran and passed; 1 on any failure; 2 on a usage
error. Fails closed on itself: a missing, unparsable or empty manifest (zero checks), an
unknown key, a `local_dir` with zero files (or fewer than its `min_count`), a private
prefix matching no file or an unreachable site is a failure.

The `frontend` layer needs `node` with `playwright` (resolved from the manifest's
directory, the working directory or `NODE_PATH`) and a Chromium it can launch. If the
manifest declares frontend checks and the tool is missing, they are reported `SKIPPED`
and the run is refused: a check that did not run is not a pass. A manifest with no
frontend checks does not need node at all.

**Limit:** it certifies what the manifest declares, nothing more. It does not know which
requests matter, it does not clean up after a wrongly accepted write, and parity is
per declared file (a file the site serves but the build no longer holds is not seen).

## CI templates

**Vendored (default).** `prumo-init` writes them; nothing to copy by hand. Every job first runs
`.prumo/vendor/bin/prumo-vendor-verify`: a missing, changed, re-moded or unlisted file fails the
job before any gate runs. Variables (GitLab) or the workflow `env` block (GitHub) set
`PRUMO_FAIL_CLOSED_DIRS`, `PRUMO_ANTI_LEAK` and `PRUMO_ANTI_LEAK_ARGS`, as below.

**Limit of the MANIFEST:** it lives in the same repository as the files it describes. It stops
drift and accidents; an edit that also rewrites the MANIFEST passes. Branch protection with a
required pipeline is what stops a deliberate edit.

**Remote (`--source remote`).** GitLab, in `.gitlab-ci.yml`:

```yaml
include:
  - remote: https://raw.githubusercontent.com/loonix/prumo-pack/v0/templates/ci/gitlab/prumo.yml
variables:
  PRUMO_FAIL_CLOSED_DIRS: "src services"   # default "."
```

Jobs `prumo-trace`, `prumo-fail-closed` and `prumo-metabolic` clone the pack at `PRUMO_PACK_REF`
(default `v0`, from `PRUMO_PACK_URL`) outside the project and run the checks. `prumo-anti-leak`
runs only with `PRUMO_ANTI_LEAK: "on"` (arguments in `PRUMO_ANTI_LEAK_ARGS`). No job has
`allow_failure`. Deploy jobs must `needs:` every test job; the pattern is in the template header.

GitHub: copy `templates/ci/github/prumo.yml` to `.github/workflows/`. It calls the reusable
workflow `loonix/prumo-pack/.github/workflows/prumo.yml@v0` with inputs `pack_ref`,
`fail_closed_dirs`, `anti_leak` (default false) and `anti_leak_args`. Keep the ref after `@`
and `pack_ref` equal.

The project needs `.prumo/regression-rules/` and `.prumo/subsystems.yml`; the checks fail
without them.

**Limit:** the templates are checked for structure, script paths and the absence of soft
failure, not executed on a real runner by this pack's tests. The vendored jobs were replayed
locally from their YAML in a fresh clone of a consumer (green, and red on one tampered byte).
While this repository is private, the remote form cannot be read by a GitLab runner or by a
GitHub repository of another owner; the vendored form has no such limit.

## agent/claude-plugin

A Claude Code plugin named `prumo`. Three PreToolUse hooks, python3 stdlib, no LLM call. A block
is exit 2 with the reason on stderr, which Claude Code feeds back to the model. Input the hook
cannot read (bad JSON, missing fields, unparsable command) blocks rather than allows.

| Hook | Tools | Blocks |
|---|---|---|
| `no_em_dash.py` | Write, Edit, MultiEdit | new text containing U+2014 |
| `protected_push.py` | Bash | `git push` updating main, master or develop: explicit refspec (`main`, `+main`, `HEAD:main`, `:main`, `--delete main`, wildcards), `--all`/`--mirror`, or no refspec while the current branch or its upstream is protected |
| `ci_soft_fail.py` | Write, Edit, MultiEdit | `.gitlab-ci.yml`, `*.gitlab-ci.yml` or `.github/workflows/*.yml` gaining `allow_failure: true` or `continue-on-error: true` (or `${{ }}`) |

`PRUMO_PROTECTED_BRANCHES="main,release"` replaces the protected list (empty keeps the default).
`git push --dry-run` is allowed: the remote is not updated.

Skills: `prumo-certify-before-done`, `prumo-trace`, `prumo-worktree`. `CLAUDE.fragment.md` is a
rules block to paste into a project's `CLAUDE.md`.

```sh
claude --plugin-dir agent/claude-plugin     # one session
claude plugin validate agent/claude-plugin  # manifest check
```

**Limit:** hooks see only what the tool call says. The push hook does not follow git aliases,
scripts, `remote.<name>.push` config or variables (a refspec with `$` blocks); it does not stop
merges through `gh`/`glab` or the web UI. The CI hook does not see files written through Bash
(`sed -i`, `echo >>`). Branch protection on the server stays the real gate; these hooks stop the
agent earlier.

## Development

```sh
make test         # runs tests/run.sh; zero cases run counts as a failure
make trace        # runs prumo-trace over this repo
make fail-closed  # runs checks/fail-closed.sh over bin, lib and checks
make leak         # runs checks/anti-leak.sh over this repo
```

Needs only `bash` and `python3` (stdlib).

## License

MIT, Daniel Carneiro.
