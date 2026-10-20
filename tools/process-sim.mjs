#!/usr/bin/env node
// Simulate an epic under the frontier pipeline's execution rules (skills/orchestrate) and write a
// scenario for tools/scenario-trace.mjs. Illustrative: durations come from the config, the
// scheduling from the rules below. Used to compare process variants on the same epic.
//
// Usage: node tools/process-sim.mjs <epic.json> -o <scenario.json>
//
// Rules modelled:
// - Planning: up to `planningWorktrees`; a child's plan loop starts once every child it depends on
//   has started implementing, lowest-numbered first. A `splitFrom` child plans after its parent's
//   sizing step. The plan branch merges at approval (doesn't move the work branch for plain merges).
// - Units (a group, or a child in no group) start when every member's plan is approved, every
//   dependency is integrated, and a pool worktree is free per member (at most `maxLanes` running),
//   in child-number order: a waiting unit holds back later ones.
// - Lane: scout; refresh and refresh review when the scout finds a relevant change; implement (T1
//   inside); code review; fixes and review 2 (fix range) when pass 1 asks for changes.
//   variant.codePass2 "conditional": pass 2 only for `design` majors.
//   variant.reviewOnCommit: implement in two parts, an early review of part 1 while part 2 is built,
//   then T1 by a helper alongside the final review.
//   variant.childOrchestrator: a child orchestrator session owns the plan loop and the lane, and is
//   the parent of their calls (resumed at Start).
// - Integration, once per unit when every member is approved: a group of one merges plainly if the
//   work branch moved only by plan merges since its base; otherwise integration T1 (and for a group,
//   conflict resolution by the member's implementer and an integration review after a conflict), in
//   the checkpoint worktree if free, else a free pool worktree.
// - Checkpoints: once their child and its dependencies are integrated, in order, in the checkpoint
//   worktree; merging one moves the work branch.
// - Epic close: epic-diff review, fixes, final checkpoint; variant.finalParallel runs the final
//   checkpoint alongside the review, then T1 for the fixes.
import fs from 'node:fs';

const argv = process.argv.slice(2);
const cfgPath = argv[0];
const outPath = argv[argv.indexOf('-o') + 1];
if (!cfgPath || argv.indexOf('-o') < 0) {
	console.error('usage: process-sim.mjs <epic.json> -o <scenario.json>');
	process.exit(2);
}
const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
const D = cfg.durations;
const V = cfg.variant ?? {};
const GAP = cfg.gapMin ?? 1;
const kids = cfg.children;
const byId = new Map(kids.map((c) => [c.id, c]));
const idx = new Map(kids.map((c, i) => [c.id, i]));
const lanesKids = kids.filter((c) => !c.sizing);
const groupOf = new Map();
for (const g of cfg.groups ?? []) for (const m of g.members) groupOf.set(m, g);
const units = [];
for (const c of lanesKids) {
	const g = groupOf.get(c.id);
	if (g) {
		if (!units.some((u) => u.id === g.id)) units.push({ id: g.id, label: g.label, members: g.members.map((m) => byId.get(m)) });
	} else units.push({ id: c.id, members: [c], single: true });
}
const unitOf = new Map();
for (const u of units) for (const m of u.members) unitOf.set(m.id, u);

// Resources.
const wt = (name) => ({ name, heldBy: null, freeAt: -Infinity });
const planning = Array.from({ length: cfg.planningWorktrees ?? 2 }, (_, i) => wt(`plan-${i + 1}`));
const pool = Array.from({ length: cfg.maxLanes }, (_, i) => wt(`pool-${String.fromCharCode(97 + i)}`));
const checkpointWt = wt('checkpoint');
const free = (w, t) => w.heldBy === null && w.freeAt + GAP <= t;
const take = (w, who) => (w.heldBy = who);
const release = (w, t) => {
	w.heldBy = null;
	w.freeAt = t;
};

// Engine.
const jobs = [];
const pending = [];
const running = [];
const workMoves = [];
const refs = [];
const compactions = [];
const childOrch = new Map(); // child id -> {plan:[start,end,wt], lane:[start,end,wt]}
let seq = 0;
function add(job) {
	job.seq = seq++;
	job.deps ??= [];
	pending.push(job);
	return job;
}
const doneAt = (id) => jobs.find((j) => j.id === id)?.end;
const isDone = (id, t) => {
	const e = doneAt(id);
	return e !== undefined && e + GAP <= t;
};

