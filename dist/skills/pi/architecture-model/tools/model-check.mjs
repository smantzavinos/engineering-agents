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
//             references since the base commit; that each element the build creates or changes
//             in code states a pattern or is bespoke, and names its code; pattern tags against
//             the model; tags on code no element references; changed lines no element owns.
//   approved  Approved versus shipped. Every structural difference from the model at the latest
//             approval commit is a re-approval difference (stop) or a model change (must be
//             recorded as a deviation in the ledger).
//
// Options:
//   --plan <plan.md>       default: plan.md beside the model. Read for `Approved:` and
//                          `Re-approved:` lines and the "Changes outside the model" section.
//   --ledger <review.md>   default: review.md beside the plan. Read for the "Deviations" section.
//   --project <file.json>  the project's path file (see below). `approved` needs it.
//   --base <commit>        `code` only: the code baseline. Default: the first `Approved:` commit.
//                          It may be that commit or an earlier one, never a later one.
//   --root <dir>           repository root. Default: the git repository holding the model.
//   --json                 print the result as JSON.
//
// What the check is judged by. A plan with an approval line is judged by what was approved: the
// path file, the profile and the plan's "Changes outside the model" list are all read from git at
// the latest approval commit, never from the working copy. Each must be in that commit; there is no fallback. Every approval commit must be
// an ancestor of HEAD, in the order the plan lists them. `approved` compares with the latest one.
// A change to the path file or the profile stops like a catalog change.
//
// Trials. A plan with no approval line runs only with --no-approval, and is then judged by the
// working copy. The result is marked as a trial. Only a trial may use reports made beforehand:
//   --no-approval          run a plan that has no approval line.
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
//     "enforcement": { "platform": "db", "platform-correlated": "db-correlated",
//                      "our-code": "our-code", "nothing": "nothing", "derived": "derived" }
//   }
//   `enforcement` maps the process's enforcement levels to the profile's ids (default: the same
//   names).
//
// The profile. The tool prints the profile as it reads it (`c4ish profile`), and the check takes
// three things from that: the style of each change state, which relationship kinds carry data, and
// the category of each element kind (container, code, data or product; none for a kind that is
// neither, such as an external system). With no profile named, the tool's default profile applies.
//
// Pattern states. An element of a code or data kind that the build creates or changes must name a
// pattern or say `bespoke` with a reason, on itself or on each of its parts, and must have a code
// reference. `pattern: null` says no pattern applies; it is not a state for such an element.
//
// A glob with no wildcard also matches everything under it (`docs/patterns` = `docs/patterns/**`).
// A leading `./` is dropped.
//
// Tags. A tag is one line: `@pattern` first on its comment line, after the comment marker. A line
// with no marker counts only inside a block comment that opens at the start of a line.
//
// plan.md: `Approved: <date> <commit>` and `Re-approved: <date> <commit>` lines, and a section
// headed "Changes outside the model" with one list item per path or glob, starting with it in
// backticks:
//   - `migrations/004_page_cursor.sql` adds the cursor column
//
// Ledger deviations: a section headed "Deviations"; one list item per differing item, starting
// with its key in backticks — the same `kind:id` the tool uses:
//   - `element:collector` dropped; nothing calls it after the page reads landed
//   - `relationship:mergeIndexes` rerouted through the summary query
//
// Text inside fenced code blocks is ignored in both files.

import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
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

/** A glob with no wildcard names a file or a directory: it also matches everything under it. A leading `./` is dropped. */
export const matchAny = (path, globs) =>
	(globs ?? []).some((raw) => {
		const g = raw.replace(/^(?:\.\/+)+/, '').replace(/\/+$/, '');
		return /[*?]/.test(g) ? globToRegExp(g).test(path) : path === g || path.startsWith(`${g}/`);
	});

const DEFAULT_STYLES = { new: 'new', modified: 'modified', reused: 'reused', removed: 'removed' };

/** Change-state id → style, from a profile file. The tool's default states are named after their styles. */
export function changeStyles(profile) {
	const out = { ...DEFAULT_STYLES };
	for (const [id, def] of Object.entries(profile?.changeStates ?? {})) if (def?.style) out[id] = def.style;
	return out;
}

