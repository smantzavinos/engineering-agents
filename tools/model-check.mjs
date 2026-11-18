#!/usr/bin/env node
// Checks that tie a plan's model to the code (plan design §4.6 checks 2 and 3, and §4.7).
// The diagram tool (`c4ish`) reports facts; this script holds the process rules.
//
// Usage:
//   node tools/model-check.mjs code     --model <model.c4ish.json> [--base <commit>] [options]
//   node tools/model-check.mjs approved --model <model.c4ish.json> [options]
//   node tools/model-check.mjs all      --model <model.c4ish.json> [options]
//
//   code      Model-to-code. Each element's change state against what happened to its code
//             references since the base commit; pattern tags against the model; tags on code no
//             element references; changed lines no element owns.
//   approved  Approved versus shipped. Every structural difference from the model at the latest
//             approval commit is a re-approval difference (stop) or a model change (must be
//             recorded as a deviation in the ledger).
//
// Options:
//   --plan <plan.md>       default: plan.md beside the model. Read for `Approved:` and
//                          `Re-approved:` lines and the "Changes outside the model" section.
//   --ledger <review.md>   default: review.md beside the plan. Read for the "Deviations" section.
//   --project <file.json>  the project's path file (see below). Default: none.
//   --base <commit>        `code` only. Default: the first `Approved:` commit in the plan.
//   --root <dir>           repository root. Default: the git repository holding the model.
//   --json                 print the result as JSON.
//   --code-report <file>   use this `c4ish code --json` output instead of running the tool.
//   --diff-report <file>   use this `c4ish diff --json` output instead of running the tool.
//   --changed-paths <file> use this list of changed paths (one per line) instead of asking git.
//
// Exit: 0 pass · 1 a check failed or a re-approval is needed · 2 usage or environment error.
//
// Project path file (all keys optional; paths and globs are relative to the repository root):
//   {
//     "profile": "docs/patterns/profile.c4ish.json",
//     "catalog": ["docs/patterns/**"],          catalog docs
//     "rules":   ["rules/patterns/**"],         conformance rules
//     "leftOut": ["**/*.test.ts", "docs/**"],   paths the model-to-code check leaves out
//     "noTag":   ["**/*.json"],                 file types that cannot carry a comment
//     "kinds":   { "data": ["data"], "container": ["container"], "product": ["product"] },
//     "enforcement": { "platform": "db", "platform-correlated": "db-correlated",
//                      "our-code": "our-code", "nothing": "nothing", "derived": "derived" }
//   }
//   `kinds` says which element kinds are data, containers and product elements. `enforcement`
//   maps the process's enforcement levels to the profile's ids (default: the same names).
//
// Ledger deviations: a section whose heading contains "Deviations"; one list item per differing
// item, starting with its key in backticks — the same `kind:id` the tool uses:
//   - `element:collector` dropped; nothing calls it after the page reads landed
//   - `relationship:mergeIndexes` rerouted through the summary query

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

/* ------------------------------------------------------------------------- */
/* Small helpers                                                               */
/* ------------------------------------------------------------------------- */

/** `**` any depth, `*` within one path segment, `?` one character. */
export function globToRegExp(glob) {
	let re = '';
	for (let i = 0; i < glob.length; i++) {
		const c = glob[i];
		if (c === '*') {
			if (glob[i + 1] === '*') {
				i++;
				if (glob[i + 1] === '/') {
					i++;
					re += '(?:.*/)?';
				} else re += '.*';
			} else re += '[^/]*';
		} else if (c === '?') re += '[^/]';
		else re += c.replace(/[.+^${}()|[\]\\]/g, '\\$&');
	}
	return new RegExp(`^${re}$`);
}

export const matchAny = (path, globs) => (globs ?? []).some((g) => globToRegExp(g).test(path));

const DEFAULT_STYLES = { new: 'new', modified: 'modified', reused: 'reused', removed: 'removed' };

