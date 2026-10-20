#!/usr/bin/env node
// Build a Work Trace v3 JSON file (https://github.com/smantzavinos/work-trace) from a hand-written
// scenario: an illustrative execution, not a recorded one. Used for process diagrams.
//
// Usage:
//   node tools/scenario-trace.mjs <scenario.json> -o <out.trace.json> [--validate-with DIR]
//     --validate-with DIR   validate with a built work-trace checkout (DIR/dist/model/validate.js)
//
// Render the result with tools/work-trace-render.mjs.
//
// Scenario format (times in minutes):
//   {
//     "title": "...", "repository": "example-app", "startedAt": "ISO", "gapMin": 1,
//     "worktrees": [{ "id": "work", "label": "work branch", "kind": "main" }, ...],
//     "orchestrator": { "worktree": "work", "ref": "epic/example" },
//     "steps": [{
//       "id": "01.plan",            unique
//       "agent": "plan-author",     agent type (colour and legend)
//       "label": "plan",            bar label; "item" is prefixed when given
//       "item": "01",               optional work item (child)
//       "wt": "plan-1", "ref": "plan/01",   worktree and the branch it has checked out
//       "dur": 35,
//       "after": ["..."],           starts gapMin after the latest of these ends (default: at 0)
//       "at": 0,                    or an absolute start, used when later than "after"
//       "resume": "01.plan",        continues that step's session (mode resume)
//       "holdUntil": "g1.t1",       the worktree keeps "ref" until that step ends
//       "compact": true             the session self-compacts in its last 2 minutes
//     }],
//     "compactions": [{ "after": "01.cr2", "dur": 2 }]   orchestrator self_compact points
//   }
import fs from 'node:fs';
import path from 'node:path';

const args = {};
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
	const a = argv[i];
	if (a === '-o') args.out = argv[++i];
	else if (a === '--validate-with') args.validateWith = argv[++i];
	else if (!args.scenario) args.scenario = a;
	else throw new Error(`unexpected argument ${a}`);
}
if (!args.scenario || !args.out) {
	console.error('usage: scenario-trace.mjs <scenario.json> -o <out.trace.json> [--validate-with DIR]');
	process.exit(2);
}

const sc = JSON.parse(fs.readFileSync(args.scenario, 'utf8'));
const MIN = 60_000;
const gap = sc.gapMin ?? 1;
const steps = new Map(sc.steps.map((s) => [s.id, s]));
if (steps.size !== sc.steps.length) throw new Error('duplicate step id');
const worktreeIds = new Set(sc.worktrees.map((w) => w.id));

// Schedule: start = gap after the latest "after" end, or "at" if later.
const time = new Map();
function schedule(id, seen = new Set()) {
	if (time.has(id)) return time.get(id);
	const s = steps.get(id);
	if (!s) throw new Error(`unknown step ${id}`);
	if (seen.has(id)) throw new Error(`cycle at ${id}`);
	seen.add(id);
	if (!worktreeIds.has(s.wt)) throw new Error(`${id}: unknown worktree ${s.wt}`);
	let start = s.at ?? 0;
	for (const dep of s.after ?? []) start = Math.max(start, schedule(dep, seen).end + gap);
	const t = { start, end: start + s.dur };
	time.set(id, t);
	return t;
}
for (const s of sc.steps) schedule(s.id);
const endOf = (id) => {
	if (!time.has(id)) throw new Error(`unknown step ${id}`);
	return time.get(id).end;
};

const totalMin = Math.max(...[...time.values()].map((t) => t.end)) + gap;
const orchSpan = 'orchestrator-run1';
const ordered = [...sc.steps].sort((a, b) => time.get(a.id).start - time.get(b.id).start || a.id.localeCompare(b.id));

