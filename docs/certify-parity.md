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

Still not verified: the backend layer side by side.

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
