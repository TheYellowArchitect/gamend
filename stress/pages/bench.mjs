#!/usr/bin/env node
/**
 * Page bench: how long every page takes at the size of the data behind it.
 *
 * For each page in the spec files it loads the page over HTTP, joins its
 * LiveView socket the way a browser does, and fires the events it finds on
 * the page that only read: next/previous page, jumps, sorts, tabs, the search
 * boxes (a broad term, one exact name, a term that matches nothing) and the
 * page-size selects. Every step is timed and checked; a step that errors, a
 * LiveView that crashes or a page that answers 500 fails the run.
 *
 * Run it through `mix demo.bench`, which signs in and passes the cookies:
 *
 *   mix demo.bench --base-url http://localhost:4091 --label 100k
 *
 * Or compare finished runs:
 *
 *   node stress/pages/bench.mjs --compare results/pages/10k.json results/pages/1m.json
 *
 * Environment (set by the mix task):
 *   BENCH_ADMIN_COOKIE, BENCH_PLAYER_COOKIE  "name=value" remember-me cookies
 *   BENCH_PARAMS                              JSON: ids and terms for {placeholders}
 *
 * A spec file exports `pages`, each `{path, as}` plus optional:
 *   name      label in the report (default: the path)
 *   as        "admin" | "player" | "visitor" (default "visitor")
 *   actions   replace discovery with these steps (below)
 *   extra     steps run after the discovered ones
 *   skip      event names discovery must not fire
 * A step is one of
 *   {click: "event", value: {...}, times: n}
 *   {change: "event", form: {field: "value"}}   (fields support {placeholders})
 *   {patch: "/path?query"}                     (a live_patch, handle_params)
 */

import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { performance } from 'node:perf_hooks';

const SLOW_MS = 250;
const VERY_SLOW_MS = 1000;
const STEP_TIMEOUT_MS = 120_000;

// Event names that change something. Discovery never fires them, whatever
// else the name says: a bench that deletes rows measures a different page
// on every run.
const WRITES =
  /(delete|destroy|remove|kick|ban|lift|revoke|refund|grant|resolve|dismiss|cancel|save|create|update|submit|send|reset|purge|clear|disable|enable|block|approve|reject|close|claim|buy|purchase|unlock|lock|leave|join|start|stop|retry|import|export|upload|restart|confirm|logout|log_out|merge|seed|mark|archive|restore|promote|demote|invite|accept|decline|kill|flush|reload|rotate|regenerate|activate|deactivate|ping|copy|download|generate|apply|set_|assign|add_|new_|play|pause|resume|report|mute|hide|pin|vote|follow|friend|subscribe|notify|push|broadcast|trigger|test_|run_|bulk|toggle_(?!select|provider)|prefill)/i;

// Event names that only change what is shown.
const READS =
  /(next|prev|page|sort|tab|period|filter|provider|view|show|select|open|inspect|edit|expand|collapse|more|detail|records|members|range|day|week|month|segment|breakdown|explore|search|refresh|group|order|scope|status|kind|chart)/i;

const SIZE_FIELDS = /(page_size|per_page|size|limit)/i;

// ── CLI ─────────────────────────────────────────────────────────────────

function parseArgs(argv) {
  const opts = { spec: [], compare: [] };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const next = () => argv[++i];
    if (arg === '--base') opts.base = next();
    else if (arg === '--label') opts.label = next();
    else if (arg === '--out') opts.out = next();
    else if (arg === '--spec') opts.spec.push(next());
    else if (arg === '--only') opts.only = next();
    else if (arg === '--repeat') opts.repeat = Number(next());
    else if (arg === '--compare') {
      while (argv[i + 1] && !argv[i + 1].startsWith('--')) opts.compare.push(argv[++i]);
    } else throw new Error(`unknown argument: ${arg}`);
  }
  return opts;
}

// ── Cookies ─────────────────────────────────────────────────────────────

class Jar {
  constructor(seed) {
    this.cookies = new Map();
    if (seed) this.set(seed);
  }