/** Change-state id → style, from a profile file. The tool's default states are named after their styles. */
export function changeStyles(profile) {
	const out = { ...DEFAULT_STYLES };
	for (const [id, def] of Object.entries(profile?.changeStates ?? {})) if (def?.style) out[id] = def.style;
	return out;
}

/* ------------------------------------------------------------------------- */
/* plan.md and the ledger                                                      */
/* ------------------------------------------------------------------------- */

/** `Approved: <date> <commit>` and `Re-approved: <date> <commit>` lines, and the paths under "Changes outside the model". */
export function parsePlan(text) {
	const approvals = [];
	const outsideModel = [];
	let inSection = 0; // heading depth of the open "Changes outside the model" section
	for (const line of text.split('\n')) {
		const a = /^\s*(?:[-*]\s+)?\**(Approved|Re-approved):\**\s+(\S+)\s+`?([0-9a-fA-F]{7,40})`?/.exec(line);
		if (a) approvals.push({ kind: a[1], date: a[2], commit: a[3] });
		const h = /^(#{1,6})\s+(.*)$/.exec(line);
		if (h) inSection = /changes outside the model/i.test(h[2]) ? h[1].length : inSection && h[1].length > inSection ? inSection : 0;
		else if (inSection) for (const m of line.matchAll(/`([^`\s]+)`/g)) outsideModel.push(m[1]);
	}
	return { approvals, outsideModel };
}

/** Deviations recorded in the ledger: key (`kind:id`) → the line's text. */
export function parseLedger(text) {
	const deviations = new Map();
	let depth = 0;
	for (const line of text.split('\n')) {
		const h = /^(#{1,6})\s+(.*)$/.exec(line);
		if (h) depth = /deviations/i.test(h[2]) ? h[1].length : depth && h[1].length > depth ? depth : 0;
		else if (depth) {
			const m = /^\s*[-*]\s+`([a-z]+:[^`]+)`\s*(.*)$/.exec(line);
			if (m) deviations.set(m[1], m[2].trim());
		}
	}
	return deviations;
}

/* ------------------------------------------------------------------------- */
/* Pattern tags                                                                */
/* ------------------------------------------------------------------------- */

const ID = '[A-Za-z0-9][A-Za-z0-9._/-]*';

/**
 * The tag in a comment. `null`: no tag. Forms (design §4.3):
 *   @pattern <id> · @pattern <id> partial: <what differs> · @pattern bespoke: <what it is>
 *   each optionally followed by `; also <id>, <id>`
 */
export function parseTag(comment) {
	const lines = (comment ?? '').split('\n').filter((l) => l.includes('@pattern'));
	if (!lines.length) return null;
	if (lines.length > 1) return { error: 'more than one @pattern tag in one comment' };
	let rest = lines[0]
		.slice(lines[0].indexOf('@pattern') + '@pattern'.length)
		.replace(/\s*(\*\/|-->)\s*$/, '')
		.trim();
	const raw = `@pattern ${rest}`;
	let also = [];
	const tail = new RegExp(`;\\s*also\\s+(${ID}(?:\\s*,\\s*${ID})*)\\s*$`).exec(rest);
	if (tail) {
		also = tail[1].split(',').map((s) => s.trim());
		rest = rest.slice(0, tail.index).trim();
	}
	const bespoke = /^bespoke:\s*(.*)$/.exec(rest);
	if (bespoke) return bespoke[1].trim() ? { raw, bespoke: true, partial: false, also } : { raw, error: 'a bespoke tag must say what the code is' };
	const m = new RegExp(`^(${ID})(?:\\s+partial:\\s*(.*))?$`).exec(rest);
	if (!m || m[1] === 'bespoke') return { raw, error: `not a tag form: ${raw}` };
	if (m[2] !== undefined && !m[2].trim()) return { raw, error: 'a partial tag must say what differs' };
	return { raw, pattern: m[1], bespoke: false, partial: m[2] !== undefined, also };
}

/** The first comment of a file: where a whole-file definition carries its tag. */
export function firstComment(text) {
	const lines = text.split('\n');
	let i = 0;
	if (lines[0]?.startsWith('#!')) i++;
	while (i < lines.length && !lines[i].trim()) i++;
	// an opening tag line may precede the comment in a component file
	if (/^<script\b[^>]*>\s*$/.test(lines[i]?.trim() ?? '')) {
		i++;
		while (i < lines.length && !lines[i].trim()) i++;
	}
	const start = i;
	const first = lines[i]?.trim() ?? '';
	if (first.startsWith('/*') || first.startsWith('<!--')) {
		const close = first.startsWith('/*') ? '*/' : '-->';
		while (i < lines.length && !lines[i].includes(close)) i++;
		i++;
	} else while (i < lines.length && /^\s*(\/\/|#|--)/.test(lines[i])) i++;
	return i > start ? { start: start + 1, end: Math.min(i, lines.length), text: lines.slice(start, i).join('\n') } : undefined;
}

/**
 * What the model says the tag on an owner's code must be. `none`: the owner has no pattern state
 * (a container, a product concept). `pattern: null` in the model stands for bespoke.
 */
export function expectedTag(model, owner) {
	const element = model.elements.find((e) => e.id === owner.element);
	if (!element) return { none: true };
	const part = owner.part === undefined ? undefined : (element.parts ?? []).find((p) => p.title === owner.part || p.id === owner.part);
	if (part && part.pattern !== undefined) return part.pattern === null ? { bespoke: true, partial: false, also: [] } : { pattern: part.pattern, bespoke: false, partial: false, also: [] };
	if (element.pattern === undefined) return { none: true };
	if (element.pattern === null) return { bespoke: true, partial: false, also: [] };
	return { pattern: element.pattern, bespoke: false, partial: element.patternFit === 'partial', also: (element.patterns ?? []).filter((p) => p !== element.pattern) };
}

/** Why a tag does not agree with the model; empty when it does. `tag` is `parseTag`'s result. */
export function tagMismatches(tag, expected) {
	if (expected.none) return tag ? [`has the tag \`${tag.raw}\` but the model gives its element no pattern`] : [];
	if (!tag) return ['has no @pattern tag'];
	if (tag.error) return [tag.error];
	const out = [];
	if (expected.bespoke !== tag.bespoke) out.push(expected.bespoke ? `is tagged \`${tag.pattern}\` but the model marks it bespoke` : 'is tagged bespoke but the model gives it a pattern');
	else if (!expected.bespoke && tag.pattern !== expected.pattern) out.push(`is tagged \`${tag.pattern}\` but the model says \`${expected.pattern}\``);
	if (!expected.bespoke && !tag.bespoke && expected.partial !== tag.partial) out.push(expected.partial ? 'is not tagged partial but the model marks a partial fit' : 'is tagged partial but the model marks a full fit');
	const want = [...expected.also].sort().join(', ');
	const got = [...tag.also].sort().join(', ');
	if (want !== got) out.push(`names further patterns [${got}] but the model lists [${want}]`);
	return out;
}

/* ------------------------------------------------------------------------- */
/* Check 2: model-to-code                                                      */
/* ------------------------------------------------------------------------- */

const refPath = (ref) => ref.split('#')[0];
const isChanged = (r) => r.delta === 'added' || r.delta === 'modified';
const through = (r) => (r.changedThrough?.length ? ` (changed through ${r.changedThrough.join(', ')})` : '');
const hint = (r) => (r.hints?.length ? `; it may now be ${r.hints.map((h) => `\`${h.ref}\` (${h.kind})`).join(' or ')}` : '');

/** Where the tags of a reference may be: comment line ranges at the working tree, with their text. */
function tagComments(report, read) {
	const text = read(refPath(report.ref));
	if (text === undefined || report.head?.status !== 'resolved') return [];
	const lines = text.split('\n');
	const out = [];
	for (const e of report.head.extents ?? []) {
		if (e.kind === 'file') {
			const c = firstComment(text);
			if (c) out.push(c);
		} else if (e.comment) out.push({ start: e.comment.start, end: e.comment.end, text: lines.slice(e.comment.start - 1, e.comment.end).join('\n') });
	}
	return out;
}

/**
 * @param model   the model (parsed JSON)
 * @param report  `c4ish code <model> --base <commit> --json`
 * @param options { styles, project, outsideModel, read(path) → text | undefined }
 */
export function checkCode(model, report, options = {}) {
	const { styles = DEFAULT_STYLES, project = {}, outsideModel = [], read = () => undefined } = options;
	const failures = [];
	const fail = (kind, where, message) => failures.push({ kind, where, message });
	const noTag = project.noTag ?? ['**/*.json'];

	for (const r of report.references) if (r.problem) fail('reference', r.ref, r.problem + hint(r));
	if (report.references.some((r) => r.delta === undefined && !r.problem)) fail('usage', 'report', 'the code report has no base commit; run the tool with --base');

	// 1. each element's change state against its references
	const elements = [];
	for (const e of model.elements) {
		const style = styles[e.change] ?? 'reused';
		const refs = report.references.filter((r) => r.owners.some((o) => o.element === e.id));
		const before = failures.length;
		const where = `element ${e.id}`;
		if (!refs.length) {
			if (e.pattern !== undefined && (style === 'new' || style === 'modified')) fail('element', where, `is ${style} and has a pattern, but no code reference`);
			elements.push({ id: e.id, style, references: 0, ok: failures.length === before });
			continue;
		}
		const usable = refs.filter((r) => !r.problem && r.delta !== undefined);
		if (style === 'new') {
			for (const r of usable) if (r.delta !== 'added') fail('element', where, `is new, but \`${r.ref}\` is ${r.delta === 'missing' ? 'not in the code' : `${r.delta}: it existed at the base`}${hint(r)}`);
		} else if (style === 'modified') {
			for (const r of usable) if (r.head.status !== 'resolved') fail('element', where, `is modified, but \`${r.ref}\` does not resolve (${r.head.status})${hint(r)}`);
			if (usable.length && !usable.some((r) => isChanged(r) || r.changedThrough?.length)) fail('element', where, 'is modified, but none of its references changed');
		} else if (style === 'removed') {
			for (const r of usable) if (r.delta !== 'removed') fail('element', where, `is removed, but \`${r.ref}\` is ${r.delta === 'missing' ? 'at neither the base nor the working tree' : `still there (${r.delta})`}${hint(r)}`);
		} else {
			for (const r of usable)
				if (r.delta !== 'unchanged' || r.changedThrough?.length) fail('element', where, `is reused, but \`${r.ref}\` is ${r.delta}${through(r)}: that makes it modified, a model change`);
		}

		// tags: on code the plan created or changed the tag must be there and agree; on code it left alone a tag must agree if there is one
		if (style === 'new' || style === 'modified') {
			for (const r of usable) {
				if (r.head.status !== 'resolved' || matchAny(refPath(r.ref), noTag)) continue;
				const comments = tagComments(r, read);
				const tags = comments.map((c) => parseTag(c.text)).filter(Boolean);
				const tag = tags.length > 1 ? { error: 'more than one @pattern tag on one definition' } : (tags[0] ?? null);
				for (const o of r.owners.filter((o) => o.element === e.id)) {
					const expected = expectedTag(model, o);
					if (!tag && !isChanged(r)) continue;
					for (const m of tagMismatches(tag, expected)) fail('tag', where, `\`${r.ref}\`${o.part ? ` (part "${o.part}")` : ''} ${m}`);
				}
			}
		}
		elements.push({ id: e.id, style, references: refs.length, ok: failures.length === before });
	}

	// 2. over the whole diff: tags on code nothing references, and changed lines nothing owns
	const tagLines = new Map(); // path → line numbers where a referenced definition's tag may sit
	for (const r of report.references) {
		const set = tagLines.get(refPath(r.ref)) ?? new Set();
		for (const c of tagComments(r, read)) for (let n = c.start; n <= c.end; n++) set.add(n);
		tagLines.set(refPath(r.ref), set);
	}
	const unaccounted = { runs: [], lines: 0, outsideModelLines: 0 };
	const leftOut = (p) => matchAny(p, project.leftOut);
	for (const f of report.files ?? []) {
		if (leftOut(f.path)) continue;
		const listed = matchAny(f.path, outsideModel);
		if (f.binary) {
			unaccounted.runs.push({ path: f.path, binary: true, ...(listed && { outsideModel: true }) });
			continue;
		}
		const text = f.status === 'deleted' ? undefined : read(f.path);
		const lines = text?.split('\n');
		for (const range of f.head ?? []) {
			if (lines)
				for (let n = range.start; n <= range.end; n++)
					if (lines[n - 1]?.includes('@pattern') && !tagLines.get(f.path)?.has(n))
						fail('built-not-modelled', `${f.path}:${n}`, `a @pattern tag was added or changed here, but no element references this definition: \`${lines[n - 1].trim()}\``);
		}
		for (const [side, ranges] of [
			['head', f.head ?? []],
			['base', f.base ?? []]
		])
			for (const range of ranges) {
				if (range.refs?.length) continue;
				const n = range.end - range.start + 1;
				unaccounted.runs.push({ path: f.path, side, start: range.start, end: range.end, lines: n, ...(listed && { outsideModel: true }) });
				unaccounted.lines += n;
				if (listed) unaccounted.outsideModelLines += n;
			}
	}
	return { ok: failures.length === 0, elements, failures, unaccounted };
}