const state = new Map(kids.map((c) => [c.id, { implStarted: false, approved: null, codeApproved: null, integrated: null }]));
const st = (id) => state.get(id);

// Planning.
function planEligible(c) {
	if (c.splitFrom && st(c.splitFrom).approved === null) return false;
	return (c.deps ?? []).every((d) => st(d).implStarted);
}
const planStepsLeft = new Map();
for (const c of kids) {
	if (c.splitFrom) continue; // planned after its parent's sizing step
	queuePlan(c);
}
function queuePlan(c) {
	const steps = c.sizing
		? [{ agent: 'plan-author', label: 'sizing: proposes split', dur: D.sizing }]
		: [
				{ agent: 'plan-author', label: 'plan', dur: D.plan, compact: true },
				{ agent: 'reviewer', label: c.planPass2 ? 'plan review 1' : c.planFix ? 'plan review 1' : 'plan review 1 (approved)', dur: D.planReview, kind: 'review' },
				...(c.planFix || c.planPass2 ? [{ agent: 'plan-author', label: c.planPass2 ? 'plan fixes' : 'plan fixes (no pass 2)', dur: D.planFix, kind: 'fixes', resume: 0 }] : []),
				...(c.planPass2 ? [{ agent: 'reviewer', label: 'plan review 2', dur: D.planReview2, kind: 'review' }] : []),
			];
	let prev = null;
	steps.forEach((s, i) => {
		const id = `${c.id}.p${i}`;
		const job = add({
			id,
			item: c.id,
			agent: s.agent,
			label: s.label,
			dur: s.dur,
			compact: s.compact,
			kind: s.kind,
			from: prev ? [prev] : c.splitFrom ? [`${c.splitFrom}.p0`] : [],
			fromKind: !prev && c.splitFrom ? 'split' : undefined,
			deps: prev ? [prev] : [],
			resume: s.resume !== undefined ? `${c.id}.p${s.resume}` : undefined,
			wt: () => st(c.id).planWt.name,
			ref: `plan/${c.id}`,
			at: i === 0 && V.childOrchestrator ? GAP : undefined,
			parentOf: 'plan',
			gate:
				i === 0
					? (t) => planEligible(c) && planning.some((w) => free(w, t)) && lowestWaitingPlan(t) === c.id
					: undefined,
			onStart: i === 0 ? (t) => {
				const w = planning.find((x) => free(x, t));
				take(w, c.id);
				st(c.id).planWt = w;
				st(c.id).planStart = t;
			} : undefined,
			onEnd: i === steps.length - 1 ? (t) => {
				const w = st(c.id).planWt;
				release(w, t);
				st(c.id).approved = t;
				refs.push({ wt: w.name, ref: `plan/${c.id}`, from: st(c.id).planStart - (V.childOrchestrator ? 1 : 0), to: t + (V.childOrchestrator ? 1 : 0) });
				if (V.childOrchestrator) childOrch.set(c.id, { ...(childOrch.get(c.id) ?? {}), plan: [st(c.id).planStart - 1, t, w.name] });
				if (c.sizing) for (const k of kids.filter((k) => k.splitFrom === c.id)) queuePlan(k);
			} : undefined,
		});
		prev = id;
	});
}
function lowestWaitingPlan(t) {
	const waiting = pending.filter((j) => j.parentOf === 'plan' && j.id.endsWith('.p0') && planEligible(byId.get(j.item)));
	waiting.sort((a, b) => idx.get(a.item) - idx.get(b.item));
	return waiting[0]?.item;
}