  set(pair) {
    const eq = pair.indexOf('=');
    this.cookies.set(pair.slice(0, eq).trim(), pair.slice(eq + 1).trim());
  }

  absorb(res) {
    for (const line of res.headers.getSetCookie?.() ?? []) {
      const pair = line.split(';')[0];
      const value = pair.slice(pair.indexOf('=') + 1);
      if (value === '' || /max-age=0/i.test(line)) this.cookies.delete(pair.split('=')[0]);
      else this.set(pair);
    }
  }

  header() {
    return [...this.cookies].map(([k, v]) => `${k}=${v}`).join('; ');
  }
}

// ── HTML ────────────────────────────────────────────────────────────────

const ENTITIES = { '&quot;': '"', '&amp;': '&', '&#39;': "'", '&lt;': '<', '&gt;': '>', '&#x27;': "'" };

function unescape(text) {
  return text.replace(/&(quot|amp|#39|#x27|lt|gt);/g, (m) => ENTITIES[m]);
}

function attrs(source) {
  const out = {};
  for (const m of source.matchAll(/([\w:.@-]+)(?:="([^"]*)")?/g)) out[m[1]] = m[2] === undefined ? '' : unescape(m[2]);
  return out;
}

function tags(html, name) {
  const re = new RegExp(`<${name}\\b([^>]*)>`, 'gi');
  return [...html.matchAll(re)].map((m) => ({ attrs: attrs(m[1]), index: m.index, end: m.index + m[0].length }));
}

function mainLiveView(html) {
  for (const tag of tags(html, '[a-z][\\w-]*')) {
    const a = tag.attrs;
    if ('data-phx-main' in a && a['data-phx-session']) {
      return { id: a.id, session: a['data-phx-session'], static: a['data-phx-static'] || '' };
    }
  }
  return null;
}

function csrfToken(html) {
  const meta = tags(html, 'meta').find((t) => t.attrs.name === 'csrf-token');
  return meta?.attrs.content;
}

// The events an element sends on click: a plain name, or the push ops of a
// JS command (`[["push", {"event": ...}]]`).
function clickEvents(value) {
  if (!value.startsWith('[')) return [{ event: value, value: {} }];
  try {
    return JSON.parse(value)
      .filter(([op]) => op === 'push')
      .map(([, args]) => ({ event: args.event, value: args.value || {} }));
  } catch {
    return [];
  }
}

function phxValues(a) {
  const value = {};
  for (const [k, v] of Object.entries(a)) if (k.startsWith('phx-value-')) value[k.slice(10)] = v;
  return value;
}

function target(a) {
  const t = a['phx-target'];
  if (t === undefined) return {};
  return /^\d+$/.test(t) ? { cid: Number(t) } : null;
}

// What a page offers that only reads, in the order a person would try it.
export function discover(html, params, skip = []) {
  const steps = [];
  const seen = new Set();
  const allowed = (event) => event && !skip.includes(event) && !WRITES.test(event) && READS.test(event);

  const clicks = [];
  for (const tag of tags(html, '[a-z][\\w-]*')) {
    const raw = tag.attrs['phx-click'];
    if (!raw || tag.attrs.disabled !== undefined) continue;
    const t = target(tag.attrs);
    if (!t) continue;
    for (const { event, value } of clickEvents(raw)) {
      if (!allowed(event)) continue;
      const merged = { ...phxValues(tag.attrs), ...value };
      const key = `${event} ${JSON.stringify(merged)}`;
      if (seen.has(key)) continue;
      seen.add(key);
      clicks.push({ click: event, value: merged, ...t });
    }
  }

  const next = clicks.filter((c) => /next/i.test(c.click));
  const jumps = clicks.filter((c) => /page/i.test(c.click) && !/next|prev|size/i.test(c.click));
  const prev = clicks.filter((c) => /prev/i.test(c.click));
  const rest = clicks.filter((c) => !next.includes(c) && !jumps.includes(c) && !prev.includes(c));

  // Three pages forward, then the furthest page a jump offers, then back.
  if (next[0]) steps.push({ ...next[0], times: 3 });
  const deepest = jumps
    .map((c) => ({ c, n: Number(Object.values(c.value)[0]) }))
    .filter(({ n }) => Number.isFinite(n))
    .sort((a, b) => b.n - a.n)[0];
  if (deepest) steps.push(deepest.c);
  if (prev[0]) steps.push(prev[0]);

  // Sorts next, one per field; then the forms; the other events (filters,
  // tabs, row details) last, since a filter narrows what a search after it
  // would read.
  const sorts = rest.filter((c) => /sort|order/i.test(c.click));
  const others = rest.filter((c) => !sorts.includes(c));
  steps.push(...sorts.slice(0, 4));

  const perEvent = new Map();
  for (const c of others) {
    const list = perEvent.get(c.click) || [];
    if (list.length < 2) list.push(c);
    perEvent.set(c.click, list);
  }
  const later = [...perEvent.values()].flat();

  for (const form of tags(html, 'form')) {
    const event = form.attrs['phx-change'] || (READS.test(form.attrs['phx-submit'] || '') ? form.attrs['phx-submit'] : null);
    if (!allowed(event)) continue;
    const t = target(form.attrs);
    if (!t) continue;
    const close = html.indexOf('</form>', form.end);
    const body = html.slice(form.end, close === -1 ? undefined : close);
    const fields = formFields(body);
    const base = Object.fromEntries(fields.map((f) => [f.name, f.value]));

    for (const f of fields) {
      if (f.kind === 'text') {
        for (const term of [params.search_broad, params.search_hit, params.search_miss].filter(Boolean)) {
          steps.push({ change: event, form: { ...base, [f.name]: term }, target: f.name, ...t });
        }
        // Cleared again: the whole list, and the state the next step expects.
        steps.push({ change: event, form: base, target: f.name, ...t });
      } else if (f.kind === 'select' && f.options.length > 1) {
        const options = SIZE_FIELDS.test(f.name)
          ? [f.options.reduce((a, b) => (Number(b) > Number(a) ? b : a))]
          : f.options.filter((o) => o !== f.value).slice(0, 3);
        for (const option of options) steps.push({ change: event, form: { ...base, [f.name]: option }, target: f.name, ...t });
      }
    }
  }

  steps.push(...later);
  return steps;
}

function formFields(body) {
  const fields = [];
  for (const input of tags(body, 'input')) {
    const a = input.attrs;
    const type = (a.type || 'text').toLowerCase();
    if (!a.name || a.disabled !== undefined) continue;
    if (['text', 'search', 'email'].includes(type)) fields.push({ name: a.name, kind: 'text', value: a.value || '' });
    else if (type === 'hidden') fields.push({ name: a.name, kind: 'hidden', value: a.value || '' });
    else if (['checkbox', 'radio'].includes(type) && a.checked !== undefined) fields.push({ name: a.name, kind: 'hidden', value: a.value || 'on' });
  }
  for (const select of tags(body, 'select')) {
    const a = select.attrs;
    if (!a.name || a.disabled !== undefined) continue;
    const close = body.indexOf('</select>', select.end);
    const options = tags(body.slice(select.end, close), 'option').map((o) => o.attrs);
    const values = options.map((o) => o.value ?? '');
    const chosen = options.find((o) => o.selected !== undefined)?.value ?? values[0] ?? '';
    fields.push({ name: a.name, kind: 'select', value: chosen, options: values });
  }
  return fields;
}

// ── LiveView socket ─────────────────────────────────────────────────────

class LiveSocket {
  constructor(base, jar, csrf) {
    const url = new URL('/live/websocket', base);
    url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
    url.searchParams.set('_csrf_token', csrf);
    url.searchParams.set('vsn', '2.0.0');
    this.ref = 0;
    this.pending = new Map();
    this.crashed = null;
    this.ws = new WebSocket(url, { headers: { cookie: jar.header(), origin: base } });
    this.ws.onmessage = (msg) => this.receive(JSON.parse(msg.data));
  }

  open() {
    return new Promise((resolve, reject) => {
      this.ws.onopen = resolve;
      this.ws.onerror = (e) => reject(new Error(`socket: ${e.message || 'failed to open'}`));
    });
  }

  receive([, ref, topic, event, payload]) {
    if (event === 'phx_error' || event === 'phx_close') {
      this.crashed = `${event} on ${topic}`;
      for (const { reject } of this.pending.values()) reject(new Error(this.crashed));
      this.pending.clear();
      return;
    }
    if (event !== 'phx_reply' || !this.pending.has(ref)) return;
    const { resolve } = this.pending.get(ref);
    this.pending.delete(ref);
    resolve(payload);
  }

  push(topic, event, payload, joinRef) {
    const ref = String(++this.ref);
    const frame = JSON.stringify([joinRef ?? this.joinRef, ref, topic, event, payload]);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(ref);
        reject(new Error(`no reply in ${STEP_TIMEOUT_MS / 1000}s`));
      }, STEP_TIMEOUT_MS);
      this.pending.set(ref, {
        resolve: (p) => (clearTimeout(timer), resolve({ payload: p, bytes: 0 })),
        reject: (e) => (clearTimeout(timer), reject(e)),
      });
      this.ws.send(frame);
    });
  }

  async join(lv, url, csrf) {
    this.topic = `lv:${lv.id}`;
    this.joinRef = String(this.ref + 1);
    return this.push(this.topic, 'phx_join', {
      url,
      params: { _csrf_token: csrf, _mounts: 0, _mount_attempts: 0 },
      session: lv.session,
      static: lv.static,
      sticky: false,
    }, this.joinRef);
  }

  close() {
    try {
      this.ws.close();
    } catch {}
  }
}