const DEFAULT_DATA_RELATIONSHIPS = ['reads', 'writes', 'references', 'pins'];

/** Relationship kinds that carry data, from a profile file. The tool's default profile has four. */
export function dataRelationshipKinds(profile) {
	const out = new Set(!profile || profile.extends === 'default' ? DEFAULT_DATA_RELATIONSHIPS : []);
	for (const [id, def] of Object.entries(profile?.relationshipKinds ?? {})) {
		if (def?.category === 'data' || def?.enforcementRequired) out.add(id);
		else out.delete(id);
	}
	return out;
}

/** Element kind → category (`container`, `code`, `data`, `product`), from a profile as the tool resolves it. */
export function kindCategories(profile) {
	const out = {};
	for (const [id, def] of Object.entries(profile?.elementKinds ?? {})) if (def?.category) out[id] = def.category;
	return out;
}

/** What re-approval calls an element of a guarded category. */
const GUARDED = { data: 'data element', container: 'container', product: 'product element' };

/** Whether an element or a part says what it is: a pattern, or bespoke. `pattern: null` says neither. */
const statesPattern = (x) => typeof x.pattern === 'string' || x.bespoke !== undefined;

/* ------------------------------------------------------------------------- */
/* plan.md and the ledger                                                      */
/* ------------------------------------------------------------------------- */