/* ------------------------------------------------------------------------- */
/* Check 3: approved versus shipped                                            */
/* ------------------------------------------------------------------------- */

/** Enforcement strength, strongest first. `derived` sits below the two platform levels (§4.7). */
function rank(project, id) {
	if (id === undefined || id === null) return Infinity;
	const names = project.enforcement ?? {};
	const of = (role) => names[role] ?? role;
	if (id === of('platform')) return 0;
	if (id === of('platform-correlated')) return 1;
	if (id === of('derived')) return 1.5;
	if (id === of('our-code')) return 2;
	if (id === of('nothing')) return 3;
	return undefined;
}

/** Reasons a change of enforcement needs re-approval. */
function enforcementReasons(project, what, before, after, added) {
	const a = rank(project, after);
	if (added) return a === undefined ? [`new ${what} with an enforcement this check cannot rank (\`${after}\`)`] : a >= 2 ? [`new ${what} enforced by \`${after ?? 'nothing stated'}\``] : [];
	const b = rank(project, before);
	if (a === undefined || b === undefined) return [`enforcement on ${what} changed and this check cannot rank \`${a === undefined ? after : before}\``];
	return a > b ? [`enforcement on ${what} moved down: \`${before}\` → \`${after ?? 'none'}\``] : [];
}