// ── Running a page ──────────────────────────────────────────────────────

function fill(text, params) {
  return text.replace(/\{(\w+)\}/g, (m, key) => (params[key] !== undefined && params[key] !== null ? encodeURIComponent(params[key]) : m));
}

function fillValue(text, params) {
  return String(text).replace(/\{(\w+)\}/g, (m, key) => (params[key] ?? m));
}

function stepLabel(step) {
  if (step.click) {
    const v = Object.entries(step.value || {}).map(([k, x]) => `${k}=${String(x).slice(0, 24)}`).join(' ');
    return `click ${step.click}${v ? ` ${v}` : ''}`;
  }
  if (step.change) return `change ${step.change} ${step.target ?? ''}=${String(step.form?.[step.target] ?? '').slice(0, 24)}`.trim();
  if (step.patch) return `patch ${step.patch}`;
  return JSON.stringify(step);
}

function payloadFor(step, params) {
  if (step.click) {
    return { event: 'event', body: { type: 'click', event: step.click, value: step.value || {}, ...(step.cid ? { cid: step.cid } : {}) } };
  }
  if (step.change) {
    const form = Object.fromEntries(Object.entries(step.form || {}).map(([k, v]) => [k, fillValue(v, params)]));
    const query = new URLSearchParams(form);
    if (step.target) query.set('_target', step.target);
    return { event: 'event', body: { type: 'form', event: step.change, value: query.toString(), uploads: {}, ...(step.cid ? { cid: step.cid } : {}) } };
  }
  if (step.patch) return { event: 'live_patch', body: { url: null } };
  throw new Error(`unknown step ${JSON.stringify(step)}`);
}

