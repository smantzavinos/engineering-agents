#!/usr/bin/env node
// Convert recorded pi sessions and pi-subagents async runs into a Work Trace v3 JSON file
// (https://github.com/smantzavinos/work-trace), for post-execution review of an orchestrated run.
//
// Usage:
//   node tools/pi-work-trace.mjs --session <root-session.jsonl> [--session ...] -o trace.json
//     [--runs-dir DIR]        pi-subagents async run records (default /tmp/pi-subagents-uid-<uid>/async-subagent-runs)
//     [--since ISO] [--until ISO]  clip the trace to a time window
//     [--calls]               also emit tool and model call spans (large)
//     [--anonymize]           replace paths, worktree names and branch names with generic labels
//     [--item-pattern RE]     regex whose group 1 names the work item in a child's task (default: NN_name child keys)
//     [--title TEXT]
//     [--validate-with DIR]   validate with a built work-trace checkout (DIR/dist/model/validate.js)
//
// Model:
//   - Each root session is an orchestrator agent session. Its runs are split at process restarts
//     (a system message after a pause), so a restart shows as a resumed run.
//   - Each async run step is an agent span. Steps that reuse a session file are resumes of that session.
//   - The parent of a run is the agent session that launched it (status.json sessionId).
//   - Each span's worktree is its cwd. Checked-out refs come from each worktree's HEAD reflog.
//   - Compactions come from session `compaction` entries (start taken from a preceding self-compact
//     `compacting` state when present).

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';

// ---------- arguments ----------
const args = { sessions: [], calls: false, anonymize: false };
for (let i = 2; i < process.argv.length; i++) {
	const a = process.argv[i];
	const next = () => process.argv[++i];
	if (a === '--session') args.sessions.push(path.resolve(next()));
	else if (a === '-o' || a === '--out') args.out = next();
	else if (a === '--runs-dir') args.runsDir = next();
	else if (a === '--since') args.since = Date.parse(next());
	else if (a === '--until') args.until = Date.parse(next());
	else if (a === '--calls') args.calls = true;
	else if (a === '--anonymize') args.anonymize = true;
	else if (a === '--item-pattern') args.itemPattern = next();
	else if (a === '--title') args.title = next();
	else if (a === '--validate-with') args.validateWith = next();
	else if (a === '-h' || a === '--help') {
		console.log(fs.readFileSync(new URL(import.meta.url)).toString().split('\n').slice(1, 20).join('\n'));
		process.exit(0);
	} else throw new Error(`Unknown argument: ${a}`);
}
if (!args.sessions.length || !args.out) throw new Error('Need at least one --session and -o');
const runsDir = args.runsDir ?? `/tmp/pi-subagents-uid-${process.getuid?.() ?? 1000}/async-subagent-runs`;
const itemRe = new RegExp(args.itemPattern ?? String.raw`\b(\d{2}[a-z]?\d?[a-z]?\d?[a-z]?)_[a-z][a-z0-9_]*`, 'i');

// ---------- helpers ----------
const ts = (v) => (typeof v === 'number' ? v : Date.parse(v));
const short = (s) => crypto.createHash('sha1').update(s).digest('hex').slice(0, 10);
function readJsonl(file) {
	if (!fs.existsSync(file)) return [];
	const out = [];
	for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
		if (!line.trim()) continue;
		try {
			out.push(JSON.parse(line));
		} catch {
			/* torn or partial line: skip */
		}
	}
	return out;
}
const textOf = (content) =>
	typeof content === 'string'
		? content
		: (content ?? []).map((c) => (c && typeof c.text === 'string' ? c.text : '')).join(' ');
function firstUserText(entries) {
	for (const e of entries) if (e.type === 'message' && e.message?.role === 'user') return textOf(e.message.content);
	return '';
}

