/**
 * `bun run measure:waterfall --path '/en/projects/42'`: one fresh load of a URL, with every API
 * request and image it made, when each started and when it ended. A request that starts right as
 * another one ends is flagged: it is either waiting on a value only that answer carries, which its
 * `enabled:` must say, or a waterfall to remove (.claude/rules/web/data-fetching.md, W6 and W7).
 * Optional module: delete it, its package script and its playwright-core dependency together.
 *
 *   --path  <path>   the page to load, starting with `/` (required)
 *   --url   <base>   the dev server, default http://localhost:3000
 *   --state <file>   a Playwright storage-state file for a screen behind sign-in, saved from a
 *                    test account (never a real person's); the file holds a session, so keep it
 *                    out of git
 *
 * Development only: the base URL must be a local server.
 */
import { chromium, type Browser, type Request } from 'playwright-core';

const args = process.argv.slice(2);
const option = (flag: string): string | undefined =>
  args.includes(flag) ? args[args.indexOf(flag) + 1] : undefined;
const BASE = option('--url') ?? 'http://localhost:3000';
const PATH = option('--path');
const STATE = option('--state');
/* A start this close after another request's end reads as waiting on it: under one frame, and
   well under any round trip an API makes. */
const CHAINED_MS = 40;
const TRACKED = new Set(['fetch', 'xhr', 'image', 'document']);
/* Requests every other one waits on by design (a token or key exchange), each with the reason it
   is never a waterfall: `['/api/session', 'every request reads the session it returns']`. */
const BY_DESIGN = new Map<string, string>([]);

interface Row {
  url: string;
  type: string;
  start: number;
  end: number;
}

async function launch(): Promise<Browser> {
  try {
    return await chromium.launch();
  } catch {
    /* The cached browser build matches the pinned playwright-core; after an upgrade it may not. */
    return await chromium.launch({ channel: 'chrome' });
  }
}

/** The request that ended just before `row` started, when the gap is short enough to be a wait. */
function chainedAfter(row: Row, rows: Row[]): Row | undefined {
  return rows
    .filter((other) => other !== row && other.type !== 'document' && !BY_DESIGN.has(other.url))
    .filter((other) => other.end <= row.start)
    .filter((other) => row.start - other.end <= CHAINED_MS)
    .sort((a, b) => b.end - a.end)[0];
}

async function main(): Promise<void> {
  if (!PATH?.startsWith('/')) throw new Error("Pass --path '/<locale>/<page>'");
  if (!/^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(BASE)) {
    throw new Error(`--url must be a local dev server, not ${BASE}`);
  }
  const browser = await launch();
  try {
    const context = await browser.newContext(STATE ? { storageState: STATE } : {});
    const page = await context.newPage();
    const rows: Row[] = [];
    const starts = new Map<Request, number>();
    const t0 = Date.now();
    page.on('request', (request) => starts.set(request, Date.now() - t0));
    page.on('requestfinished', (request) => {
      if (!TRACKED.has(request.resourceType())) return;
      const url = request.url().replace(BASE, '');
      if (url.startsWith('/_next/')) return;
      rows.push({
        url,
        type: request.resourceType(),
        start: starts.get(request) ?? 0,
        end: Date.now() - t0,
      });
    });

    await page.goto(`${BASE}${PATH}`);
    await page.waitForLoadState('networkidle');

    rows.sort((a, b) => a.start - b.start);
    let flagged = 0;
    for (const row of rows) {
      const after = row.type === 'fetch' ? chainedAfter(row, rows) : undefined;
      if (after) flagged += 1;
      const mark = after ? `  ⚠ after ${after.url.slice(0, 60)}` : '';
      console.log(
        `${String(row.start).padStart(6)} → ${String(row.end).padStart(6)}  ${row.type.padEnd(8)} ${row.url.slice(0, 90)}${mark}`,
      );
    }
    console.log(`\n${rows.length} requests, ${flagged} started as another ended.`);
  } finally {
    await browser.close();
  }
}

await main();