function replyProblem(payload) {
  if (!payload) return 'empty reply';
  if (payload.status !== 'ok') return `status ${payload.status}: ${JSON.stringify(payload.response).slice(0, 160)}`;
  const response = payload.response || {};
  if (response.live_redirect || response.redirect) return null;
  return null;
}

async function runPage(page, ctx) {
  const results = [];
  const record = (label, ms, extra = {}) => results.push({ label, ms, ...extra });
  const jar = new Jar(ctx.cookies[page.as || 'visitor']);
  const url = new URL(fill(page.path, ctx.params), ctx.base).toString();

  const t0 = performance.now();
  let res;
  try {
    res = await fetch(url, { headers: { cookie: jar.header(), accept: 'text/html' }, redirect: 'manual' });
  } catch (e) {
    record('GET', performance.now() - t0, { error: `fetch: ${e.message}` });
    return results;
  }
  const html = await res.text();
  jar.absorb(res);
  const getMs = performance.now() - t0;
  const redirect = res.status >= 300 && res.status < 400 ? res.headers.get('location') : null;
  record('GET', getMs, {
    status: res.status,
    bytes: html.length,
    ...(res.status >= 500 || res.status === 429 ? { error: `HTTP ${res.status}` } : {}),
    ...(redirect ? { note: `-> ${redirect}` } : res.status !== 200 ? { note: `HTTP ${res.status}` } : {}),
  });
  if (res.status !== 200) return results;

  const lv = mainLiveView(html);
  if (!lv) return results;
  const csrf = csrfToken(html);
  const socket = new LiveSocket(ctx.base, jar, csrf);

  try {
    await socket.open();
    const tj = performance.now();
    const { payload } = await socket.join(lv, url, csrf);
    const problem = replyProblem(payload);
    const joined = JSON.stringify(payload).length;
    record('join', performance.now() - tj, { bytes: joined, ...(problem ? { error: problem } : {}) });
    if (problem) return results;
    if (payload.response?.live_redirect || payload.response?.redirect) {
      results.at(-1).note = 'redirected on join';
      return results;
    }

    const steps = page.actions || [...discover(html, ctx.params, page.skip), ...(page.extra || [])];
    for (const step of steps) {
      for (let n = 1; n <= (step.times || 1); n++) {
        const label = stepLabel(step) + (step.times > 1 ? ` #${n}` : '');
        const { event, body } = payloadFor(step, ctx.params);
        if (event === 'live_patch') body.url = new URL(fill(step.patch, ctx.params), ctx.base).toString();
        const ts = performance.now();
        try {
          const { payload: reply } = await socket.push(socket.topic, event, body);
          const problem = replyProblem(reply);
          record(label, performance.now() - ts, { bytes: JSON.stringify(reply).length, ...(problem ? { error: problem } : {}) });
          if (problem) break;
        } catch (e) {
          record(label, performance.now() - ts, { error: e.message });
          return results;
        }
      }
    }
  } catch (e) {
    record('join', 0, { error: e.message });
  } finally {
    socket.close();
  }
  return results;
}