// Sessions and spans.
const agentSessions = [{ id: 'orchestrator', agentType: 'orchestrator', label: 'orchestrator' }];
const spans = [
	{
		id: orchSpan,
		kind: 'agent',
		worktreeId: sc.orchestrator.worktree,
		label: 'orchestrator',
		sessionId: 'orchestrator',
		mode: 'start',
		startMs: 0,
		endMs: totalMin * MIN,
		status: 'ok',
	},
];
const events = [];
const sessionOf = new Map(); // step id -> session id
const lastSpanOfSession = new Map();
for (const s of ordered) {
	const t = time.get(s.id);
	let sessionId;
	if (s.resume) {
		sessionId = sessionOf.get(s.resume);
		if (!sessionId) throw new Error(`${s.id}: resumes ${s.resume}, which has not started yet`);
	} else {
		sessionId = `s-${s.id}`;
		agentSessions.push({ id: sessionId, agentType: s.agent, label: s.agent, attributes: { item: s.item ?? null } });
	}
	sessionOf.set(s.id, sessionId);
	const span = {
		id: `sp-${s.id}`,
		kind: 'agent',
		parentId: orchSpan,
		worktreeId: s.wt,
		label: s.item ? `${s.item} ${s.label}` : s.label,
		sessionId,
		mode: s.resume ? 'resume' : 'start',
		startMs: t.start * MIN,
		endMs: t.end * MIN,
		status: 'ok',
		attributes: { agent: s.agent, phase: s.label, item: s.item ?? null, illustrative: true },
	};
	if (s.resume) span.resumesSpanId = lastSpanOfSession.get(sessionId);
	lastSpanOfSession.set(sessionId, span.id);
	spans.push(span);
	if (s.compact) {
		events.push({
			id: `c-${s.id}`,
			kind: 'compaction',
			sessionId,
			spanId: span.id,
			atMs: Math.max(t.start, t.end - 2) * MIN,
			endMs: t.end * MIN,
			trigger: 'manual',
			outcome: 'ok',
		});
	}
}
for (const c of sc.compactions ?? []) {
	const at = endOf(c.after) + gap;
	events.push({
		id: `c-orch-${c.after}`,
		kind: 'compaction',
		sessionId: 'orchestrator',
		spanId: orchSpan,
		atMs: at * MIN,
		endMs: (at + (c.dur ?? 2)) * MIN,
		trigger: 'manual',
		outcome: 'ok',
	});
}

// Checked-out branch per worktree: from the first step on a ref to the end of its last step (or its
// holdUntil step), cut short where the worktree switches to another ref.
const byWt = new Map();
const addUse = (wt, ref, start, end) => {
	if (!byWt.has(wt)) byWt.set(wt, []);
	byWt.get(wt).push({ ref, start, end });
};
addUse(sc.orchestrator.worktree, sc.orchestrator.ref, 0, totalMin);
for (const s of ordered) {
	const t = time.get(s.id);
	addUse(s.wt, s.ref, t.start, Math.max(t.end, s.holdUntil ? endOf(s.holdUntil) : 0));
}
const worktreeRefs = [];
for (const [wt, uses] of byWt) {
	uses.sort((a, b) => a.start - b.start);
	const intervals = [];
	for (const u of uses) {
		const cur = intervals.at(-1);
		if (cur && cur.ref === u.ref) cur.end = Math.max(cur.end, u.end);
		else {
			if (cur) cur.end = Math.min(cur.end, u.start);
			intervals.push({ ...u });
		}
	}
	for (const iv of intervals) {
		if (iv.end <= iv.start) continue;
		worktreeRefs.push({
			id: `ref-${worktreeRefs.length + 1}`,
			worktreeId: wt,
			startMs: iv.start * MIN,
			endMs: iv.end * MIN,
			ref: { kind: 'branch', name: iv.ref },
		});
	}
}

const trace = {
	schemaVersion: 3,
	trace: {
		id: `scenario-${path.basename(args.scenario, '.json')}`,
		title: sc.title,
		startedAt: sc.startedAt,
		observedUntilMs: totalMin * MIN,
	},
	repositories: [{ id: 'repo-1', label: sc.repository }],
	worktrees: sc.worktrees.map((w) => ({ id: w.id, repositoryId: 'repo-1', label: w.label ?? w.id, kind: w.kind ?? 'linked' })),
	worktreeRefs,
	agentSessions,
	spans,
	events,
};

if (args.validateWith) {
	const { validateTrace } = await import(path.resolve(args.validateWith, 'dist/model/validate.js'));
	const r = validateTrace(trace);
	if (!r.ok) {
		console.error(JSON.stringify(r.issues, null, 2));
		process.exit(1);
	}
}
fs.writeFileSync(args.out, JSON.stringify(trace, null, '\t') + '\n');
const h = (m) => `${Math.floor(m / 60)}h${String(m % 60).padStart(2, '0')}`;
console.log(`${args.out}: ${spans.length} spans, ${events.length} compactions, ${worktreeRefs.length} branch intervals, ${h(totalMin)} total`);
