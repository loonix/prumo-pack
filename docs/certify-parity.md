# prumo-certify: parity with the production certifier

`bin/prumo-certify` is a generic port of a project specific certifier that runs in
production today (three scripts plus a JSON list of requests). This note records
what was ported, what was left out, and what was NOT verified.

## Not run: parity against the live site

The original certifier and `prumo-certify` were **not** run side by side against the
live site the original certifies. Doing so sends real requests to production,
including write requests (invalid on purpose, but writes all the same). That call
belongs to the human who owns that deployment, not to the agent that wrote the port.

What was measured here is only the pack's own test suite (`tests/test_certify.sh`)
against a local stdlib server (`tests/fixtures/certify/server.py`). Passing those
tests says the port honours its own contract, not that it reaches the same verdict
as the original on the same site.

To close the gap, the owner of the deployment would:

1. write a `prumo-certify.json` that declares the same checks as the original;
2. run both certifiers against the same base url at the same commit;
3. compare verdicts check by check, and add a regression test for any divergence.

## What was ported

| Original layer | prumo-certify |
|---|---|
| Walk the static build directory and compare sha256 of each file with what the site serves | `files`, with `local_dir` + `url_prefix`, or one `local` + `url` |
| Hand written curl calls with expected status codes, invalid writes the API must refuse | `backend`, declared as data: `method`, `path`, `headers`, `body`, `expect_status`, `expect_body_contains` |
| Secret missing means the business rules were not verified, which counts as a failure | `${NAME}` in path, headers or body; an unset variable fails the check |
| Visible text in the rendered DOM (innerText), no console errors, HTTP 200 | `frontend`, with `expect_text` |
| Exit 0 only when every layer passed | Same, plus: zero declared checks, an unknown key or a SKIPPED check is a failure |

## What was left out, on purpose

- **Automatic cleanup** of a resource created by a write that should have been
  refused. It needs project knowledge (which id, which delete endpoint). The port
  fails the check and says a resource may have been created; cleanup is manual.
- **Login flows** that fetch a token and reuse it. Pass the token through the
  environment (`Authorization: Bearer ${API_TOKEN}`) instead.
- **Frontend extras** of the original: texts that must be absent, selectors that must
  be visible, clicks before reading, WCAG contrast, custom viewports, screenshots and
  a timestamped report file. Candidates for later, each with a test first.
- **Image pixel checks** (the original asserted a served logo had no coloured pixel,
  using an imaging library outside the stdlib).
- **Redirects**: the port does not follow them, a 302 is checked as a 302. Declare the
  final url for file parity.