// ── Report ──────────────────────────────────────────────────────────────

const median = (xs) => {
  const s = [...xs].sort((a, b) => a - b);
  return s.length ? s[Math.floor((s.length - 1) / 2)] : NaN;
};

function fmtMs(ms) {
  if (!Number.isFinite(ms)) return '-';
  return ms >= 1000 ? `${(ms / 1000).toFixed(2)}s` : `${ms.toFixed(0)}ms`;
}

function flag(ms, error) {
  if (error) return 'ERROR';
  if (ms >= VERY_SLOW_MS) return 'VERY SLOW';
  if (ms >= SLOW_MS) return 'slow';
  return '';
}

function summarise(runs) {
  // runs: [[step results of run 1], [run 2], ...] for one page
  const byLabel = new Map();
  for (const run of runs) {
    for (const step of run) {
      const row = byLabel.get(step.label) || { label: step.label, ms: [], errors: [], bytes: step.bytes, status: step.status, note: step.note };
      row.ms.push(step.ms);
      if (step.error) row.errors.push(step.error);
      byLabel.set(step.label, row);
    }
  }
  return [...byLabel.values()].map((row) => ({
    label: row.label,
    median: median(row.ms),
    cold: row.ms[0],
    max: Math.max(...row.ms),
    bytes: row.bytes,
    status: row.status,
    note: row.note,
    error: row.errors[0],
  }));
}

function printPage(name, steps) {
  console.log(`\n${name}`);
  for (const s of steps) {
    const kb = s.bytes ? `${(s.bytes / 1024).toFixed(0)}KB` : '';
    const tail = [flag(s.median, s.error), s.error, s.note].filter(Boolean).join('  ');
    console.log(`  ${fmtMs(s.median).padStart(8)}  cold ${fmtMs(s.cold).padStart(7)}  ${kb.padStart(6)}  ${s.label}${tail ? `   ${tail}` : ''}`);
  }
}