/**
 * @param diff     `c4ish diff <model> --base <approval commit> --only structure --json`
 * @param options  { styles, project, profilePatterns: Set, deviations: Map, changedPaths: string[], outsideModel: string[] }
 */
export function checkApproved(diff, options = {}) {
	const { styles = DEFAULT_STYLES, project = {}, profilePatterns = new Set(), deviations = new Map(), changedPaths = [], outsideModel = [] } = options;
	const kinds = project.kinds ?? {};
	const guarded = new Set([...(kinds.data ?? []), ...(kinds.container ?? []), ...(kinds.product ?? [])]);
	const kindName = (k) => (kinds.data?.includes(k) ? 'data element' : kinds.container?.includes(k) ? 'container' : 'product element');
	const differences = [];
	for (const d of diff.differences ?? []) {
		if (!d.aspects?.includes('structure')) continue;
		// a proposed pattern that became catalogued shows as a proposed pattern removed
		if (d.kind === 'pattern' && d.change === 'removed' && profilePatterns.has(d.id)) continue;
		const reasons = [];
		const fields = (d.fields ?? []).filter((f) => f.aspect === 'structure');
		if (d.kind === 'element') {
			const kind = (d.after ?? d.before)?.kind;
			if (d.change !== 'changed' && guarded.has(kind)) reasons.push(`${kindName(kind)} ${d.change}`);
			for (const f of fields) {
				if (f.path.length === 1 && f.path[0] === 'change' && styles[f.after] === 'removed') reasons.push('change state became removed');
				if (f.path[0] === 'ties' && f.path.length === 3 && f.path[2] === 'enforcement') reasons.push(...enforcementReasons(project, `tie ${f.path[1]}`, f.before, f.after, false));
				if (f.path[0] === 'ties' && f.path.length === 2 && f.change === 'added') reasons.push(...enforcementReasons(project, `tie ${f.path[1]}`, undefined, f.after?.enforcement, true));
			}
			// a data element that arrives with weakly enforced ties is covered by "data element added"
		} else if (d.kind === 'relationship') {
			if (d.change === 'added' && d.after?.enforcement !== undefined) reasons.push(...enforcementReasons(project, 'data relationship', undefined, d.after.enforcement, true));
			for (const f of fields) if (f.path.length === 1 && f.path[0] === 'enforcement') reasons.push(...enforcementReasons(project, 'data relationship', f.before, f.after, f.change === 'added'));
		} else if (d.kind === 'contract') {
			if (d.change === 'removed') reasons.push('contract removed');
			for (const f of fields) {
				if (f.path[0] !== 'clauses' || f.path.length !== 2) continue;
				if (f.path[1] === 'access') reasons.push(`access clause ${f.change}`);
				else if (f.change === 'removed') reasons.push(`clause \`${f.path[1]}\` removed`);
			}
		}
		const key = `${d.kind}:${d.id}`;
		differences.push({
			key,
			change: d.change,
			fields: fields.map((f) => ({ path: f.path.join('.'), change: f.change })),
			class: reasons.length ? 're-approval' : 'model-change',
			...(reasons.length && { reasons }),
			recorded: deviations.has(key),
			...(deviations.has(key) && { deviation: deviations.get(key) })
		});
	}

	// catalog, rule and profile files changed that the approved plan does not list
	const paths = [];
	for (const p of changedPaths) {
		const kind = matchAny(p, project.catalog) ? 'catalog' : matchAny(p, project.rules) ? 'rule' : project.profile === p ? 'profile' : undefined;
		if (kind && !matchAny(p, outsideModel)) paths.push({ path: p, kind });
	}

	const seen = new Set(differences.map((d) => d.key));
	const stale = [...deviations.keys()].filter((k) => !seen.has(k));
	const reapproval = differences.filter((d) => d.class === 're-approval');
	const unrecorded = differences.filter((d) => d.class === 'model-change' && !d.recorded);
	const verdict = reapproval.length || paths.length ? 're-approval' : unrecorded.length ? 'fail' : 'pass';
	return { ok: verdict === 'pass', verdict, differences, paths, stale };
}