// Units.
const started = new Set();
function unitReady(u) {
	return u.members.every((m) => st(m.id).approved !== null && (m.deps ?? []).every((d) => st(d).integrated !== null && st(d).integrated + GAP <= Infinity));
}
const runningLanes = () => lanesKids.filter((c) => st(c.id).laneWt && st(c.id).integrated === null).length;
function tryStartUnits(t) {
	const ready = units.filter((u) => !started.has(u.id) && unitReady(u)).sort((a, b) => idx.get(a.members[0].id) - idx.get(b.members[0].id));
	for (const u of ready) {
		const freeWts = pool.filter((w) => free(w, t));
		if (freeWts.length < u.members.length || runningLanes() + u.members.length > cfg.maxLanes) return;
		started.add(u.id);
		u.base = t;
		u.members.forEach((m, i) => startLane(m, freeWts[i], t));
	}
}
function startLane(c, w, t) {
	take(w, c.id);
	const s = st(c.id);
	s.laneWt = w;
	s.base = t;
	const at = t + (V.childOrchestrator ? GAP : 0);
	const L = (o) => add({ item: c.id, wt: w.name, ref: `lane/${c.id}`, parentOf: 'lane', ...o });
	const pass2 = c.codeFix && (V.codePass2 !== 'conditional' || c.fixKind === 'design');
	const lastPlan = [...jobs, ...pending].filter((j) => j.item === c.id && j.parentOf === 'plan').at(-1).id;
	let prev = L({ id: `${c.id}.scout`, agent: 'helper', label: c.scoutRelevant ? 'scout: relevant' : 'scout', dur: D.scout, at, from: [lastPlan], kind: 'start' }).id;
	if (c.scoutRelevant) {
		prev = L({ id: `${c.id}.refresh`, agent: 'plan-author', label: 'refresh', dur: D.refresh, deps: [prev], from: [prev], kind: 'refresh' }).id;
		prev = L({ id: `${c.id}.rr`, agent: 'reviewer', label: 'refresh review', dur: D.refreshReview, deps: [prev], from: [prev], kind: 'review' }).id;
	}
	let reviewed; // ids the fix step acts on
	let tail; // ids that must finish before approval / fixes
	const implId = `${c.id}.impl`;
	if (V.reviewOnCommit) {
		const body = c.build - D.t1;
		const a = L({ id: implId, agent: 'implementer', label: 'implement (part 1)', dur: Math.round(body * 0.6), deps: [prev], from: [prev], kind: 'build', onStart: () => (s.implStarted = true) }).id;
		const early = L({ id: `${c.id}.early`, agent: 'reviewer', label: 'early review (part 1)', dur: Math.round(D.codeReview * 0.6), deps: [a], from: [a], kind: 'review' }).id;
		const b = L({ id: `${c.id}.impl2`, agent: 'implementer', label: 'implement (part 2)', dur: body - Math.round(body * 0.6), deps: [a], resume: implId, compact: true }).id;
		const t1 = L({ id: `${c.id}.t1`, agent: 'helper', label: 'T1', dur: D.t1, deps: [b], from: [b], kind: 'T1' }).id;
		const fin = L({ id: `${c.id}.cr1`, agent: 'reviewer', label: c.codeFix ? 'code review (rest)' : 'code review (rest, approved)', dur: Math.round(D.codeReview * 0.5), deps: [b, early], from: [b], kind: 'review' }).id;
		reviewed = [early, fin];
		tail = [t1, fin];
	} else {
		const im = L({ id: implId, agent: 'implementer', label: 'implement + T1', dur: c.build, deps: [prev], from: [prev], kind: 'build', compact: true, onStart: () => (s.implStarted = true) }).id;
		const cr = L({ id: `${c.id}.cr1`, agent: 'reviewer', label: c.codeFix ? 'code review 1' : 'code review 1 (approved)', dur: D.codeReview, deps: [im], from: [im], kind: 'review' }).id;
		reviewed = [cr];
		tail = [cr];
	}
	if (c.codeFix) {
		const fx = L({ id: `${c.id}.fix1`, agent: 'implementer', label: pass2 ? 'fixes' : 'fixes (no pass 2)', dur: D.fix, deps: tail, from: reviewed, kind: 'fixes', resume: implId }).id;
		tail = [fx];
		if (pass2) tail = [L({ id: `${c.id}.cr2`, agent: 'reviewer', label: 'review 2 (fix range)', dur: D.codeReview2, deps: [fx], from: [fx], kind: 'review' }).id];
	}
	s.laneTail = tail;
	// approval when the tail finishes
	add({ id: `${c.id}.approved`, marker: true, deps: tail, dur: 0, onEnd: (t2) => codeApproved(c, t2 - GAP) });
}
function codeApproved(c, t) {
	const s = st(c.id);
	s.codeApproved = t;
	if (V.childOrchestrator) {
		const e = Math.max(...s.laneTail.map(doneAt));
		childOrch.set(c.id, { ...childOrch.get(c.id), lane: [Math.max(s.base, childOrch.get(c.id).plan[1]), e + 1, s.laneWt.name] });
	}
	const u = unitOf.get(c.id);
	if (u.members.every((m) => st(m.id).codeApproved !== null)) integrate(u, t);
}