// ── Compare ─────────────────────────────────────────────────────────────

async function compare(files) {
  const runs = await Promise.all(files.map(async (f) => JSON.parse(await readFile(f, 'utf8'))));
  const labels = runs.map((r) => r.label);
  console.log(`page / step`.padEnd(70) + labels.map((l) => l.padStart(10)).join('') + '   growth');
  const keys = [];
  const seen = new Set();
  for (const run of runs) for (const p of run.pages) for (const s of p.steps) {
    const key = `${p.name} :: ${s.label}`;
    if (!seen.has(key)) (seen.add(key), keys.push([p.name, s.label]));
  }
  for (const [page, label] of keys) {
    const cells = runs.map((r) => r.pages.find((p) => p.name === page)?.steps.find((s) => s.label === label));
    const ms = cells.map((c) => (c ? c.median : NaN));
    const first = ms.find(Number.isFinite);
    const last = [...ms].reverse().find(Number.isFinite);
    const growth = first > 0 && last >= 0 ? last / first : NaN;
    const error = cells.find((c) => c?.error)?.error;
    const mark = error ? ` ERROR ${error}` : last >= VERY_SLOW_MS ? ' VERY SLOW' : last >= SLOW_MS ? ' slow' : '';
    const name = `${page} :: ${label}`.slice(0, 69).padEnd(70);
    console.log(name + ms.map((m) => fmtMs(m).padStart(10)).join('') + `   ${Number.isFinite(growth) ? `x${growth.toFixed(1)}` : ''}${mark}`);
  }
}

// ── Main ────────────────────────────────────────────────────────────────

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.compare.length) return compare(opts.compare);

  const base = opts.base || process.env.BASE_URL || 'http://localhost:4000';
  const label = opts.label || 'run';
  const repeat = opts.repeat || 3;
  const params = JSON.parse(process.env.BENCH_PARAMS || '{}');
  const cookies = { admin: process.env.BENCH_ADMIN_COOKIE, player: process.env.BENCH_PLAYER_COOKIE, visitor: null };

  const pages = [];
  for (const file of opts.spec) {
    const mod = await import(path.resolve(file));
    pages.push(...mod.pages);
  }
  const selected = pages.filter((p) => !opts.only || p.path.includes(opts.only) || (p.name || '').includes(opts.only));

  console.log(`page bench "${label}" against ${base}: ${selected.length} pages, ${repeat} runs each (median shown)`);
  const out = { label, base, startedAt: new Date().toISOString(), repeat, pages: [] };
  const started = performance.now();

  for (const page of selected) {
    const name = page.name || page.path;
    const runs = [];
    for (let i = 0; i < repeat; i++) runs.push(await runPage(page, { base, params, cookies }));
    const steps = summarise(runs);
    out.pages.push({ name, path: page.path, as: page.as || 'visitor', steps });
    printPage(`${name}  [${page.as || 'visitor'}]`, steps);
  }

  const all = out.pages.flatMap((p) => p.steps.map((s) => ({ page: p.name, ...s })));
  const errors = all.filter((s) => s.error);
  const slow = all.filter((s) => !s.error && s.median >= SLOW_MS).sort((a, b) => b.median - a.median);

  console.log(`\n${all.length} steps in ${fmtMs(performance.now() - started)}; ${slow.length} slow (>= ${SLOW_MS}ms), ${errors.length} errors`);
  for (const s of slow.slice(0, 25)) console.log(`  ${fmtMs(s.median).padStart(8)}  ${s.page} :: ${s.label}`);
  for (const s of errors) console.log(`  ERROR  ${s.page} :: ${s.label}: ${s.error}`);

  const file = opts.out || path.resolve(path.dirname(new URL(import.meta.url).pathname), '..', 'results', 'pages', `${label}.json`);
  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(file, JSON.stringify(out, null, 2));
  console.log(`\nresult: ${file}`);
  process.exitCode = errors.length ? 1 : 0;
}

main().catch((e) => {
  console.error(e);
  process.exit(2);
});