/** The lines of a Markdown text outside fenced code blocks. */
function proseLines(text) {
	const out = [];
	let fence;
	for (const line of text.split(/\r?\n/)) {
		const m = /^\s*(```+|~~~+)/.exec(line);
		if (m && !fence) fence = m[1][0];
		else if (m && m[1][0] === fence) fence = undefined;
		else if (!fence) out.push(line);
	}
	return out;
}

/** List items that start with a backticked token, inside the section with exactly this heading. */
function sectionItems(text, heading) {
	const title = new RegExp(`^(?:[\\d.]+\\s+)?${heading}:?\\s*$`, 'i');
	const out = [];
	let depth = 0;
	for (const line of proseLines(text)) {
		const h = /^(#{1,6})\s+(.*)$/.exec(line);
		if (h) depth = title.test(h[2].replace(/[*_`]/g, '').trim()) ? h[1].length : depth && h[1].length > depth ? depth : 0;
		else if (depth) {
			const m = /^\s*(?:[-*+]|\d+[.)])\s+`([^`]+)`\s*(.*)$/.exec(line);
			if (m) out.push([m[1].trim(), m[2].trim()]);
		}
	}
	return out;
}

/** `Approved: <date> <commit>` and `Re-approved: <date> <commit>` lines, and the paths under "Changes outside the model". */
export function parsePlan(text) {
	const approvals = [];
	for (const line of proseLines(text)) {
		const a = /^\s*(?:[-*]\s+)?\**(Approved|Re-approved):\**\s+(\S+)\s+`?([0-9a-fA-F]{7,40})`?/.exec(line);
		if (a) approvals.push({ kind: a[1], date: a[2], commit: a[3] });
	}
	return { approvals, outsideModel: sectionItems(text, 'changes outside the model').map(([path]) => path) };
}

/** Deviations recorded in the ledger: key (`kind:id`) → the line's text. */
export function parseLedger(text) {
	return new Map(sectionItems(text, 'deviations').filter(([key]) => /^[a-z]+:.+/.test(key)));
}

/* ------------------------------------------------------------------------- */
/* Pattern tags                                                                */
/* ------------------------------------------------------------------------- */

const ID = '[A-Za-z0-9][A-Za-z0-9._/-]*';

const MARKED_TAG = /^\s*(?:\/\/+!?|\{?\/\*+!?|\*|#|<!--|--|;+|%+)\s*@pattern(?:\s|$)/;
const BARE_TAG = /^\s*@pattern(?:\s|$)/;

/**
 * A tag starts its comment line: `@pattern` straight after a comment marker. Mentions in prose or
 * strings are not tags. A line with no marker is a tag only inside a comment (`inComment`).
 */
export const isTagLine = (line, inComment = true) => MARKED_TAG.test(line) || (inComment && BARE_TAG.test(line));

/** Line numbers (1-based) inside a block comment that opens at the start of a line, the opening line excluded. */
export function blockCommentLines(text) {
	const out = new Set();
	let close;
	text.split('\n').forEach((line, i) => {
		if (close) {
			out.add(i + 1);
			if (line.includes(close)) close = undefined;
			return;
		}
		const open = /^\s*(\{?\/\*|<!--)/.exec(line);
		if (!open) return;
		const end = open[1] === '<!--' ? '-->' : '*/';
		if (!line.slice(open[0].length).includes(end)) close = end;
	});
	return out;
}

/**
 * The tag in a comment. `null`: no tag. Forms (design §4.3):
 *   @pattern <id> · @pattern <id> partial: <what differs> · @pattern bespoke: <what it is>
 *   each optionally followed by `; also <id>, <id>`
 */
export function parseTag(comment) {
	const lines = (comment ?? '').split('\n').filter(isTagLine);
	if (!lines.length) return null;
	if (lines.length > 1) return { error: 'more than one @pattern tag in one comment' };
	let rest = lines[0]
		.slice(lines[0].indexOf('@pattern') + '@pattern'.length)
		.replace(/\s*(\*\/\}?|-->)\s*$/, '')
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
	// an opening tag line may precede the comment in a component file, and directives ("use strict") in a script
	for (const before of [/^<script\b[^>]*>$/, /^(['"])use [a-z ]+\1;?$/])
		while (i < lines.length && before.test(lines[i].trim())) {
			i++;
			while (i < lines.length && !lines[i].trim()) i++;
		}
	const start = i;
	const first = lines[i]?.trim() ?? '';
	if (first.startsWith('/*') || first.startsWith('{/*') || first.startsWith('<!--')) {
		const close = first.startsWith('<!--') ? '-->' : '*/';
		while (i < lines.length && !lines[i].includes(close)) i++;
		i++;
	} else while (i < lines.length && /^\s*(\/\/|#|--|;|%)/.test(lines[i])) i++;
	return i > start ? { start: start + 1, end: Math.min(i, lines.length), text: lines.slice(start, i).join('\n') } : undefined;
}

/**
 * What the model says the tag on an owner's code must be. `none`: the owner has no pattern state
 * (a container, a product concept, or `pattern: null`: no pattern applies). A part that states its
 * own pattern, or is bespoke, or says `pattern: null`, is judged by that; any other part carries
 * its element's tag.
 */
export function expectedTag(model, owner) {
	const element = model.elements.find((e) => e.id === owner.element);
	if (!element) return { none: true };
	const part = owner.part === undefined ? undefined : (element.parts ?? []).find((p) => p.title === owner.part || p.id === owner.part);
	if (part?.bespoke !== undefined) return { bespoke: true, partial: false, also: [] };
	if (part && part.pattern !== undefined) return part.pattern === null ? { none: true } : { pattern: part.pattern, bespoke: false, partial: part.patternFit === 'partial', also: [] };
	if (element.bespoke !== undefined) return { bespoke: true, partial: false, also: element.patterns ?? [] };
	if (typeof element.pattern !== 'string') return { none: true };
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
 * @param options { styles, categories, project, outsideModel, read(path) → text | undefined }
 *                `categories` is `kindCategories(profile)`; without it no element is known to live in code.
 */
export function checkCode(model, report, options = {}) {
	const { styles = DEFAULT_STYLES, categories = {}, project = {}, outsideModel = [], read = () => undefined } = options;
	const failures = [];
	const fail = (kind, where, message) => failures.push({ kind, where, message });
	const noTag = project.noTag ?? ['**/*.json'];

	for (const r of report.references) if (r.problem) fail('reference', r.ref, r.problem + hint(r));
	if (report.references.some((r) => r.delta === undefined && !r.problem)) fail('usage', 'report', 'the code report has no base commit; run the tool with --base');

	// 1. each element's change state against its references. A part with its own change state is judged by that.
	const elements = [];
	for (const e of model.elements) {
		const style = styles[e.change] ?? 'reused';
		const before = failures.length;
		const where = `element ${e.id}`;
		const owned = []; // one entry per (reference, owner in this element)
		for (const r of report.references) for (const o of r.owners) if (o.element === e.id) owned.push({ r, o, style: o.part !== undefined && o.change !== undefined ? (styles[o.change] ?? 'reused') : style });
		// an element the build creates or changes in code is in one pattern state, and names its code
		const category = categories[e.kind];
		const inCode = category === 'code' || category === 'data';
		const stated = statesPattern(e) || ((e.parts ?? []).length > 0 && e.parts.every(statesPattern));
		const built = style === 'new' || style === 'modified';
		if (built && inCode && !stated) {
			const none = e.pattern === null || (e.parts ?? []).some((p) => p.pattern === null);
			fail('element', where, `is ${style} ${category}, but ${none ? 'says `pattern: null`: name a pattern, or say `bespoke` with a reason' : 'states neither a pattern nor `bespoke` with a reason'}${(e.parts ?? []).length ? ' (on itself or on each of its parts)' : ''}`);
		}
		if (!owned.length) {
			if (built && (stated || inCode)) fail('element', where, `is ${style} and ${typeof e.pattern === 'string' ? 'has a pattern' : e.bespoke !== undefined ? 'is bespoke' : stated ? 'has parts with patterns' : `is ${category}`}, but no code reference`);
			elements.push({ id: e.id, style, references: 0, ok: failures.length === before });
			continue;
		}
		const usable = owned.filter(({ r }) => !r.problem && r.delta !== undefined);
		for (const { r, o, style: as } of usable) {
			const what = o.part !== undefined && as !== style ? `part "${o.part}" is ${as}` : `is ${as}`;
			if (as === 'new') {
				if (r.delta !== 'added') fail('element', where, `${what}, but \`${r.ref}\` is ${r.delta === 'missing' ? 'not in the code' : `${r.delta}: it existed at the base`}${hint(r)}`);
			} else if (as === 'modified') {
				if (r.head.status !== 'resolved') fail('element', where, `${what}, but \`${r.ref}\` does not resolve (${r.head.status})${hint(r)}`);
			} else if (as === 'removed') {
				if (r.delta !== 'removed') fail('element', where, `${what}, but \`${r.ref}\` is ${r.delta === 'missing' ? 'at neither the base nor the working tree' : `still there (${r.delta})`}${hint(r)}`);
			} else if (r.delta !== 'unchanged' || r.changedThrough?.length) fail('element', where, `${what}, but \`${r.ref}\` is ${r.delta}${through(r)}: that makes it modified, a model change`);
		}
		if (style === 'modified' && usable.length && !usable.some(({ r }) => r.delta !== 'unchanged' || r.changedThrough?.length)) fail('element', where, 'is modified, but none of its references changed');

		// tags: on code the plan created or changed the tag must be there and agree; on code it left
		// alone, in any element, a tag must agree if there is one — so a retag cannot switch a rule off
		for (const { r, o, style: as } of usable) {
			if (r.head.status !== 'resolved' || matchAny(refPath(r.ref), noTag)) continue;
			const tags = tagComments(r, read)
				.map((c) => parseTag(c.text))
				.filter(Boolean);
			const tag = tags.length > 1 ? { error: 'more than one @pattern tag on one definition' } : (tags[0] ?? null);
			if (!tag && (!isChanged(r) || as === 'reused')) continue; // changed reused code already fails above
			for (const m of tagMismatches(tag, expectedTag(model, o))) fail('tag', where, `\`${r.ref}\`${o.part ? ` (part "${o.part}")` : ''} ${m}`);
		}
		elements.push({ id: e.id, style, references: new Set(owned.map(({ r }) => r.ref)).size, ok: failures.length === before });
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
		const inBlock = text === undefined ? new Set() : blockCommentLines(text);
		for (const range of f.head ?? []) {
			if (lines)
				for (let n = range.start; n <= range.end; n++)
					if (isTagLine(lines[n - 1] ?? '', inBlock.has(n)) && !tagLines.get(f.path)?.has(n))
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
 * @param options  { styles, categories, project, projectPath, dataRelationships: Set, profilePatterns: Set, deviations: Map, changedPaths: string[], outsideModel: string[] }
 *                 `categories` is `kindCategories(profile)`; without it no element kind is guarded.
 */
export function checkApproved(diff, options = {}) {
	const { styles = DEFAULT_STYLES, categories = {}, project = {}, projectPath, dataRelationships = new Set(DEFAULT_DATA_RELATIONSHIPS), profilePatterns = new Set(), deviations = new Map(), changedPaths = [], outsideModel = [] } = options;
	const kindName = (k) => GUARDED[categories[k]];
	const guarded = (k) => kindName(k) !== undefined;
	const differences = [];
	for (const d of diff.differences ?? []) {
		if (!d.aspects?.includes('structure')) continue;
		// a proposed pattern that became catalogued shows as a proposed pattern removed
		if (d.kind === 'pattern' && d.change === 'removed' && profilePatterns.has(d.id)) continue;
		const reasons = [];
		const fields = (d.fields ?? []).filter((f) => f.aspect === 'structure');
		if (d.kind === 'element') {
			const kind = (d.after ?? d.before)?.kind;
			if (d.change !== 'changed' && guarded(kind)) reasons.push(`${kindName(kind)} ${d.change}`);
			for (const f of fields) {
				if (f.path.length === 1 && f.path[0] === 'kind') {
					// a kind that turns into, or out of, a guarded kind is one added or removed
					if (guarded(f.after)) reasons.push(`${kindName(f.after)} added (kind was \`${f.before}\`)`);
					if (guarded(f.before)) reasons.push(`${kindName(f.before)} removed (kind is now \`${f.after}\`)`);
				}
				if (f.path.length === 1 && f.path[0] === 'change' && styles[f.after] === 'removed' && guarded(kind)) reasons.push(`${kindName(kind)} removed (change state became removed)`);
				if (f.path[0] === 'ties' && f.path.length === 3 && f.path[2] === 'enforcement') reasons.push(...enforcementReasons(project, `tie ${f.path[1]}`, f.before, f.after, false));
				if (f.path[0] === 'ties' && f.path.length === 2 && f.change === 'added') reasons.push(...enforcementReasons(project, `tie ${f.path[1]}`, undefined, f.after?.enforcement, true));
			}
			// a data element that arrives with weakly enforced ties is covered by "data element added"
		} else if (d.kind === 'relationship') {
			// a data relationship that states no enforcement has none
			const isData = (rel) => rel?.enforcement !== undefined || dataRelationships.has(rel?.kind);
			if (d.change === 'added' && isData(d.after)) reasons.push(...enforcementReasons(project, 'data relationship', undefined, d.after.enforcement, true));
			for (const f of fields) {
				if (f.path.length === 1 && f.path[0] === 'enforcement') reasons.push(...enforcementReasons(project, 'data relationship', f.before, f.after, f.change === 'added' && !dataRelationships.has(d.before?.kind)));
				// a relationship that becomes a data relationship is a new one
				if (f.path.length === 1 && f.path[0] === 'kind' && dataRelationships.has(f.after) && !dataRelationships.has(f.before)) reasons.push(...enforcementReasons(project, 'data relationship', undefined, d.after?.enforcement, true));
			}
		} else if (d.kind === 'contract') {
			if (d.change === 'removed') reasons.push('contract removed');
			for (const f of fields) {
				if (f.path.length === 1 && f.path[0] === 'change' && styles[f.after] === 'removed') reasons.push('contract removed (change state became removed)');
				if (f.path[0] !== 'clauses' || f.path.length !== 2) continue;
				if (f.path[1] === 'access') reasons.push(`access clause ${f.change}`);
				else if (f.change === 'removed') reasons.push(`clause \`${f.path[1]}\` removed`);
			}
		} else if (d.kind === 'scenario') {
			// one that is gone cannot be delivered as approved; whether a kept one still can is judgment
			if (d.change === 'removed') reasons.push('scenario removed');
		}
		const key = `${d.kind}:${d.id}`;
		differences.push({
			key,
			change: d.change,
			fields: fields.map((f) => ({ path: f.path.join('.'), change: f.change })),
			class: reasons.length ? 're-approval' : 'model-change',
			...(reasons.length && { reasons: [...new Set(reasons)] }),
			recorded: deviations.has(key),
			...(deviations.has(key) && { deviation: deviations.get(key) })
		});
	}

	// catalog, rule and profile files changed that the approved plan does not list
	const paths = [];
	for (const p of changedPaths) {
		const kind = matchAny(p, project.catalog) ? 'catalog' : matchAny(p, project.rules) ? 'rule' : project.profile && matchAny(p, [project.profile]) ? 'profile' : projectPath === p ? 'path' : undefined;
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
		if (key === 'json' || key === 'no-approval') opts[key] = true;
		else if (['model', 'plan', 'ledger', 'project', 'base', 'root', 'code-report', 'diff-report', 'changed-paths'].includes(key)) {
			if (rest[i + 1] === undefined) throw new UsageError(`--${key} needs a value`);
			opts[key] = rest[++i];
		} else throw new UsageError(`unknown option: ${a}`);
	}
	if (!['code', 'approved', 'all'].includes(command)) throw new UsageError('give a command: code, approved or all');
	if (!opts.model) throw new UsageError('--model is required');
	return { command, opts };
}

function readText(path) {
	try {
		return readFileSync(path, 'utf8');
	} catch (e) {
		throw new UsageError(`cannot read ${path}: ${e.code ?? e.message}`);
	}
}

function readJson(path) {
	const text = readText(path);
	try {
		return JSON.parse(text);
	} catch (e) {
		throw new UsageError(`${path} is not JSON: ${e.message}`);
	}
}

const GIT = { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 256 * 1024 * 1024 };
const tryGit = (root, args) => execFileSync('git', ['-C', root, ...args], GIT);
function git(root, args) {
	try {
		return tryGit(root, args);
	} catch (e) {
		throw new UsageError(`git ${args.join(' ')} failed: ${(e.stderr || e.message).trim()}`);
	}
}

/** Run the diagram tool and parse its JSON. It exits non-zero when it reports problems, with the JSON still on stdout. */
function tool(args) {
	let out;
	try {
		out = execFileSync(process.env.C4ISH ?? 'c4ish', args, GIT);
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

/** The real path, so a path through a symlink still sits under the repository root. */
const real = (path) => (existsSync(path) ? realpathSync(path) : path);

const PREMADE = ['code-report', 'diff-report', 'changed-paths'];

function context(opts) {
	if (!existsSync(resolve(opts.model))) throw new UsageError(`no such model: ${opts.model}`);
	const model = real(resolve(opts.model));
	let root = opts.root && real(resolve(opts.root));
	if (!root) {
		try {
			root = real(tryGit(dirname(model), ['rev-parse', '--show-toplevel']).trim());
		} catch {
			throw new UsageError(`${opts.model} is not inside a git repository; pass --root <dir>`);
		}
	}
	const plan = real(resolve(opts.plan ?? join(dirname(model), 'plan.md')));
	const ledger = real(resolve(opts.ledger ?? join(dirname(plan), 'review.md')));
	const projectFile = opts.project && real(resolve(opts.project));
	if (projectFile && !existsSync(projectFile)) throw new UsageError(`no such path file: ${opts.project}`);
	const parsed = existsSync(plan) ? parsePlan(readFileSync(plan, 'utf8')) : { approvals: [], outsideModel: [] };
	const ctx = { model, root, plan, ledger, projectFile, ...parsed };

	// a plan with an approval line is judged by what was approved; anything else is a trial and must say so
	if (ctx.approvals.length) {
		if (opts['no-approval']) throw new UsageError(`--no-approval was given, but ${opts.plan ?? 'the plan'} has an approval line: an approved plan is judged by its approval`);
		const premade = PREMADE.find((k) => opts[k]);
		if (premade) throw new UsageError(`--${premade} is for trials (--no-approval): an approved plan is checked against git and the tool's own output`);
		ctx.approvals = approvalChain(ctx);
		ctx.approved = ctx.approvals.at(-1);
	} else if (!opts['no-approval']) throw new UsageError(`no \`Approved: <date> <commit>\` line in ${ctx.plan}; pass --no-approval to run a trial judged by the working copy`);
	return ctx;
}

const isAncestor = (root, a, b) => {
	try {
		tryGit(root, ['merge-base', '--is-ancestor', a, b]);
		return true;
	} catch {
		return false;
	}
};

/** The plan's approval commits, resolved. Each must be in the history of HEAD, in the order listed. */
function approvalChain(ctx) {
	const out = [];
	for (const a of ctx.approvals) {
		let sha;
		try {
			sha = tryGit(ctx.root, ['rev-parse', '--verify', '--quiet', `${a.commit}^{commit}`]).trim();
		} catch {
			throw new UsageError(`the plan's \`${a.kind}:\` line names ${a.commit}, which is not a commit in this repository`);
		}
		if (!isAncestor(ctx.root, sha, 'HEAD')) throw new UsageError(`the plan's \`${a.kind}:\` line names ${a.commit}, which is not in the history of HEAD`);
		const before = out.at(-1);
		if (before && !isAncestor(ctx.root, before.sha, sha)) throw new UsageError(`the plan's approval lines are out of order: ${a.commit} does not come after ${before.commit}`);
		out.push({ ...a, sha });
	}
	return out;
}

const inside = (ctx, path) => {
	const rel = relative(ctx.root, path);
	return rel.startsWith('..') ? undefined : rel;
};

/** A file as the approved commit has it. There is no fallback to the working copy: the build writes that. */
function approvedText(ctx, path, what) {
	const rel = inside(ctx, path);
	if (rel === undefined) throw new UsageError(`${what} must be inside the repository: ${path}`);
	try {
		return tryGit(ctx.root, ['show', `${ctx.approved.sha}:${rel}`]);
	} catch (e) {
		throw new UsageError(`cannot read ${rel} at ${ctx.approved.commit}, the commit the plan was approved at; ${what} must be committed before approval: ${(e.stderr || e.message).trim()}`);
	}
}

function approvedJson(ctx, path, what) {
	const text = approvedText(ctx, path, what);
	try {
		return JSON.parse(text);
	} catch (e) {
		throw new UsageError(`${inside(ctx, path)} at ${ctx.approved.commit} is not JSON: ${e.message}`);
	}
}

/** The profile as the tool reads it, default merged in. No path: the tool's default profile. */
function resolvedProfile(path) {
	let profile;
	try {
		profile = tool(path ? ['profile', path] : ['profile']);
	} catch (e) {
		if (e instanceof UsageError) throw new UsageError(`${e.message}\n(this check needs a c4ish that has the \`profile\` command)`);
		throw e;
	}
	if (!profile || typeof profile.elementKinds !== 'object') throw new UsageError('`c4ish profile` did not print a profile: this c4ish is too old for this check');
	return profile;
}

/** `resolvedProfile` of a profile's text, which is not a file in the working copy. */
function resolvedProfileText(text) {
	const dir = mkdtempSync(join(tmpdir(), 'model-check-profile-'));
	try {
		writeFileSync(join(dir, 'profile.c4ish.json'), text);
		return resolvedProfile(join(dir, 'profile.c4ish.json'));
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
}

/**
 * What the check is judged by. For an approved plan: the path file, the profile (change states,
 * data relationship kinds, the category of each element kind) and the plan's "Changes outside the
 * model" list, all as the latest approval commit has them. For a trial: the working copy. The
 * working copy's profile is used only to run the tool and to know which patterns are now catalogued.
 */
function settings(ctx) {
	if (ctx.settings) return ctx.settings;
	let project = {};
	let projectPath;
	if (ctx.projectFile) {
		projectPath = inside(ctx, ctx.projectFile);
		project = ctx.approved ? approvedJson(ctx, ctx.projectFile, 'the path file') : readJson(ctx.projectFile);
	}
	const profilePath = project.profile ? join(ctx.root, project.profile) : undefined;
	if (project.kinds) throw new UsageError('the path file has `kinds`, which this check no longer reads: give each element kind a `category` in the profile instead');
	const profile = profilePath && existsSync(profilePath) ? readJson(profilePath) : undefined;
	const judged = ctx.approved && profilePath ? resolvedProfileText(approvedText(ctx, profilePath, 'the profile')) : resolvedProfile(profile && profilePath);
	const outsideModel = ctx.approved ? parsePlan(approvedText(ctx, ctx.plan, 'the plan')).outsideModel : ctx.outsideModel;
	return (ctx.settings = {
		project,
		projectPath,
		outsideModel,
		styles: changeStyles(judged),
		dataRelationships: dataRelationshipKinds(judged),
		categories: kindCategories(judged),
		profilePatterns: new Set(Array.isArray(profile?.patterns) ? profile.patterns.map((p) => p.id) : Object.keys(profile?.patterns ?? {})),
		toolArgs: profilePath ? ['--profile', profilePath] : []
	});
}

function runCode(ctx, opts) {
	const first = ctx.approvals.find((a) => a.kind === 'Approved') ?? ctx.approvals[0];
	const base = opts.base ?? first?.sha;
	const given = opts['code-report'];
	if (!given && !base) throw new UsageError('no base commit: pass --base');
	// a later baseline would hide what the build did
	if (first && opts.base && !isAncestor(ctx.root, opts.base, first.sha)) throw new UsageError(`--base ${opts.base} is not the first approval commit (${first.commit}) or an earlier one`);
	const { project, styles, categories, outsideModel, toolArgs } = settings(ctx);
	const report = given ? readJson(resolve(given)) : tool(['code', ctx.model, '--base', base, '--root', ctx.root, '--json', ...toolArgs]);
	const read = (p) => {
		try {
			return readFileSync(join(ctx.root, p), 'utf8');
		} catch {
			return undefined;
		}
	};
	return { base: report.base ?? base, ...checkCode(readJson(ctx.model), report, { styles, categories, project, outsideModel, read }) };
}

function runApproved(ctx, opts) {
	const given = opts['diff-report'];
	if (!ctx.approved && !given) throw new UsageError('a trial of `approved` (--no-approval) has no commit to compare with: pass --diff-report');
	// without it nothing says where the catalog, the rules and the profile are, so nothing guards them
	if (!ctx.projectFile) throw new UsageError('`approved` needs the project path file (--project): it names the profile, the catalog and the rules');
	const { project, projectPath, styles, categories, dataRelationships, profilePatterns, outsideModel, toolArgs } = settings(ctx);
	const diff = given ? readJson(resolve(given)) : tool(['diff', ctx.model, '--base', ctx.approved.sha, '--only', 'structure', '--json', ...toolArgs]);
	let changedPaths = [];
	if (opts['changed-paths']) changedPaths = readText(resolve(opts['changed-paths'])).split(/\r?\n/).filter(Boolean);
	else if (ctx.approved) {
		// -z: names as they are; --no-renames: a moved file is one removed and one added
		const list = (args) => git(ctx.root, args).split('\0').filter(Boolean);
		changedPaths = [...new Set([...list(['diff', '--name-only', '--no-renames', '-z', ctx.approved.sha]), ...list(['ls-files', '--others', '--exclude-standard', '-z'])])];
	}
	const deviations = existsSync(ctx.ledger) ? parseLedger(readFileSync(ctx.ledger, 'utf8')) : new Map();
	const { sha: _sha, ...against } = ctx.approved ?? {};
	return { ...(ctx.approved && { against }), ...checkApproved(diff, { styles, categories, project, projectPath, dataRelationships, profilePatterns, deviations, changedPaths, outsideModel }) };
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
		const checks = {};
		if (parsed.command !== 'approved') checks.code = runCode(ctx, parsed.opts);
		if (parsed.command !== 'code') checks.approved = runApproved(ctx, parsed.opts);
		// the approval lines the verdict rests on: the build must not have written any of them
		const approvals = ctx.approvals.map(({ kind, date, commit }) => ({ kind, date, commit }));
		if (parsed.opts.json) console.log(JSON.stringify({ ...(ctx.approved ? { approvals } : { trial: true }), ...checks }, null, 2));
		else {
			if (ctx.approved) console.log(`judged by the plan as approved: ${approvals.map((a) => `${a.kind} ${a.date} ${a.commit.slice(0, 10)}`).join(' → ')}`);
			else console.log('TRIAL (--no-approval): judged by the working copy, not by an approved plan');
			if (checks.code) printCode(checks.code);
			if (checks.approved) printApproved(checks.approved);
		}
		return Object.values(checks).every((r) => r.ok) ? 0 : 1;
	} catch (e) {
		// never exit 1 for anything but a verdict: an error here is not "the check failed"
		console.error(`model-check: ${e instanceof UsageError ? e.message : (e.stack ?? e)}`);
		return 2;
	}
}

// Installed copies are reached through symlinks, so compare real paths: a run that silently did
// nothing would read as a pass.
const invoked = () => {
	try {
		return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
	} catch {
		return false;
	}
};
if (process.argv[1] && invoked()) process.exitCode = main(process.argv.slice(2));