// Integration.
const integrationWt = (t) => (free(checkpointWt, t) && !checkpointBusy() ? checkpointWt : pool.find((w) => free(w, t)));
const checkpointBusy = () => checkpointWt.heldBy !== null;
function integrate(u, t) {
	const lastIds = u.members.flatMap((m) => st(m.id).laneTail);
	if (u.single && !workMoves.some((x) => x > u.base)) {
		finishIntegration(u, t + GAP, lastIds.at(-1));
		return;
	}
	let iw;
	const conflictMember = u.members.find((m) => m.conflict);
	const name = u.single ? u.members[0].id : u.id;
	const item = u.single ? u.members[0].id : u.id;
	const label = u.single ? 'integration T1' : `group T1 (${u.members.map((m) => m.id).join(', ')})`;
	let first;
	const gate = (tt) => !!integrationWt(tt);
	const onStart = (tt) => {
		iw = integrationWt(tt);
		take(iw, `integration/${name}`);
		u.intStart = tt;
	};
	let prev;
	if (conflictMember) {
		const m = conflictMember;
		first = add({ id: `${u.id}.conflict`, item, agent: 'implementer', label: 'resolve integration conflict', dur: D.conflict, wt: m === undefined ? null : st(m.id).laneWt.name, ref: `lane/${m.id}`, resume: `${m.id}.impl`, from: st(m.id).laneTail, kind: 'conflict', gate, onStart });
		prev = first.id;
	}
	const t1 = add({ id: `${u.id}.it1`, item, agent: 'helper', label, dur: u.single ? D.singleT1 : D.groupT1, wt: () => iw.name, ref: `integration/${name}`, deps: prev ? [prev] : [], from: prev ? [prev, ...lastIds.filter((x) => !st(conflictMember.id).laneTail.includes(x))] : lastIds, kind: 'merge', gate: prev ? undefined : gate, onStart: prev ? undefined : onStart });
	let last = t1;
	if (conflictMember) last = add({ id: `${u.id}.irev`, item, agent: 'reviewer', label: 'integration review', dur: D.intReview, wt: () => iw.name, ref: `integration/${name}`, deps: [t1.id], from: [t1.id], kind: 'review' });
	last.onEnd = (tt) => {
		release(iw, tt);
		refs.push({ wt: iw.name, ref: `integration/${name}`, from: u.intStart, to: tt });
		finishIntegration(u, tt, last.id);
	};
}
function finishIntegration(u, t, afterId) {
	for (const m of u.members) {
		st(m.id).integrated = t;
		release(st(m.id).laneWt, t);
		refs.push({ wt: st(m.id).laneWt.name, ref: `lane/${m.id}`, from: st(m.id).base - (V.childOrchestrator ? 1 : 0), to: t });
	}
	workMoves.push(t);
	compactions.push({ after: afterId });
}