// Phase of a child, from its agent and the skill wording at the start of its task.
// First matching rule for the agent wins; the last rule of each list is the fallback.
const B = String.raw`\*{0,2}`; // optional markdown bold around a mode word
const PHASES = {
	reviewer: [
		[new RegExp(`in ${B}plan${B} mode`, 'i'), (t) => (/refresh/i.test(t) ? 'refresh review' : 'plan review')],
		[/refresh/i, () => 'refresh review'],
		[new RegExp(`in ${B}epic${B} mode|epic close`, 'i'), () => 'epic review'],
		[/integration review/i, () => 'integration review'],
		[/./, () => 'code review']
	],
	implementer: [
		[/integrat/i, () => 'integration fix'],
		[new RegExp(`${B}fix${B} mode|reviving|owner-requested|bug fix`, 'i'), () => 'fix'],
		[/./, () => 'build']
	],
	'plan-author': [
		[/refresh/i, () => 'refresh'],
		[/reviving|revis|findings/i, () => 'plan revision'],
		[/./, () => 'plan']
	],
	helper: [
		[/^(task:\s*)?(errand[^.]{0,20}read-only|read-?only|readonly)|\bscout\b|reconnaissance/i, () => 'scout'],
		[/checkpoint/i, () => 'checkpoint'],
		[/\bT1\b.{0,40}integration|integration.{0,40}\bT1\b/i, () => 'integration gates'],
		[/\bT1\b|\bgates?\b|digest/i, () => 'gates'],
		[/tests?[- ]only|implement|docs only|sweep|migration|fix/i, () => 'build assist'],
		[/./, () => 'helper']
	],
	oracle: [[/./, () => 'oracle']],
	researcher: [[/./, () => 'research']]
};
function phaseOf(agent, task) {
	const head = task.slice(0, 400);
	for (const [re, f] of PHASES[agent] ?? []) if (re.test(head)) return f(head);
	return agent;
}
function itemOf(task) {
	const head = task.slice(0, 600);
	const m = itemRe.exec(head) ?? /\bchild\s*`?(\d{2}[a-z0-9]*)/i.exec(head) ?? /\b(\d{2}[a-z]\d?[a-z]?\d?)\b/.exec(head);
	if (m) return m[1];
	const c = /\bcheckpoint\s+(\d+)/i.exec(head);
	return c ? `C${c[1]}` : undefined;
}

// ---------- git context ----------
const repoByCommon = new Map();
const worktreeByPath = new Map();
function git(cwd, ...a) {
	try {
		return execFileSync('git', ['-C', cwd, ...a], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
	} catch {
		return undefined;
	}
}
function worktreeFor(cwd) {
	if (!cwd) return undefined;
	if (worktreeByPath.has(cwd)) return worktreeByPath.get(cwd);
	const top = git(cwd, 'rev-parse', '--show-toplevel') ?? cwd;
	if (worktreeByPath.has(top)) {
		worktreeByPath.set(cwd, worktreeByPath.get(top));
		return worktreeByPath.get(top);
	}
	const common = path.resolve(top, git(top, 'rev-parse', '--git-common-dir') ?? '.git');
	const gitDir = path.resolve(top, git(top, 'rev-parse', '--git-dir') ?? '.git');
	if (!repoByCommon.has(common))
		repoByCommon.set(common, { id: `repo-${repoByCommon.size + 1}`, label: path.basename(path.dirname(common)) });
	const wt = {
		id: `wt-${short(top)}`,
		repositoryId: repoByCommon.get(common).id,
		label: path.basename(top),
		path: top,
		kind: gitDir === common ? 'main' : 'linked'
	};
	worktreeByPath.set(cwd, wt);
	worktreeByPath.set(top, wt);
	return wt;
}
// Checkouts of HEAD as [{at, from, to}], oldest first.
function checkouts(wt) {
	const raw = git(wt.path, 'reflog', 'show', '--date=unix', '--format=%gd%x09%gs', 'HEAD') ?? '';
	const out = [];
	for (const line of raw.split('\n')) {
		const m = /HEAD@\{(\d+)\}\t(?:checkout|switch): moving from (\S+) to (\S+)/.exec(line);
		if (m) out.push({ at: Number(m[1]) * 1000, from: m[2], to: m[3] });
	}
	return out.reverse();
}
const asRef = (name) =>
	name === 'HEAD' ? undefined : /^[0-9a-f]{7,40}$/.test(name) ? { kind: 'detached', commitSha: name } : { kind: 'branch', name };

// ---------- sessions ----------
const agentSessions = new Map(); // id -> {id, agentType, label, attributes}
const sessionIdByFile = new Map(); // session file -> agent session id
const fileEntries = new Map(); // session file -> entries
const activations = []; // agent spans before origin shift: {id, sessionId, start, end, status, cwd, parentSessionId, attributes, label}

// Roots: split each orchestrator session at restarts.
for (const file of args.sessions) {
	const entries = readJsonl(file);
	const header = entries.find((e) => e.type === 'session');
	const sid = `orch-${(header?.id ?? short(file)).slice(0, 8)}`;
	sessionIdByFile.set(file, sid);
	fileEntries.set(file, entries);
	agentSessions.set(sid, { id: sid, agentType: 'orchestrator', label: 'orchestrator' });
	const cwd = header?.cwd;
	let run = null;
	let prevTs = null;
	let n = 0;
	for (const e of entries) {
		const t = e.timestamp ? ts(e.timestamp) : NaN;
		if (!Number.isFinite(t)) continue;
		const restart = e.type === 'message' && e.message?.role === 'system' && prevTs !== null && t - prevTs > 60_000;
		if (!run || restart) {
			if (run) activations.push(run);
			run = { id: `${sid}-run${++n}`, sessionId: sid, start: t, end: t, status: 'ok', cwd, label: 'orchestrator' };
		}
		run.end = Math.max(run.end, t);
		prevTs = t;
	}
	if (run) activations.push(run);
}

// Runs: include every run launched (transitively) from a root session.
const statuses = [];
if (fs.existsSync(runsDir))
	for (const d of fs.readdirSync(runsDir)) {
		try {
			statuses.push(JSON.parse(fs.readFileSync(path.join(runsDir, d, 'status.json'), 'utf8')));
		} catch {
			/* missing or partial status */
		}
	}
const included = new Set();
for (let changed = true; changed; ) {
	changed = false;
	for (const s of statuses) {
		if (included.has(s) || !sessionIdByFile.has(s.sessionId)) continue;
		included.add(s);
		changed = true;
		for (const step of s.steps ?? []) {
			const f = step.sessionFile ?? s.sessionFile;
			if (f && !sessionIdByFile.has(f)) {
				const m = /([0-9a-f-]{36})\/run-\d+\/session\.jsonl$/.exec(f);
				sessionIdByFile.set(f, `s-${(m ? m[1] : short(f)).slice(0, 8)}`);
			}
		}
	}
}
// Revived runs ("reviving a previous subagent conversation") continue the original session.
function launchText(file, start) {
	const users = (fileEntries.get(file) ?? []).filter((e) => e.type === 'message' && e.message?.role === 'user');
	const e = users.find((u) => ts(u.timestamp) >= start - 5000) ?? users[0];
	return e ? textOf(e.message.content) : '';
}
const original = new Map(); // revived session file -> original session file
for (const s of included)
	for (const step of s.steps ?? []) {
		const file = step.sessionFile ?? s.sessionFile;
		if (!fileEntries.has(file)) fileEntries.set(file, readJsonl(file));
		const m = /reviving a previous subagent conversation[\s\S]{0,400}?Original session file:\s*(\S+)/i.exec(launchText(file, ts(step.startedAt ?? s.startedAt)));
		if (m && m[1] !== file) original.set(file, m[1]);
	}
for (const file of original.keys()) {
	let root = file;
	for (let i = 0; i < 50 && original.has(root); i++) root = original.get(root);
	if (sessionIdByFile.has(root)) sessionIdByFile.set(file, sessionIdByFile.get(root));
}

const STATUS = { complete: 'ok', failed: 'error', paused: 'cancelled', stopped: 'cancelled', cancelled: 'cancelled' };
for (const s of included) {
	const parentSessionId = sessionIdByFile.get(s.sessionId);
	(s.steps ?? []).forEach((step, i) => {
		const file = step.sessionFile ?? s.sessionFile;
		const sid = sessionIdByFile.get(file);
		const agent = step.agent ?? 'agent';
		const start = ts(step.startedAt ?? s.startedAt);
		const text = launchText(file, start);
		const revived = /reviving a previous subagent conversation/i.test(text.slice(0, 200));
		const ask = revived ? text.slice(text.search(/Follow-up:/i) + 1 || 0) : text;
		let phase = phaseOf(agent, ask);
		if (revived && agent === 'plan-author') phase = /refresh/i.test(ask.slice(0, 400)) ? 'refresh' : 'plan revision';
		if (revived && agent === 'implementer') phase = /integrat/i.test(ask.slice(0, 400)) ? 'integration fix' : 'fix';
		const item = itemOf(ask) ?? itemOf(firstUserText(fileEntries.get(file)));
		if (!agentSessions.has(sid)) agentSessions.set(sid, { id: sid, agentType: agent, first: Infinity });
		const sess = agentSessions.get(sid);
		if (start < sess.first) Object.assign(sess, { first: start, label: [item, phase].filter(Boolean).join(' · '), attributes: { item: item ?? null } });
		let end = ts(step.endedAt ?? s.endedAt ?? NaN);
		const state = step.status ?? s.state;
		let status = STATUS[state] ?? (state === 'running' ? 'running' : 'ok');
		if (status === 'ok' && step.exitCode && step.exitCode !== 0) status = 'error';
		if (status !== 'running' && !Number.isFinite(end)) end = ts(s.lastUpdate ?? s.lastActivityAt ?? start + 1);
		activations.push({
			id: `run-${s.runId.slice(0, 8)}${(s.steps?.length ?? 1) > 1 ? `-${i}` : ''}`,
			sessionId: sid,
			parentSessionId,
			start,
			end: status === 'running' ? undefined : end,
			status,
			cwd: s.cwd,
			label: [item, phase].filter(Boolean).join(' · ') || agent,
			attributes: {
				agent,
				model: step.model ?? null,
				phase,
				item: item ?? null,
				runId: s.runId,
				revived,
				mode: s.mode ?? null,
				turns: step.turnCount ?? s.turnCount ?? null,
				tools: step.toolCount ?? s.toolCount ?? null,
				tokens: step.tokens?.total ?? s.totalTokens?.total ?? null,
				exitCode: step.exitCode ?? null
			}
		});
	});
}

// ---------- window, continuity, parents ----------
const lo = args.since ?? -Infinity;
const hi = args.until ?? Infinity;
let spans = activations
	.filter((a) => a.start <= hi && (a.end ?? Infinity) >= lo)
	.map((a) => {
		const c = { ...a, start: Math.max(a.start, lo) };
		if (c.end !== undefined && c.end > hi) c.end = hi;
		if (c.end === undefined && Number.isFinite(hi)) c.end = hi;
		if (c.end !== undefined && c.end <= c.start) c.end = c.start + 1;
		return c;
	});
// Session continuity: chronological runs of one session; overlapping runs become separate sessions.
const bySession = new Map();
for (const s of spans.sort((a, b) => a.start - b.start || a.id.localeCompare(b.id))) {
	const list = bySession.get(s.sessionId) ?? [];
	const prev = list.at(-1);
	if (prev && (prev.end === undefined || prev.end > s.start)) {
		const base = agentSessions.get(s.sessionId);
		const nid = `${s.sessionId}-${s.id}`;
		agentSessions.set(nid, { ...base, id: nid });
		s.sessionId = nid;
		bySession.set(nid, [s]);
		continue;
	}
	list.push(s);
	bySession.set(s.sessionId, list);
}
for (const list of bySession.values())
	list.forEach((s, i) => {
		s.mode = i === 0 ? 'start' : 'resume';
		if (i > 0) s.resumesSpanId = list[i - 1].id;
	});
const activeRun = (sid, t) => (bySession.get(sid) ?? []).find((r) => r.start <= t && t <= (r.end ?? Infinity));
const rootRuns = spans.filter((s) => !s.parentSessionId);
for (const s of spans) {
	if (!s.parentSessionId) continue;
	let p = activeRun(s.parentSessionId, s.start) ?? rootRuns.find((r) => r.start <= s.start && s.start <= (r.end ?? Infinity));
	if (!p && s.start === lo) {
		// Clipped at the window start before its launcher's next run began: start it with that run.
		p = (bySession.get(s.parentSessionId) ?? []).find((r) => r.start > s.start && (s.end === undefined || r.start < s.end));
		if (p) s.start = p.start;
	}
	if (p && p !== s) s.parentId = p.id;
}

// ---------- calls ----------
// A revived session file may repeat its original's entries; count each (session, entry) once.
const seen = new Set();
const once = (sid, id) => !seen.has(`${sid}|${id}`) && seen.add(`${sid}|${id}`);
const calls = [];
if (args.calls)
	for (const [file, entries] of fileEntries) {
		const sid = sessionIdByFile.get(file);
		let prev = null;
		const open = new Map();
		for (const e of entries) {
			const t = e.timestamp ? ts(e.timestamp) : NaN;
			if (!Number.isFinite(t) || e.type !== 'message' || !once(sid, e.id)) continue;
			const m = e.message;
			if (m.role === 'assistant') {
				const run = activeRun(sid, prev ?? t);
				if (run && prev !== null && t > prev)
					calls.push({ id: `m-${short(sid + e.id)}`, kind: 'model', parentId: run.id, label: m.model ?? 'model', startMs: prev, endMs: t, status: m.stopReason === 'error' ? 'error' : 'ok' });
				for (const b of m.content ?? []) if (b.type === 'toolCall') open.set(b.id, { name: b.name, t, run: activeRun(sid, t) });
			} else if (m.role === 'toolResult' && open.has(m.toolCallId)) {
				const c = open.get(m.toolCallId);
				open.delete(m.toolCallId);
				if (c.run)
					calls.push({ id: `t-${short(sid + m.toolCallId)}`, kind: 'tool', parentId: c.run.id, label: c.name, startMs: c.t, endMs: Math.max(t, c.t + 1), status: m.isError ? 'error' : 'ok' });
			}
			prev = t;
		}
	}

// ---------- compactions ----------
const events = [];
for (const [file, entries] of fileEntries) {
	const sid = sessionIdByFile.get(file);
	let compactingAt = null;
	for (const e of entries) {
		if (e.type === 'custom' && e.customType === 'self-compact:state' && e.data?.phase === 'compacting') compactingAt = ts(e.timestamp);
		if (e.type !== 'compaction' || !once(sid, e.id)) continue;
		const end = ts(e.timestamp);
		const at = compactingAt !== null && end - compactingAt < 10 * 60_000 ? compactingAt : end;
		compactingAt = null;
		if (at < lo || at > hi) continue;
		const run = activeRun(sid, at);
		events.push({
			id: `c-${short(sid + e.id)}`,
			kind: 'compaction',
			sessionId: sid,
			...(run && (run.end === undefined || end <= run.end) ? { spanId: run.id } : {}),
			atMs: at,
			...(end > at ? { endMs: end } : {}),
			trigger: e.fromHook ? 'automatic' : 'manual',
			outcome: 'ok',
			...(Number.isInteger(e.tokensBefore) ? { tokensBefore: e.tokensBefore } : {}),
			attributes: { source: e.fromHook ? 'hook' : 'pi' }
		});
	}
}

// ---------- worktrees and refs ----------
for (const s of spans) s.wt = worktreeFor(s.cwd);
const usedWts = [...new Set(spans.map((s) => s.wt).filter(Boolean))];
const allTimes = [...spans.flatMap((s) => [s.start, s.end ?? s.start]), ...calls.flatMap((c) => [c.startMs, c.endMs])];
const origin = Math.min(...spans.map((s) => s.start));
const until = Math.max(...allTimes, ...events.map((e) => e.endMs ?? e.atMs));
const refs = [];
for (const wt of usedWts) {
	const moves = checkouts(wt);
	let cur = [...moves].reverse().find((m) => m.at <= origin)?.to ?? moves.find((m) => m.at > origin)?.from;
	let from = origin;
	const push = (to) => {
		const ref = cur && asRef(cur);
		if (ref && to > from) refs.push({ id: `ref-${refs.length + 1}`, worktreeId: wt.id, startMs: from, endMs: to, ref });
	};
	for (const m of moves.filter((m) => m.at > origin && m.at < until)) {
		push(m.at);
		cur = m.to;
		from = m.at;
	}
	push(until);
}

// ---------- anonymize ----------
if (args.anonymize) {
	const names = new Map();
	const anonBranch = (name) => {
		const m = /^([a-z]+)\/(.+)$/.exec(name);
		const key = m && itemOf(m[2]);
		if (m && key) return `${m[1]}/${key}`;
		if (['main', 'master'].includes(name)) return name;
		if (!names.has(name)) names.set(name, `branch-${names.size + 1}`);
		return names.get(name);
	};
	for (const r of refs) if (r.ref.kind === 'branch') r.ref.name = anonBranch(r.ref.name);
	usedWts.forEach((wt, i) => {
		wt.label = wt.kind === 'main' ? 'main checkout' : `worktree ${i + 1}`;
		delete wt.path;
	});
	[...repoByCommon.values()].forEach((r, i) => (r.label = `repository ${i + 1}`));
}

// ---------- emit ----------
const rel = (t) => Math.round(t - origin);
const trace = {
	schemaVersion: 3,
	trace: {
		id: `pi-${short(args.sessions.join('|') + lo + hi)}`,
		...(args.title ? { title: args.title } : {}),
		startedAt: new Date(origin).toISOString(),
		observedUntilMs: rel(until)
	},
	repositories: [...new Set(usedWts.map((w) => w.repositoryId))].map((id) => [...repoByCommon.values()].find((r) => r.id === id)),
	worktrees: usedWts.map(({ id, repositoryId, label, path: p, kind }) => ({ id, repositoryId, label, ...(p ? { path: p } : {}), kind })),
	worktreeRefs: refs.map((r) => ({ ...r, startMs: rel(r.startMs), endMs: rel(r.endMs) })).filter((r) => r.endMs > r.startMs),
	agentSessions: [...agentSessions.values()]
		.filter((s) => bySession.has(s.id))
		.map(({ id, agentType, label, attributes }) => ({ id, agentType, ...(label ? { label } : {}), ...(attributes ? { attributes } : {}) })),
	spans: [
		...spans.map((s) => ({
			id: s.id,
			kind: 'agent',
			...(s.parentId ? { parentId: s.parentId } : {}),
			...(s.wt ? { worktreeId: s.wt.id } : {}),
			label: s.label,
			sessionId: s.sessionId,
			mode: s.mode,
			...(s.resumesSpanId ? { resumesSpanId: s.resumesSpanId } : {}),
			startMs: rel(s.start),
			...(s.status === 'running' ? {} : { endMs: rel(s.end) }),
			status: s.status,
			...(s.attributes ? { attributes: s.attributes } : {})
		})),
		...calls.map((c) => ({ ...c, startMs: rel(c.startMs), endMs: rel(c.endMs) }))
	],
	events: events.map((e) => ({ ...e, atMs: rel(e.atMs), ...(e.endMs ? { endMs: rel(e.endMs) } : {}) }))
};
// Rounding can collapse sub-millisecond ranges; keep ends strictly after starts.
for (const x of [...trace.spans, ...trace.worktreeRefs]) if (x.endMs !== undefined && x.endMs <= x.startMs) x.endMs = x.startMs + 1;
for (const e of trace.events) if (e.endMs !== undefined && e.endMs <= e.atMs) delete e.endMs;

fs.mkdirSync(path.dirname(path.resolve(args.out)), { recursive: true });
fs.writeFileSync(args.out, JSON.stringify(trace, null, 1));
const agents = trace.spans.filter((s) => s.kind === 'agent').length;
console.log(`${args.out}: ${agents} agent spans, ${trace.spans.length - agents} calls, ${trace.events.length} compactions, ${trace.worktrees.length} worktrees`);

if (args.validateWith) {
	const { validateTrace } = await import(path.resolve(args.validateWith, 'dist/model/validate.js'));
	const r = validateTrace(trace);
	if (!r.ok) {
		console.error(r.issues.slice(0, 20).map((i) => `${i.path}: ${i.message}`).join('\n'));
		process.exit(1);
	}
	console.log('valid');
}