/* ------------------------------------------------------------------------- */
/* Command line                                                                */
/* ------------------------------------------------------------------------- */

class UsageError extends Error {}

function parseArgs(argv) {
	const [command, ...rest] = argv;
	const opts = {};
	for (let i = 0; i < rest.length; i++) {
		const a = rest[i];
		if (!a.startsWith('--')) throw new UsageError(`unexpected argument: ${a}`);
		const key = a.slice(2);
		if (key === 'json') opts.json = true;
		else if (['model', 'plan', 'ledger', 'project', 'base', 'root', 'code-report', 'diff-report', 'changed-paths'].includes(key)) {
			if (rest[i + 1] === undefined) throw new UsageError(`--${key} needs a value`);
			opts[key] = rest[++i];
		} else throw new UsageError(`unknown option: ${a}`);
	}
	if (!['code', 'approved', 'all'].includes(command)) throw new UsageError('give a command: code, approved or all');
	if (!opts.model) throw new UsageError('--model is required');
	return { command, opts };
}

const readJson = (path) => JSON.parse(readFileSync(path, 'utf8'));
const git = (root, args) => execFileSync('git', ['-C', root, ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 256 * 1024 * 1024 });

/** Run the diagram tool and parse its JSON. It exits non-zero when it reports problems, with the JSON still on stdout. */
function tool(args) {
	let out;
	try {
		out = execFileSync(process.env.C4ISH ?? 'c4ish', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 256 * 1024 * 1024 });
	} catch (e) {
		if (e.code === 'ENOENT') throw new UsageError('c4ish is not on PATH (set C4ISH to its path)');
		out = e.stdout ?? '';
		try {
			return JSON.parse(out);
		} catch {
			throw new UsageError(`c4ish ${args.join(' ')} failed:\n${(e.stderr || out || e.message).trim()}`);
		}
	}
	return JSON.parse(out);
}