// Checkpoints.
let prevCheckpoint = null;
add({
	id: 'base', item: 'baseline', agent: 'helper', label: 'baseline full gates', dur: D.gates, wt: 'checkpoint', ref: 'checkpoint/baseline', at: 0,
	onStart: () => take(checkpointWt, 'baseline'),
	onEnd: (t) => { release(checkpointWt, t); refs.push({ wt: 'checkpoint', ref: 'checkpoint/baseline', from: 0, to: t }); },
});
for (const cp of cfg.checkpoints ?? []) {
	const after = byId.get(cp.after);
	const need = [after.id, ...(after.deps ?? [])];
	const id = `cp-${cp.after}`;
	const prior = prevCheckpoint;
	add({
		id, item: id, agent: 'helper', label: `checkpoint after ${cp.after}: full gates`, dur: D.gates, wt: 'checkpoint', ref: `checkpoint/${cp.after}`,
		deps: prior ? [prior] : [],
		gate: (t) => need.every((n) => st(n).integrated !== null && st(n).integrated <= t) && free(checkpointWt, t),
		onStart: (t) => take(checkpointWt, id),
		onEnd: (t) => { release(checkpointWt, t); workMoves.push(t); refs.push({ wt: 'checkpoint', ref: `checkpoint/${cp.after}`, from: doneAt(id) - D.gates, to: t }); },
	});
	prevCheckpoint = id;
}

// Epic close.
const allIntegrated = (t) => lanesKids.every((c) => st(c.id).integrated !== null && st(c.id).integrated <= t);
const lastLaneTail = () => lanesKids.flatMap((c) => st(c.id).laneTail ?? []).sort((a, b) => doneAt(b) - doneAt(a))[0];
{
	const closeGate = (t) => allIntegrated(t) && (!prevCheckpoint || doneAt(prevCheckpoint) !== undefined);
	const gatesJob = { id: 'close.gates', item: 'close', agent: 'helper', label: 'final checkpoint: full gates', dur: D.gates, wt: 'checkpoint', ref: 'checkpoint/close',
		onStart: (t) => take(checkpointWt, 'close'), onEnd: (t) => { release(checkpointWt, t); refs.push({ wt: 'checkpoint', ref: 'checkpoint/close', from: t - D.gates, to: t }); } };
	if (V.finalParallel) {
		add({ id: 'close.rev', item: 'close', agent: 'reviewer', label: 'epic-diff review', dur: D.epicReview, wt: 'work', ref: cfg.workBranch, gate: closeGate, fromLast: true, kind: 'epic review' });
		add({ ...gatesJob, gate: (t) => closeGate(t) && free(checkpointWt, t), fromLast: true, kind: 'checkpoint' });
		add({ id: 'close.fix', item: 'close', agent: 'implementer', label: 'epic-close fixes', dur: D.epicFix, wt: 'work', ref: cfg.workBranch, deps: ['close.rev'], from: ['close.rev'], kind: 'fixes' });
		add({ id: 'close.t1', item: 'close', agent: 'helper', label: 'T1 for the fixes', dur: D.epicT1, wt: 'work', ref: cfg.workBranch, deps: ['close.fix'], from: ['close.fix'], kind: 'T1' });
	} else {
		add({ id: 'close.rev', item: 'close', agent: 'reviewer', label: 'epic-diff review', dur: D.epicReview, wt: 'work', ref: cfg.workBranch, gate: closeGate, fromLast: true, kind: 'epic review' });
		add({ id: 'close.fix', item: 'close', agent: 'implementer', label: 'epic-close fixes + T1', dur: D.epicFix + D.epicT1, wt: 'work', ref: cfg.workBranch, deps: ['close.rev'], from: ['close.rev'], kind: 'fixes' });
		add({ ...gatesJob, deps: ['close.fix'], from: ['close.fix'], kind: 'checkpoint', gate: (t) => free(checkpointWt, t) });
	}
}

// Run.
for (let t = 0; t < 10000; t++) {
	for (const j of [...running]) {
		if (j.end === t) {
			running.splice(running.indexOf(j), 1);
			j.onEnd?.(t);
		}
	}
	let changed = true;
	while (changed) {
		changed = false;
		tryStartUnits(t);
		pending.sort((a, b) => a.seq - b.seq);
		for (const j of [...pending]) {
			if (j.at !== undefined && t < j.at) continue;
			if (!j.deps.every((d) => isDone(d, t) || (j.marker && doneAt(d) !== undefined && doneAt(d) + GAP <= t))) continue;
			if (j.gate && !j.gate(t)) continue;
			pending.splice(pending.indexOf(j), 1);
			j.start = t;
			j.end = t + j.dur;
			if (j.fromLast) j.from = [lastLaneTail()];
			jobs.push(j);
			j.onStart?.(t);
			if (typeof j.wt === 'function') j.wt = j.wt();
			if (j.dur === 0) j.onEnd?.(t);
			else running.push(j);
			changed = true;
		}
	}
	if (!pending.length && !running.length) break;
}
if (pending.length) throw new Error(`stuck: ${pending.map((j) => j.id).join(', ')}`);

