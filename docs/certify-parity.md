# prumo-certify: parity with the production certifier

`bin/prumo-certify` is a generic port of a project specific certifier that runs in
production today (three scripts plus a JSON list of requests). This note records
what was ported, what was left out, and what was NOT verified.

## Parity against the live site, read-only layers (28 Sep 2026)

Both certifiers ran against the live site they certify, at the same commit of the
project (`e0e0578`), with a `prumo-certify.json` generated from the original's request
list. Only read-only layers ran: file parity and the rendered DOM. The backend layer
sends write requests to production (invalid on purpose) and was not run; that call
stays with the owner of the deployment.

| Layer | Original | prumo-certify |
|---|---|---|
| File parity, private prefixes, floor of 40 | 69 checked, 0 failures | 69 checked, 0 failures |
| Rendered DOM, 40 pages that declare visible text | pass | 40 passed |
| Rendered DOM, 42 pages that declare only absences, selectors or images | pass | refused the manifest; after the fix, 42 passed |
| 2 pages that click or resize before reading | pass | not expressible, left out |
| 12 pages with pixel or size assertions | pass | text and selectors checked, pixel parts not ported |

The refusal was a real divergence: `expect_text` was mandatory, so a page could not
assert only that something is gone. Fixed by making every assertion list optional and
refusing a page that declares none. Regression tests: "a check asserting only absences
passes, expect_text is optional" and "frontend check with no assertion at all fails".

After the fix the full manifest gives 151 declared, 151 passed (69 files, 82 pages).

## Backend layer, side by side against a local instance (28 Sep 2026)

This ran against a local build of the project at commit `789c3fd`, NOT production:
the API on `http://127.0.0.1:18087`, a throwaway empty database, throwaway secrets,
`STRIPE_ENABLED=false`, InvoiceXpress, SMTP and the alert webhook off. No request left
localhost. The manifest mirrors every request of the original, same order, 17 entries.
The port cannot log in by itself, so the admin token was fetched with one `curl` and
passed as `ADMIN_TOKEN`; the login check itself is still declared.

| Check | Original | prumo-certify |
|---|---|---|
| Health says db ok | pass | pass |
| Config exposes the Stripe publishable key | fail | fail |
| Stripe webhook requires a signature (400) | fail, got 200 | fail, got 200 |
| Intake refuses a wrong key (401) | pass | pass |
| Admin refuses a wrong password (401) | pass | pass |
| Broker dashboard requires a session (401) | pass | pass |
| Terms PT, EN, FR, ES are not public pages (404, 4 checks) | 4 pass | 4 pass |
| Legal text not served by the portal static dir (404) | pass | pass |
| Legal text requires an account (401) | pass | pass |
| Admin logs in with the right password | pass | pass |
| Four invalid leads refused (400, 4 checks) | 4 pass | 4 pass |
| Footer logo has no coloured pixel | pass | not ported |
| **Total** | 16 OK, 2 failures, exit 1 | 17 declared, 15 passed, 2 failed, exit 1 |

No divergence on the 17 shared checks. The two failures are the same in both and are
caused by the local environment, not by either certifier: with Stripe disabled the API
serves no publishable key and the webhook answers 200 `stripe_disabled`. Both
certifiers caught it. No lead was created (the `leads` table was empty after the run).

Control with the admin secret unset: the original reports 11 OK, 3 failures (one line
for the whole business rule block); the port reports 10 passed, 7 failed (each check
that needs the secret fails on its own, request not sent). Both exit 1. Different
counts, same verdict, by design.

Still not verified: the backend layer against production, and the business rules
against a build where a rule is broken (every rule check passed here, so only the two
Stripe checks exercised the failure path).

## What was ported

| Original layer | prumo-certify |
|---|---|
| Walk the static build directory and compare sha256 of each file with what the site serves | `files`, with `local_dir` + `url_prefix`, or one `local` + `url` |
| Build files under a list of non public prefixes must answer 404, any other status fails | `private_prefixes` on a `local_dir` entry; a prefix matching no file is a manifest error |
| Refuse when fewer than a minimum number of files were checked | `min_count` on a `local_dir` entry (the original applied one floor to the whole run) |
| Hand written curl calls with expected status codes, invalid writes the API must refuse | `backend`, declared as data: `method`, `path`, `headers`, `body`, `expect_status`, `expect_body_contains` |
| Secret missing means the business rules were not verified, which counts as a failure | `${NAME}` in path, headers or body; an unset variable fails the check |
| Visible text in the rendered DOM (innerText), no console errors, HTTP 200 | `frontend`, with `expect_text` |
| Texts that must no longer appear in the rendered DOM, case-insensitive | `expect_absent` |
| Elements that must be visible | `expect_visible_selector` (first match: rendered, non-zero box, `visibility: visible`) |
| Images that must have loaded (complete, naturalWidth above 0) | `expect_image_loaded` |
| Exit 0 only when every layer passed | Same, plus: zero declared checks, an unknown key or a SKIPPED check is a failure |

## What was left out, on purpose

- **Automatic cleanup** of a resource created by a write that should have been
  refused. It needs project knowledge (which id, which delete endpoint). The port
  fails the check and says a resource may have been created; cleanup is manual.
- **Login flows** that fetch a token and reuse it. Pass the token through the
  environment (`Authorization: Bearer ${API_TOKEN}`) instead.
- **Frontend extras** of the original: clicks before reading, WCAG contrast, ink and
  border checks, same-size comparisons, custom viewports, screenshots and a timestamped
  report file. Candidates for later, each with a test first.
- **Image pixel checks** (the original asserted a served logo had no coloured pixel,
  using an imaging library outside the stdlib).
- **Redirects**: the port does not follow them, a 302 is checked as a 302. Declare the
  final url for file parity.