function context(opts) {
	const model = resolve(opts.model);
	if (!existsSync(model)) throw new UsageError(`no such model: ${opts.model}`);
	let root = opts.root && resolve(opts.root);
	if (!root) {
		try {
			root = git(dirname(model), ['rev-parse', '--show-toplevel']).trim();
		} catch {
			throw new UsageError(`${opts.model} is not inside a git repository; pass --root <dir>`);
		}
	}
	const plan = resolve(opts.plan ?? join(dirname(model), 'plan.md'));
	const ledger = resolve(opts.ledger ?? join(dirname(plan), 'review.md'));
	const project = opts.project ? readJson(resolve(opts.project)) : {};
	const profilePath = project.profile ? join(root, project.profile) : undefined;
	const profile = profilePath && existsSync(profilePath) ? readJson(profilePath) : undefined;
	const planText = existsSync(plan) ? readFileSync(plan, 'utf8') : undefined;
	const parsed = planText === undefined ? { approvals: [], outsideModel: [] } : parsePlan(planText);
	const toolArgs = profilePath ? ['--profile', profilePath] : [];
	return { model, root, plan, ledger, project, profile, profilePath, ...parsed, styles: changeStyles(profile), toolArgs };
}

/** "Changes outside the model" as the approved plan had it; the working copy if that commit has no plan. */
function approvedOutsideModel(ctx, commit) {
	try {
		return parsePlan(git(ctx.root, ['show', `${commit}:${relative(ctx.root, ctx.plan)}`])).outsideModel;
	} catch {
		return ctx.outsideModel;
	}
}

