// Rendered DOM layer of prumo-certify. Opens each page in a real browser and
// checks the VISIBLE text (innerText ignores what CSS hides) and the console.
//
// Run mode:   node prumo_certify_dom.mjs < job.json
//   job: {"base_url": "...", "resolve_from": [dirs], "checks": [
//          {"name": "...", "path": "/", "expect_text": ["..."],
//           "expect_absent": ["..."], "expect_visible_selector": ["css"],
//           "expect_image_loaded": ["css"]}]}
//   prints one JSON line per check: {"name": "...", "ok": true|false, "detail": "..."}
// Probe mode: node prumo_certify_dom.mjs --probe [dirs...]
//   exits 0 when playwright loads and chromium starts.
//
// Exit 3 means the tool is missing (playwright not resolvable or chromium does
// not start). The caller reports that as SKIPPED, which counts as a failure.

import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const TOOL_MISSING = 3;

// Resolve playwright from the project (manifest dir, working dir) or NODE_PATH.
function loadPlaywright(dirs) {
  for (const d of [...dirs, process.cwd()]) {
    try {
      return createRequire(join(resolve(d), 'noop.js'))('playwright');
    } catch {
      // try the next place
    }
  }
  return null;
}

function missing(message) {
  process.stderr.write(message + '\n');
  process.exit(TOOL_MISSING);
}

async function launch(dirs) {
  const pw = loadPlaywright(dirs);
  if (!pw) missing('playwright not found: install it in the project or set NODE_PATH');
  try {
    return await pw.chromium.launch();
  } catch (e) {
    missing('chromium could not start: ' + String(e).split('\n')[0]);
  }
}

// Runs in the page. Returns why the first element matching sel is not visible,
// or '' when it is rendered, has a non-zero box and computed visibility visible.
function selectorHidden(sel) {
  let el;
  try {
    el = document.querySelector(sel);
  } catch {
    return 'invalid selector';
  }
  if (!el) return 'no element matches';
  if (typeof el.checkVisibility === 'function' && !el.checkVisibility()) {
    return 'display:none on it or an ancestor';
  }
  const style = getComputedStyle(el);
  if (style.display === 'none') return 'display:none on it or an ancestor';
  if (style.visibility !== 'visible') return `visibility:${style.visibility}`;
  const box = el.getBoundingClientRect();
  if (box.width === 0 || box.height === 0) return 'zero-size box';
  return '';
}

// Runs in the page. A broken image still has a box, so visibility says nothing
// about it: this reads whether the first <img> matching sel decoded.
function imageNotLoaded(sel) {
  let el;
  try {
    el = document.querySelector(sel);
  } catch {
    return 'invalid selector';
  }
  if (!el) return 'no element matches';
  if (!(el instanceof HTMLImageElement)) return 'not an img element';
  if (!el.complete) return 'still loading';
  if (el.naturalWidth === 0) return 'complete but naturalWidth 0';
  return '';
}

async function checkPage(browser, base, c) {
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e).slice(0, 160)));
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text().slice(0, 160)); });
  const problems = [];
  try {
    const resp = await page.goto(base + c.path, { waitUntil: 'networkidle', timeout: 30000 });
    if (!resp || resp.status() !== 200) problems.push(`HTTP ${resp ? resp.status() : 'no response'}`);
    const text = await page.evaluate(() => document.body ? document.body.innerText : '');
    const absent = (c.expect_text || []).filter((t) => !text.includes(t));
    if (absent.length) problems.push('not visible: ' + absent.map((t) => JSON.stringify(t)).join(', '));
    // Absence is checked case-insensitively: "Sold out" and "SOLD OUT" are the same leak.
    const lower = text.toLowerCase();
    const present = (c.expect_absent || []).filter((t) => lower.includes(t.toLowerCase()));
    if (present.length) problems.push('still visible: ' + present.map((t) => JSON.stringify(t)).join(', '));
    const hidden = [];
    for (const sel of c.expect_visible_selector || []) {
      const why = await page.evaluate(selectorHidden, sel);
      if (why) hidden.push(`${sel} (${why})`);
    }
    if (hidden.length) problems.push('selector not visible: ' + hidden.join(', '));
    const unloaded = [];
    for (const sel of c.expect_image_loaded || []) {
      const why = await page.evaluate(imageNotLoaded, sel);
      if (why) unloaded.push(`${sel} (${why})`);
    }
    if (unloaded.length) problems.push('image not loaded: ' + unloaded.join(', '));
    if (errors.length) problems.push(`console error: ${errors[0]}` + (errors.length > 1 ? ` (+${errors.length - 1} more)` : ''));
  } catch (e) {
    problems.push('page did not load: ' + String(e).split('\n')[0].slice(0, 160));
  }
  await ctx.close();
  return { name: c.name, ok: problems.length === 0, detail: problems.join('; ') };
}

const args = process.argv.slice(2);
if (args[0] === '--probe') {
  const browser = await launch(args.slice(1));
  await browser.close();
  process.exit(0);
}

const job = JSON.parse(readFileSync(0, 'utf8'));
const browser = await launch(job.resolve_from || []);
for (const c of job.checks) {
  process.stdout.write(JSON.stringify(await checkPage(browser, job.base_url, c)) + '\n');
}
await browser.close();