// Emit the scenario.
const end = Math.max(...jobs.map((j) => j.end));
const steps = [];
const orchId = (c, phase) => `${c}.lead.${phase}`;
for (const [c, o] of childOrch) {
	if (o.plan) steps.push({ id: orchId(c, 'plan'), agent: 'child-orchestrator', label: 'child orchestrator', workItem: c, wt: o.plan[2], ref: `plan/${c}`, at: o.plan[0], dur: o.plan[1] - o.plan[0] });
	if (o.lane) steps.push({ id: orchId(c, 'lane'), agent: 'child-orchestrator', label: 'child orchestrator', workItem: c, wt: o.lane[2], ref: `lane/${c}`, at: o.lane[0], dur: o.lane[1] - o.lane[0], resume: orchId(c, 'plan') });
}
const realJobs = jobs.filter((j) => !j.marker);
for (const j of realJobs) {
	const parent = V.childOrchestrator && j.parentOf && childOrch.get(j.item)?.[j.parentOf] ? orchId(j.item, j.parentOf) : undefined;
	const fromIds = (j.from ?? []).filter((f) => realJobs.some((r) => r.id === f));
	steps.push({
		id: j.id, agent: j.agent, label: j.label, workItem: j.item, wt: j.wt, ref: j.ref, at: j.start, dur: j.dur,
		...(fromIds.length ? { from: fromIds, kind: j.fromKind ?? j.kind } : {}),
		...(j.resume ? { resume: j.resume } : {}),
		...(parent ? { parent } : {}),
		...(j.compact ? { compact: true } : {}),
	});
}
steps.sort((a, b) => a.at - b.at || a.id.localeCompare(b.id));
refs.push({ wt: 'work', ref: cfg.workBranch, from: 0, to: end + GAP });
const workItems = [
	{ id: 'baseline', label: 'baseline' },
	...kids.map((c) => ({ id: c.id, label: c.label, ...(c.splitFrom ? { parentId: c.splitFrom } : {}) })),
	...(cfg.checkpoints ?? []).map((cp) => ({ id: `cp-${cp.after}`, label: `checkpoint after ${cp.after}` })),
	...units.filter((u) => !u.single).map((u) => ({ id: u.id, label: u.label })),
	{ id: 'close', label: 'epic close' },
];
const usedWts = new Set(['work', ...steps.map((s) => s.wt)]);
const scenario = {
	title: cfg.title,
	repository: 'example-app',
	startedAt: '2026-01-05T09:00:00Z',
	gapMin: 0,
	worktrees: [
		{ id: 'work', label: 'work branch', kind: 'main' },
		...[...planning, ...pool, checkpointWt].filter((w) => usedWts.has(w.name)).map((w) => ({ id: w.name, label: w.name.replace('-', ' ') })),
	],
	orchestrator: { worktree: 'work', ref: cfg.workBranch },
	workItems,
	refs,
	steps,
	compactions,
};
fs.writeFileSync(outPath, JSON.stringify(scenario, null, '\t') + '\n');

// Summary.
const h = (m) => `${Math.floor(m / 60)}h${String(Math.round(m % 60)).padStart(2, '0')}`;
const busy = (name) => realJobs.filter((j) => j.wt === name).reduce((a, j) => a + j.dur, 0);
console.log(`${outPath}: end ${h(end)}`);
for (const c of lanesKids) {
	const s = st(c.id);
	console.log(`  ${c.id.padEnd(4)} plan ${String(s.planStart).padStart(4)}–${String(s.approved).padStart(4)}  start ${String(s.base).padStart(4)}  approved ${String(s.codeApproved).padStart(4)}  integrated ${String(s.integrated).padStart(4)}`);
}
console.log('  lanes busy (agent min):', pool.map((w) => `${w.name} ${busy(w.name)}`).join(', '));