function runCode(ctx, opts) {
	const base = opts.base ?? ctx.approvals.find((a) => a.kind === 'Approved')?.commit;
	let report;
	if (opts['code-report']) report = readJson(resolve(opts['code-report']));
	else {
		if (!base) throw new UsageError('no base commit: pass --base, or record `Approved: <date> <commit>` in the plan');
		report = tool(['code', ctx.model, '--base', base, '--root', ctx.root, '--json', ...ctx.toolArgs]);
	}
	const read = (p) => {
		try {
			return readFileSync(join(ctx.root, p), 'utf8');
		} catch {
			return undefined;
		}
	};
	const outsideModel = base && !opts['code-report'] ? approvedOutsideModel(ctx, base) : ctx.outsideModel;
	return { base: report.base ?? base, ...checkCode(readJson(ctx.model), report, { styles: ctx.styles, project: ctx.project, outsideModel, read }) };
}

function runApproved(ctx, opts) {
	const latest = ctx.approvals.at(-1);
	let diff;
	if (opts['diff-report']) diff = readJson(resolve(opts['diff-report']));
	else {
		if (!latest) throw new UsageError(`no \`Approved: <date> <commit>\` line in ${ctx.plan}`);
		diff = tool(['diff', ctx.model, '--base', latest.commit, '--only', 'structure', '--json', ...ctx.toolArgs]);
	}
	let changedPaths = [];
	if (opts['changed-paths']) changedPaths = readFileSync(resolve(opts['changed-paths']), 'utf8').split('\n').filter(Boolean);
	else if (latest) {
		const list = (args) => git(ctx.root, args).split('\n').filter(Boolean);
		changedPaths = [...new Set([...list(['diff', '--name-only', latest.commit]), ...list(['ls-files', '--others', '--exclude-standard'])])];
	}
	const deviations = existsSync(ctx.ledger) ? parseLedger(readFileSync(ctx.ledger, 'utf8')) : new Map();
	const profilePatterns = new Set(Array.isArray(ctx.profile?.patterns) ? ctx.profile.patterns.map((p) => p.id) : Object.keys(ctx.profile?.patterns ?? {}));
	const outsideModel = latest && !opts['diff-report'] ? approvedOutsideModel(ctx, latest.commit) : ctx.outsideModel;
	return { against: latest, ...checkApproved(diff, { styles: ctx.styles, project: ctx.project, profilePatterns, deviations, changedPaths, outsideModel }) };
}

