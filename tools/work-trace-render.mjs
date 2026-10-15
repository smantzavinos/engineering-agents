#!/usr/bin/env node
// Render Work Trace JSON files to static SVG with work-trace's own exporter (exportTimelineSvg),
// run in headless Chrome. https://github.com/smantzavinos/work-trace
//
// Usage:
//   node tools/work-trace-render.mjs --work-trace <checkout> [options] <trace.json> [...]
//     --out-dir DIR          default: next to each trace
//     --width PX             default 1600
//     --no-worktrees         hide worktree regions
//     --no-connectors        hide causal connectors
//     --tools / --model-calls  show call spans (when the trace has them)
//     --hide TYPE[,TYPE]     hide agent types (e.g. helper,oracle)
//
// The checkout needs `pnpm install` (its vite and Svelte plugin build the exporter bundle, cached
// under /tmp per checkout commit). Needs google-chrome on PATH or CHROME=/path/to/chrome.

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawn, execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const opts = { traces: [], width: 1600, showWorktrees: true, showConnectors: true, showTools: false, showModelCalls: false, hide: [] };
for (let i = 2; i < process.argv.length; i++) {
	const a = process.argv[i];
	const next = () => process.argv[++i];
	if (a === '--work-trace') opts.wt = path.resolve(next());
	else if (a === '--out-dir') opts.outDir = path.resolve(next());
	else if (a === '--width') opts.width = Number(next());
	else if (a === '--no-worktrees') opts.showWorktrees = false;
	else if (a === '--no-connectors') opts.showConnectors = false;
	else if (a === '--tools') opts.showTools = true;
	else if (a === '--model-calls') opts.showModelCalls = true;
	else if (a === '--hide') opts.hide.push(...next().split(','));
	else if (a.startsWith('-')) throw new Error(`Unknown option ${a}`);
	else opts.traces.push(path.resolve(a));
}
if (!opts.wt || !opts.traces.length) throw new Error('Need --work-trace <checkout> and at least one trace');

// ---------- exporter bundle ----------
const commit = execFileSync('git', ['-C', opts.wt, 'rev-parse', '--short', 'HEAD'], { encoding: 'utf8' }).trim();
const cache = path.join(os.tmpdir(), `work-trace-export-${commit}`);
const bundle = path.join(cache, 'export.iife.js');
if (!fs.existsSync(bundle)) {
	fs.mkdirSync(cache, { recursive: true });
	const entry = path.join(cache, 'entry.js');
	fs.writeFileSync(entry, `export { exportTimelineSvg } from ${JSON.stringify(path.join(opts.wt, 'src/lib/export/export-svg.ts'))};\n`);
	const nm = path.join(opts.wt, 'node_modules');
	const vite = await import(pathToFileURL(path.join(nm, 'vite/dist/node/index.js')).href);
	const { svelte } = await import(pathToFileURL(path.join(nm, '@sveltejs/vite-plugin-svelte/src/index.js')).href);
	await vite.build({
		root: opts.wt,
		configFile: false,
		logLevel: 'warn',
		plugins: [svelte({ compilerOptions: { runes: true }, configFile: false })],
		build: {
			outDir: cache,
			emptyOutDir: false,
			lib: { entry, name: 'WorkTraceExport', formats: ['iife'], fileName: () => 'export.iife.js' }
		}
	});
}

// ---------- headless Chrome ----------
const port = 9300 + Math.floor(Math.random() * 400);
const chrome = spawn(
	process.env.CHROME ?? 'google-chrome',
	['--headless=new', '--no-sandbox', '--disable-gpu', `--remote-debugging-port=${port}`, `--user-data-dir=${fs.mkdtempSync(path.join(os.tmpdir(), 'wtr-'))}`, 'about:blank'],
	{ stdio: 'ignore' }
);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ws;
let id = 0;
const pending = new Map();
const send = (method, params = {}) =>
	new Promise((resolve, reject) => {
		const i = ++id;
		pending.set(i, { resolve, reject });
		ws.send(JSON.stringify({ id: i, method, params }));
	});
const evaluate = async (expression) => {
	const r = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
	if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description ?? r.exceptionDetails.text);
	return r.result.value;
};
try {
	let url;
	for (let i = 0; i < 50 && !url; i++) {
		try {
			url = (await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find((t) => t.type === 'page')?.webSocketDebuggerUrl;
		} catch {
			/* not up yet */
		}
		if (!url) await sleep(200);
	}
	if (!url) throw new Error('Chrome did not start');
	ws = new WebSocket(url);
	await new Promise((r) => (ws.onopen = r));
	ws.onmessage = (m) => {
		const d = JSON.parse(m.data);
		const p = pending.get(d.id);
		if (!p) return;
		pending.delete(d.id);
		d.error ? p.reject(new Error(d.error.message)) : p.resolve(d.result);
	};
	await evaluate(fs.readFileSync(bundle, 'utf8'));
	for (const trace of opts.traces) {
		const options = {
			width: opts.width,
			showWorktrees: opts.showWorktrees,
			showConnectors: opts.showConnectors,
			showTools: opts.showTools,
			showModelCalls: opts.showModelCalls,
			hiddenAgentTypes: opts.hide
		};
		const svg = await evaluate(
			`WorkTraceExport.exportTimelineSvg(${fs.readFileSync(trace, 'utf8')}, ${JSON.stringify(options)})`
		);
		const out = path.join(opts.outDir ?? path.dirname(trace), `${path.basename(trace).replace(/(\.trace)?\.json$/, '')}.svg`);
		fs.mkdirSync(path.dirname(out), { recursive: true });
		fs.writeFileSync(out, svg);
		console.log(out);
	}
} finally {
	ws?.close();
	chrome.kill();
}