function printCode(r) {
	const bad = r.elements.filter((e) => !e.ok).length;
	console.log(`model-to-code${r.base ? ` (base ${String(r.base).slice(0, 10)})` : ''}: ${r.ok ? 'pass' : 'FAIL'} — ${r.elements.filter((e) => e.references).length} element(s) with references, ${bad} failing`);
	for (const f of r.failures) console.log(`  fail  ${f.where}: ${f.message}`);
	const u = r.unaccounted;
	console.log(`  unaccounted: ${u.lines} changed line(s) in ${new Set(u.runs.map((x) => x.path)).size} file(s) inside no reference${u.outsideModelLines ? ` (${u.outsideModelLines} in files the plan lists outside the model)` : ''}`);
	const byFile = new Map();
	for (const run of u.runs) byFile.set(run.path, [...(byFile.get(run.path) ?? []), run]);
	for (const [path, runs] of byFile) {
		const where = runs.map((x) => (x.binary ? 'binary' : `${x.side === 'base' ? 'was ' : ''}${x.start}${x.end > x.start ? `-${x.end}` : ''}`)).join(', ');
		console.log(`    ${path}${runs[0].outsideModel ? ' [outside the model]' : ''}: ${where}`);
	}
}

function printApproved(r) {
	const label = { pass: 'pass', fail: 'FAIL', 're-approval': 'STOP — re-approval needed' }[r.verdict];
	console.log(`approved versus shipped${r.against ? ` (against ${r.against.kind} ${r.against.commit.slice(0, 10)})` : ''}: ${label} — ${r.differences.length} structural difference(s)`);
	for (const d of r.differences) {
		const what = d.fields.length ? d.fields.map((f) => f.path).join(', ') : d.change;
		if (d.class === 're-approval') console.log(`  stop  ${d.key} (${what}): ${d.reasons.join('; ')}`);
		else console.log(`  ${d.recorded ? 'ok  ' : 'fail'}  ${d.key} (${what}): model change, ${d.recorded ? `recorded — ${d.deviation}` : 'not recorded in the ledger'}`);
	}
	for (const p of r.paths) console.log(`  stop  ${p.path}: ${p.kind} file changed, and the approved plan does not list it under Changes outside the model`);
	for (const k of r.stale) console.log(`  note  the ledger records \`${k}\`, which does not differ from the approved model`);
}

export function main(argv) {
	let parsed;
	try {
		parsed = parseArgs(argv);
		const ctx = context(parsed.opts);
		const result = {};
		if (parsed.command !== 'approved') result.code = runCode(ctx, parsed.opts);
		if (parsed.command !== 'code') result.approved = runApproved(ctx, parsed.opts);
		if (parsed.opts.json) console.log(JSON.stringify(result, null, 2));
		else {
			if (result.code) printCode(result.code);
			if (result.approved) printApproved(result.approved);
		}
		return Object.values(result).every((r) => r.ok) ? 0 : 1;
	} catch (e) {
		if (!(e instanceof UsageError) && !(e instanceof SyntaxError)) throw e;
		console.error(`model-check: ${e.message}`);
		return 2;
	}
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) process.exitCode = main(process.argv.slice(2));
