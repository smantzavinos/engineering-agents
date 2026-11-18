// Tests for tools/model-check.mjs. Run: node --test tools/model-check.test.mjs
// The last group builds a small git repository and runs the real diagram tool; it is skipped
// when `c4ish` is not on PATH.

import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, it } from 'node:test';
import { changeStyles, checkApproved, checkCode, expectedTag, firstComment, globToRegExp, matchAny, parseLedger, parsePlan, parseTag, tagMismatches } from './model-check.mjs';

const SCRIPT = join(dirname(fileURLToPath(import.meta.url)), 'model-check.mjs');

describe('globs', () => {
	it('** crosses directories, * stays in one segment', () => {
		assert.ok(matchAny('docs/a/b.md', ['docs/**']));
		assert.ok(matchAny('src/a/b.test.ts', ['**/*.test.ts']));
		assert.ok(matchAny('b.test.ts', ['**/*.test.ts']));
		assert.ok(!matchAny('src/a/b.ts', ['src/*.ts']));
		assert.ok(matchAny('src/b.ts', ['src/*.ts']));
		assert.ok(!globToRegExp('a.ts').test('aXts'));
	});
});

describe('plan.md', () => {
	const plan = ['# Plan', 'Approved: 2026-01-02 abc1234', '## Changes outside the model', '- `docs/patterns/api.md`: new entry', '### Config', '- `config/*.json`', '## Risks', '- `not/this.md`', '- **Re-approved:** 2026-01-05 `def5678` enforcement'].join('\n');

	it('reads approvals in order, and the paths under Changes outside the model', () => {
		const p = parsePlan(plan);
		assert.deepEqual(p.approvals, [
			{ kind: 'Approved', date: '2026-01-02', commit: 'abc1234' },
			{ kind: 'Re-approved', date: '2026-01-05', commit: 'def5678' }
		]);
		assert.deepEqual(p.outsideModel, ['docs/patterns/api.md', 'config/*.json']);
	});

	it('reads deviations from the ledger by key', () => {
		const d = parseLedger(['## Review 1', '- `element:x` not a deviation', '### Deviations', '- `element:svc` flipped to modified; the guard moved', '* `relationship:w`  rerouted', 'text', '## Gates', '- `element:late` no'].join('\n'));
		assert.deepEqual([...d], [
			['element:svc', 'flipped to modified; the guard moved'],
			['relationship:w', 'rerouted']
		]);
	});
});

describe('tags', () => {
	it('parses each form', () => {
		assert.equal(parseTag('// nothing here'), null);
		assert.deepEqual(parseTag('// @pattern api/read-query'), { raw: '@pattern api/read-query', pattern: 'api/read-query', bespoke: false, partial: false, also: [] });
		assert.deepEqual(parseTag('/* @pattern api/guard partial: no audit row */'), { raw: '@pattern api/guard partial: no audit row', pattern: 'api/guard', bespoke: false, partial: true, also: [] });
		assert.deepEqual(parseTag('<!-- @pattern bespoke: one-off import ; also web/page, api/guard -->'), { raw: '@pattern bespoke: one-off import ; also web/page, api/guard', bespoke: true, partial: false, also: ['web/page', 'api/guard'] });
		assert.deepEqual(parseTag(' * @pattern data/table; also data/join-table').also, ['data/join-table']);
	});

	it('rejects what is not a form', () => {
		assert.match(parseTag('// @pattern').error, /not a tag form/);
		assert.match(parseTag('// @pattern a/b and more words').error, /not a tag form/);
		assert.match(parseTag('// @pattern bespoke:').error, /must say what/);
		assert.match(parseTag('// @pattern a/b partial:').error, /must say what differs/);
		assert.match(parseTag('// @pattern a/b\n// @pattern c/d').error, /more than one/);
	});

	it('finds the first comment of a file', () => {
		assert.deepEqual(firstComment('#!/usr/bin/env node\n\n// @pattern a/b\n// more\nconst x = 1;\n// later'), { start: 3, end: 4, text: '// @pattern a/b\n// more' });
		assert.equal(firstComment('<script lang="ts">\n\t// @pattern web/page\n\tlet a;\n</script>').text.trim(), '// @pattern web/page');
		assert.equal(firstComment('<!--\n  @pattern web/page\n-->\n<div/>').end, 3);
		assert.equal(firstComment('const x = 1;\n// @pattern a/b'), undefined);
	});

	const model = {
		elements: [
			{ id: 'box', kind: 'container' },
			{ id: 'full', pattern: 'api/mutation', patterns: ['api/mutation', 'api/guard'] },
			{ id: 'part', pattern: 'api/mutation', patternFit: 'partial', parts: [{ title: 'Guard', pattern: 'api/guard' }, { title: 'Plain' }] },
			{ id: 'one', pattern: null }
		]
	};

	it('says what the model expects', () => {
		assert.deepEqual(expectedTag(model, { element: 'box' }), { none: true });
		assert.deepEqual(expectedTag(model, { element: 'full' }), { pattern: 'api/mutation', bespoke: false, partial: false, also: ['api/guard'] });
		assert.equal(expectedTag(model, { element: 'part' }).partial, true);
		assert.deepEqual(expectedTag(model, { element: 'part', part: 'Guard' }), { pattern: 'api/guard', bespoke: false, partial: false, also: [] });
		// a part with no pattern of its own carries the element's tag
		assert.equal(expectedTag(model, { element: 'part', part: 'Plain' }).pattern, 'api/mutation');
		assert.equal(expectedTag(model, { element: 'one' }).bespoke, true);
	});

	it('a tag agrees only when pattern, fit, bespoke and further patterns all match', () => {
		const full = expectedTag(model, { element: 'full' });
		assert.deepEqual(tagMismatches(parseTag('// @pattern api/mutation; also api/guard'), full), []);
		assert.match(tagMismatches(null, full)[0], /no @pattern tag/);
		assert.match(tagMismatches(parseTag('// @pattern api/read-query; also api/guard'), full)[0], /tagged `api\/read-query` but the model says `api\/mutation`/);
		assert.match(tagMismatches(parseTag('// @pattern api/mutation'), full)[0], /further patterns \[\] but the model lists \[api\/guard\]/);
		assert.match(tagMismatches(parseTag('// @pattern api/mutation partial: x; also api/guard'), full)[0], /tagged partial/);
		assert.match(tagMismatches(parseTag('// @pattern api/mutation'), expectedTag(model, { element: 'part' }))[0], /not tagged partial/);
		assert.match(tagMismatches(parseTag('// @pattern bespoke: x; also api/guard'), full)[0], /tagged bespoke/);
		assert.match(tagMismatches(parseTag('// @pattern api/mutation'), expectedTag(model, { element: 'one' }))[0], /marks it bespoke/);
		assert.deepEqual(tagMismatches(parseTag('// @pattern bespoke: importer'), expectedTag(model, { element: 'one' })), []);
		assert.match(tagMismatches(parseTag('// @pattern a/b'), { none: true })[0], /gives its element no pattern/);
		assert.deepEqual(tagMismatches(null, { none: true }), []);
	});
});

/* ------------------------------------------------------------------------- */

const named = (ref, owner, delta, extra = {}) => ({
	ref,
	owners: [owner],
	head: delta === 'removed' || delta === 'missing' ? { status: 'missing-name' } : { status: 'resolved', extents: [{ kind: 'function', start: 2, end: 4, comment: { start: 1, end: 1 } }] },
	base: delta === 'added' || delta === 'missing' ? { status: 'missing-name' } : { status: 'resolved' },
	delta,
	...extra
});
const files = (texts) => (p) => texts[p];
const el = (id, change, pattern, extra = {}) => ({ id, kind: 'component', title: id, change, ...(pattern !== undefined && { pattern }), ...extra });
const messages = (r) => r.failures.map((f) => `${f.where}: ${f.message}`);

describe('model-to-code', () => {
	const tagged = (id) => `// @pattern ${id}\nexport function f() {\n\treturn 1;\n}\n`;

	it('passes when every change state matches the code and the tags agree', () => {
		const model = { elements: [el('n', 'new', 'api/mutation'), el('m', 'modified', 'api/read-query'), el('r', 'reused', 'api/guard'), el('x', 'removed', 'api/guard'), el('box', 'modified')] };
		const report = {
			references: [named('n.ts#f', { element: 'n' }, 'added'), named('m.ts#f', { element: 'm' }, 'modified'), named('r.ts#f', { element: 'r' }, 'unchanged'), named('x.ts#f', { element: 'x' }, 'removed')],
			files: []
		};
		const r = checkCode(model, report, { read: files({ 'n.ts': tagged('api/mutation'), 'm.ts': tagged('api/read-query'), 'r.ts': 'export function f() {}\n' }) });
		assert.deepEqual(messages(r), []);
		assert.equal(r.ok, true);
		assert.deepEqual(r.elements.map((e) => `${e.id}:${e.references}`), ['n:1', 'm:1', 'r:1', 'x:1', 'box:0']);
	});

	it('a new element whose code existed at the base fails', () => {
		const r = checkCode({ elements: [el('n', 'new', 'a/b')] }, { references: [named('n.ts#f', { element: 'n' }, 'modified')] }, { read: files({ 'n.ts': tagged('a/b') }) });
		assert.deepEqual(messages(r), ['element n: is new, but `n.ts#f` is modified: it existed at the base']);
	});

	it('a modified element fails when nothing changed, and passes when changed only through what it is built from', () => {
		const model = { elements: [el('m', 'modified', 'a/b')] };
		const still = checkCode(model, { references: [named('m.ts#f', { element: 'm' }, 'unchanged')] });
		assert.deepEqual(messages(still), ['element m: is modified, but none of its references changed']);
		const via = checkCode(model, { references: [named('m.ts#f', { element: 'm' }, 'unchanged', { changedThrough: ['shared'] })] });
		assert.equal(via.ok, true);
	});

	it('a modified element fails when a reference no longer resolves, with the hint', () => {
		const r = checkCode({ elements: [el('m', 'modified', 'a/b')] }, { references: [named('m.ts#f', { element: 'm' }, 'removed', { hints: [{ kind: 'renamed', ref: 'm.ts#g' }] })] });
		assert.deepEqual(messages(r), ['element m: is modified, but `m.ts#f` does not resolve (missing-name); it may now be `m.ts#g` (renamed)', 'element m: is modified, but none of its references changed']);
	});

	it('a removed element whose code is still there fails', () => {
		const r = checkCode({ elements: [el('x', 'removed')] }, { references: [named('x.ts#f', { element: 'x' }, 'unchanged')] });
		assert.deepEqual(messages(r), ['element x: is removed, but `x.ts#f` is still there (unchanged)']);
	});

	it('a reused element that changed, directly or through a shared block, fails', () => {
		const model = { elements: [el('r', 'reused', 'a/b')] };
		assert.match(messages(checkCode(model, { references: [named('r.ts#f', { element: 'r' }, 'modified')] }))[0], /is reused, but `r.ts#f` is modified: that makes it modified, a model change/);
		assert.match(messages(checkCode(model, { references: [named('r.ts#f', { element: 'r' }, 'unchanged', { changedThrough: ['base'] })] }))[0], /unchanged \(changed through base\)/);
		// a changed comment alone (a retag) does not make it modified
		assert.equal(checkCode(model, { references: [named('r.ts#f', { element: 'r' }, 'unchanged', { commentChanged: true })] }).ok, true);
	});

	it('a new or modified element with a pattern and no reference fails; a container does not', () => {
		const r = checkCode({ elements: [el('n', 'new', 'a/b'), el('one', 'modified', null), el('box', 'new'), el('r', 'reused', 'a/b')] }, { references: [] });
		assert.deepEqual(messages(r), ['element n: is new and has a pattern, but no code reference', 'element one: is modified and has a pattern, but no code reference']);
	});

	it('changed code must carry a tag that agrees; untouched code may be untagged', () => {
		const model = { elements: [el('m', 'modified', 'a/b')] };
		const report = { references: [named('m.ts#f', { element: 'm' }, 'modified'), named('m.ts#g', { element: 'm' }, 'unchanged'), named('m.ts#h', { element: 'm' }, 'unchanged')] };
		report.references[1].head.extents = [{ kind: 'function', start: 6, end: 6 }];
		report.references[2].head.extents = [{ kind: 'function', start: 8, end: 8, comment: { start: 7, end: 7 } }];
		const text = '// plain comment\nexport function f() {\n\treturn 1;\n}\n\nexport function g() {}\n// @pattern c/d\nexport function h() {}\n';
		assert.deepEqual(messages(checkCode(model, report, { read: files({ 'm.ts': text }) })), ['element m: `m.ts#f` has no @pattern tag', 'element m: `m.ts#h` is tagged `c/d` but the model says `a/b`']);
	});

	it('a part with its own pattern is checked against the part', () => {
		const model = { elements: [el('n', 'new', 'a/b', { parts: [{ title: 'Guard', pattern: 'a/guard' }] })] };
		const report = { references: [named('n.ts#f', { element: 'n', part: 'Guard' }, 'added')] };
		assert.deepEqual(messages(checkCode(model, report, { read: files({ 'n.ts': tagged('a/b') }) })), ['element n: `n.ts#f` (part "Guard") is tagged `a/b` but the model says `a/guard`']);
		assert.equal(checkCode(model, report, { read: files({ 'n.ts': tagged('a/guard') }) }).ok, true);
	});

	it('a whole-file reference is tagged in the first comment; a file type with no comments is skipped', () => {
		const whole = (ref, id) => ({ ref, owners: [{ element: id }], head: { status: 'resolved', extents: [{ kind: 'file', start: 1, end: 3 }] }, base: { status: 'missing-file' }, delta: 'added' });
		const model = { elements: [el('page', 'new', 'web/page'), el('cfg', 'new', 'a/b')] };
		const report = { references: [whole('Page.html', 'page'), whole('cfg.json', 'cfg')] };
		assert.equal(checkCode(model, report, { read: files({ 'Page.html': '<!-- @pattern web/page -->\n<div/>\n', 'cfg.json': '{}' }) }).ok, true);
		assert.deepEqual(messages(checkCode(model, report, { read: files({ 'Page.html': '<div/>\n<!-- @pattern web/page -->\n', 'cfg.json': '{}' }) })), ['element page: `Page.html` has no @pattern tag']);
	});

	it('a reference with a problem fails', () => {
		const r = checkCode({ elements: [el('n', 'new', 'a/b')] }, { references: [{ ref: 'n.ts#f', owners: [{ element: 'n' }], head: { status: 'ambiguous' }, problem: 'n.ts#f names 2 definitions' }] });
		assert.deepEqual(messages(r), ['n.ts#f: n.ts#f names 2 definitions']);
	});

	it('a tag added on code no element references fails; one on a referenced definition does not', () => {
		const model = { elements: [el('n', 'new', 'a/b')] };
		const text = `${tagged('a/b')}\n// @pattern a/b\nexport function stray() {}\n`;
		const report = {
			references: [named('n.ts#f', { element: 'n' }, 'added')],
			files: [{ path: 'n.ts', status: 'added', base: [], head: [{ start: 1, end: 1, refs: [{ ref: 'n.ts#f', in: 'comment' }] }, { start: 2, end: 4, refs: [{ ref: 'n.ts#f', in: 'body' }] }, { start: 5, end: 7, refs: [] }] }]
		};
		const r = checkCode(model, report, { read: files({ 'n.ts': text }) });
		assert.deepEqual(messages(r), ['n.ts:6: a @pattern tag was added or changed here, but no element references this definition: `// @pattern a/b`']);
		assert.deepEqual(r.unaccounted.runs, [{ path: 'n.ts', side: 'head', start: 5, end: 7, lines: 3 }]);
	});

	it('lists changed lines no reference owns, leaves out the project paths, and marks files the plan lists', () => {
		const report = {
			references: [],
			files: [
				{ path: 'src/glue.ts', status: 'modified', base: [{ start: 9, end: 10, refs: [] }], head: [{ start: 3, end: 5, refs: [] }, { start: 8, end: 8, refs: [{ ref: 'src/glue.ts#f', in: 'body' }] }] },
				{ path: 'src/glue.test.ts', status: 'added', base: [], head: [{ start: 1, end: 40, refs: [] }] },
				{ path: 'migrations/001.sql', status: 'added', base: [], head: [{ start: 1, end: 6, refs: [] }] },
				{ path: 'logo.png', status: 'added', binary: true, base: [], head: [] }
			]
		};
		const r = checkCode({ elements: [] }, report, { project: { leftOut: ['**/*.test.ts'] }, outsideModel: ['migrations/**'] });
		assert.equal(r.ok, true);
		assert.deepEqual(r.unaccounted, {
			runs: [
				{ path: 'src/glue.ts', side: 'head', start: 3, end: 5, lines: 3 },
				{ path: 'src/glue.ts', side: 'base', start: 9, end: 10, lines: 2 },
				{ path: 'migrations/001.sql', side: 'head', start: 1, end: 6, lines: 6, outsideModel: true },
				{ path: 'logo.png', binary: true }
			],
			lines: 11,
			outsideModelLines: 6
		});
	});

	it('uses the profile for change states it renames', () => {
		const styles = changeStyles({ changeStates: { fresh: { label: 'Fresh', style: 'new' } } });
		assert.equal(styles.fresh, 'new');
		assert.equal(styles.removed, 'removed');
		const r = checkCode({ elements: [el('n', 'fresh', 'a/b')] }, { references: [named('n.ts#f', { element: 'n' }, 'unchanged')] }, { styles });
		assert.match(messages(r)[0], /is new, but/);
	});
});

/* ------------------------------------------------------------------------- */

const S = 'structure';
const diffOf = (...differences) => ({ differences: differences.map((d) => ({ aspects: [S], ...d, fields: d.fields?.map((f) => ({ aspect: S, ...f })) })) });
const project = { kinds: { data: ['data'], container: ['container'], product: ['feature'] }, catalog: ['docs/patterns/**'], rules: ['rules/**'], profile: 'docs/patterns/profile.c4ish.json' };
const classes = (r) => r.differences.map((d) => `${d.key} ${d.class}${d.reasons ? `: ${d.reasons.join('; ')}` : ''}`);

describe('approved versus shipped', () => {
	it('passes with no difference, and with model changes the ledger records', () => {
		assert.equal(checkApproved(diffOf(), { project }).verdict, 'pass');
		const diff = diffOf({ kind: 'element', id: 'svc', change: 'changed', before: { kind: 'component' }, after: { kind: 'component' }, fields: [{ path: ['change'], change: 'changed', before: 'reused', after: 'modified' }] });
		const r = checkApproved(diff, { project, deviations: new Map([['element:svc', 'the guard moved in']]) });
		assert.equal(r.verdict, 'pass');
		assert.deepEqual(r.differences, [{ key: 'element:svc', change: 'changed', fields: [{ path: 'change', change: 'changed' }], class: 'model-change', recorded: true, deviation: 'the guard moved in' }]);
	});

	it('fails on a model change the ledger does not record, and notes a record with no difference', () => {
		const diff = diffOf({ kind: 'element', id: 'job', change: 'added', after: { kind: 'component' } });
		const r = checkApproved(diff, { project, deviations: new Map([['element:other', 'x']]) });
		assert.equal(r.verdict, 'fail');
		assert.deepEqual(classes(r), ['element:job model-change']);
		assert.deepEqual(r.stale, ['element:other']);
	});

	it('a data element, container or product element added or removed needs re-approval, recorded or not', () => {
		const diff = diffOf(
			{ kind: 'element', id: 't', change: 'added', after: { kind: 'data' } },
			{ kind: 'element', id: 'c', change: 'removed', before: { kind: 'container' } },
			{ kind: 'element', id: 'p', change: 'added', after: { kind: 'feature' } },
			{ kind: 'element', id: 'gone', change: 'changed', before: { kind: 'component' }, after: { kind: 'component' }, fields: [{ path: ['change'], change: 'changed', before: 'modified', after: 'removed' }] }
		);
		const r = checkApproved(diff, { project, deviations: new Map([['element:t', 'needed']]) });
		assert.equal(r.verdict, 're-approval');
		assert.deepEqual(classes(r), ['element:t re-approval: data element added', 'element:c re-approval: container removed', 'element:p re-approval: product element added', 'element:gone re-approval: change state became removed']);
	});

	it('enforcement moved down needs re-approval; moved up is a model change', () => {
		const rel = (id, before, after) => ({ kind: 'relationship', id, change: 'changed', fields: [{ path: ['enforcement'], change: 'changed', before, after }] });
		const r = checkApproved(diffOf(rel('down', 'platform', 'our-code'), rel('up', 'nothing', 'platform'), rel('derived', 'platform-correlated', 'derived'), rel('fromDerived', 'derived', 'our-code'), rel('odd', 'platform', 'custom')), { project });
		assert.deepEqual(classes(r), [
			'relationship:down re-approval: enforcement on data relationship moved down: `platform` → `our-code`',
			'relationship:up model-change',
			'relationship:derived re-approval: enforcement on data relationship moved down: `platform-correlated` → `derived`',
			'relationship:fromDerived re-approval: enforcement on data relationship moved down: `derived` → `our-code`',
			'relationship:odd re-approval: enforcement on data relationship changed and this check cannot rank `custom`'
		]);
	});

	it("maps the process's enforcement levels to the project's ids", () => {
		const mapped = { ...project, enforcement: { platform: 'db', 'platform-correlated': 'db-correlated' } };
		const diff = diffOf({ kind: 'relationship', id: 'w', change: 'changed', fields: [{ path: ['enforcement'], change: 'changed', before: 'db', after: 'db-correlated' }] });
		assert.deepEqual(classes(checkApproved(diff, { project: mapped })), ['relationship:w re-approval: enforcement on data relationship moved down: `db` → `db-correlated`']);
		assert.match(classes(checkApproved(diff, { project }))[0], /cannot rank/);
	});

	it('a new data relationship or tie enforced by our-code or nothing needs re-approval', () => {
		const diff = diffOf(
			{ kind: 'relationship', id: 'weak', change: 'added', after: { enforcement: 'nothing' } },
			{ kind: 'relationship', id: 'strong', change: 'added', after: { enforcement: 'platform' } },
			{ kind: 'relationship', id: 'call', change: 'added', after: { kind: 'calls' } },
			{
				kind: 'element',
				id: 'tbl',
				change: 'changed',
				before: { kind: 'data' },
				after: { kind: 'data' },
				fields: [
					{ path: ['ties', 'a~c'], change: 'added', after: { fields: ['a', 'c'], enforcement: 'our-code' } },
					{ path: ['ties', 'a~b', 'enforcement'], change: 'changed', before: 'platform', after: 'nothing' },
					{ path: ['fields', 'c'], change: 'added', after: { id: 'c' } }
				]
			}
		);
		assert.deepEqual(classes(checkApproved(diff, { project })), [
			'relationship:weak re-approval: new data relationship enforced by `nothing`',
			'relationship:strong model-change',
			'relationship:call model-change',
			'element:tbl re-approval: new tie a~c enforced by `our-code`; enforcement on tie a~b moved down: `platform` → `nothing`'
		]);
	});

	it('a contract removed, a clause removed, or the access clause touched needs re-approval; other clauses are model changes', () => {
		const clause = (name, change) => ({ path: ['clauses', name], change });
		const diff = diffOf(
			{ kind: 'contract', id: 'gone', change: 'removed', before: {} },
			{ kind: 'contract', id: 'a', change: 'changed', fields: [clause('access', 'changed')] },
			{ kind: 'contract', id: 'b', change: 'changed', fields: [clause('limits', 'removed'), clause('extra', 'added')] },
			{ kind: 'contract', id: 'c', change: 'changed', fields: [clause('limits', 'changed'), clause('extra', 'added')] },
			{ kind: 'contract', id: 'new', change: 'added', after: {} }
		);
		assert.deepEqual(classes(checkApproved(diff, { project })), ['contract:gone re-approval: contract removed', 'contract:a re-approval: access clause changed', 'contract:b re-approval: clause `limits` removed', 'contract:c model-change', 'contract:new model-change']);
	});

	it('drops a proposed pattern that the profile now holds, and keeps one it does not', () => {
		const diff = diffOf({ kind: 'pattern', id: 'api/batch', change: 'removed' }, { kind: 'pattern', id: 'api/other', change: 'removed' });
		assert.deepEqual(classes(checkApproved(diff, { project, profilePatterns: new Set(['api/batch']) })), ['pattern:api/other model-change']);
	});

	it('ignores differences that are not structure', () => {
		const diff = { differences: [{ kind: 'element', id: 'e', change: 'changed', aspects: ['text'], fields: [{ path: ['title'], aspect: 'text', change: 'changed' }] }] };
		assert.deepEqual(checkApproved(diff, { project }).differences, []);
	});

	it('a catalog, rule or profile file the approved plan does not list needs re-approval', () => {
		const changedPaths = ['src/a.ts', 'docs/patterns/api.md', 'docs/patterns/web.md', 'rules/guard.yml', 'docs/patterns/profile.c4ish.json'];
		const r = checkApproved(diffOf(), { project, changedPaths, outsideModel: ['docs/patterns/api.md', 'docs/patterns/profile.c4ish.json'] });
		assert.equal(r.verdict, 're-approval');
		assert.deepEqual(r.paths, [
			{ path: 'docs/patterns/web.md', kind: 'catalog' },
			{ path: 'rules/guard.yml', kind: 'rule' }
		]);
		assert.equal(checkApproved(diffOf(), { project, changedPaths, outsideModel: ['docs/patterns/**', 'rules/guard.yml'] }).verdict, 'pass');
	});
});

/* ------------------------------------------------------------------------- */

const hasTool = spawnSync(process.env.C4ISH ?? 'c4ish', ['--version'], { encoding: 'utf8' }).status === 0;

describe('against a real repository', { skip: hasTool ? false : 'c4ish is not on PATH' }, () => {
	const run = (dir, ...args) => spawnSync(process.execPath, [SCRIPT, ...args], { cwd: dir, encoding: 'utf8' });
	const git = (dir, ...args) => execFileSync('git', ['-C', dir, '-c', 'user.name=t', '-c', 'user.email=t@example.com', '-c', 'commit.gpgsign=false', ...args], { encoding: 'utf8' }).trim();
	const put = (dir, path, text) => {
		mkdirSync(dirname(join(dir, path)), { recursive: true });
		writeFileSync(join(dir, path), text);
	};

	/** The base: four definitions and a model that claims the wrong thing about each. */
	function repository() {
		const dir = mkdtempSync(join(tmpdir(), 'model-check-'));
		git(dir, 'init', '-q');
		put(dir, 'src/budget.ts', 'export function meter(n: number) {\n\treturn n;\n}\n');
		put(dir, 'src/list.ts', 'export function owners() {\n\treturn [];\n}\n');
		put(dir, 'src/cards.ts', 'export function cards() {\n\treturn [];\n}\n');
		put(dir, 'src/old.ts', 'export function collector() {\n\treturn [];\n}\n\nexport function shared() {\n\treturn 1;\n}\n');
		const model = {
			schemaVersion: 1,
			title: 'Paged reads',
			views: [{ id: 'eng', kind: 'engineering', title: 'Paged reads' }],
			elements: [
				{ id: 'api', kind: 'container', title: 'API', change: 'modified' },
				{ id: 'page', kind: 'component', parent: 'api', title: 'Page', change: 'new', pattern: 'api/read-query', code: ['src/page.ts#page'] },
				{ id: 'budget', kind: 'component', parent: 'api', title: 'Budget', change: 'reused', pattern: 'api/guard', code: ['src/budget.ts#meter'] },
				{ id: 'owners', kind: 'component', parent: 'api', title: 'Owners', change: 'new', pattern: 'api/read-query', code: ['src/list.ts#owners'] },
				{ id: 'cards', kind: 'component', parent: 'api', title: 'Cards', change: 'modified', pattern: 'api/read-query', code: ['src/cards.ts#cards'] },
				{ id: 'old', kind: 'component', parent: 'api', title: 'Collector', change: 'removed', code: ['src/old.ts#collector'] },
				{ id: 'items', kind: 'data', title: 'items', change: 'reused', pattern: 'data/table' }
			],
			relationships: [
				{ id: 'read', from: 'page', to: 'items', kind: 'reads', enforcement: 'platform', change: 'new' },
				{ id: 'check', from: 'page', to: 'budget', kind: 'calls', change: 'new' }
			]
		};
		put(dir, 'plans/p/model.c4ish.json', JSON.stringify(model, null, '\t'));
		put(dir, 'plans/p/plan.md', '# Plan\n\n## Changes outside the model\n- `migrations/001.sql`\n');
		put(dir, 'project.json', JSON.stringify({ leftOut: ['plans/**', '**/*.test.ts', 'project.json'], kinds: { data: ['data'], container: ['container'] } }));
		git(dir, 'add', '-A');
		git(dir, 'commit', '-q', '-m', 'approved plan');
		const approved = git(dir, 'rev-parse', 'HEAD');
		put(dir, 'plans/p/plan.md', `# Plan\n\nApproved: 2026-01-02 ${approved}\n\n## Changes outside the model\n- \`migrations/001.sql\`\n`);
		// the build: a new tagged query, a change to the "reused" budget, glue, a migration, a test
		put(dir, 'src/page.ts', '// @pattern api/read-query\nexport function page() {\n\treturn [];\n}\n');
		put(dir, 'src/budget.ts', 'export function meter(n: number) {\n\treturn n + 1;\n}\n');
		put(dir, 'src/glue.ts', 'export const glue = 1;\n');
		put(dir, 'migrations/001.sql', 'select 1;\n');
		put(dir, 'src/page.test.ts', 'export {};\n');
		return { dir, model, args: ['--model', 'plans/p/model.c4ish.json', '--project', 'project.json'] };
	}
	const rewrite = (dir, model, change) => {
		const next = structuredClone(model);
		change(next);
		put(dir, 'plans/p/model.c4ish.json', JSON.stringify(next, null, '\t'));
		return next;
	};

	it('finds each wrong claim, then passes once the model and the code agree', () => {
		const { dir, model, args } = repository();
		try {
			const bad = run(dir, 'code', ...args, '--json');
			assert.equal(bad.status, 1, bad.stderr);
			const result = JSON.parse(bad.stdout).code;
			assert.deepEqual(
				result.failures.map((f) => `${f.where}: ${f.message}`),
				[
					'element budget: is reused, but `src/budget.ts#meter` is modified: that makes it modified, a model change',
					'element owners: is new, but `src/list.ts#owners` is unchanged: it existed at the base',
					'element cards: is modified, but none of its references changed',
					'element old: is removed, but `src/old.ts#collector` is still there (unchanged)'
				]
			);
			// the test and the plan are left out; the migration is marked as listed by the plan
			assert.deepEqual(result.unaccounted.runs.map((r) => `${r.path}${r.outsideModel ? ' (listed)' : ''}`), ['migrations/001.sql (listed)', 'src/glue.ts']);

			// correct the claims, tag what changed, delete what is removed
			rewrite(dir, model, (m) => {
				const by = (id) => m.elements.find((e) => e.id === id);
				by('budget').change = 'modified';
				by('owners').change = 'reused';
				by('cards').change = 'reused';
			});
			put(dir, 'src/budget.ts', '// @pattern api/guard\nexport function meter(n: number) {\n\treturn n + 1;\n}\n');
			put(dir, 'src/old.ts', 'export function shared() {\n\treturn 1;\n}\n');
			const good = run(dir, 'code', ...args);
			assert.equal(good.status, 0, good.stdout + good.stderr);
			assert.match(good.stdout, /^model-to-code \(base [0-9a-f]{10}\): pass — 5 element\(s\) with references, 0 failing/);
			assert.match(good.stdout, /src\/glue\.ts: 1/);

			// a tag the model does not carry is caught
			put(dir, 'src/page.ts', '// @pattern api/mutation\nexport function page() {\n\treturn [];\n}\n');
			const wrongTag = run(dir, 'code', ...args);
			assert.equal(wrongTag.status, 1);
			assert.match(wrongTag.stdout, /fail {2}element page: `src\/page\.ts#page` is tagged `api\/mutation` but the model says `api\/read-query`/);
		} finally {
			rmSync(dir, { recursive: true, force: true });
		}
	});

	it('compares with the approved model: unrecorded change fails, recorded passes, weaker enforcement stops', () => {
		const { dir, model, args } = repository();
		try {
			assert.equal(run(dir, 'approved', ...args).status, 0);

			const changed = rewrite(dir, model, (m) => void (m.elements.find((e) => e.id === 'budget').change = 'modified'));
			const unrecorded = run(dir, 'approved', ...args);
			assert.equal(unrecorded.status, 1);
			assert.match(unrecorded.stdout, /approved versus shipped \(against Approved [0-9a-f]{10}\): FAIL — 1 structural difference/);
			assert.match(unrecorded.stdout, /fail {2}element:budget \(change\): model change, not recorded in the ledger/);

			put(dir, 'plans/p/review.md', '## Deviations\n- `element:budget` the meter had to count the new page reads\n');
			const recorded = run(dir, 'approved', ...args);
			assert.equal(recorded.status, 0, recorded.stdout);
			assert.match(recorded.stdout, /ok {4}element:budget \(change\): model change, recorded — the meter had to count/);

			rewrite(dir, changed, (m) => void (m.relationships[0].enforcement = 'our-code'));
			const stop = run(dir, 'all', ...args, '--json');
			assert.equal(stop.status, 1);
			const approved = JSON.parse(stop.stdout).approved;
			assert.equal(approved.verdict, 're-approval');
			assert.deepEqual(approved.differences.find((d) => d.key === 'relationship:read').reasons, ['enforcement on data relationship moved down: `platform` → `our-code`']);
		} finally {
			rmSync(dir, { recursive: true, force: true });
		}
	});

	it('reports a usage error with exit 2', () => {
		const { dir } = repository();
		try {
			const r = run(dir, 'code', '--model', 'plans/p/none.json');
			assert.equal(r.status, 2);
			assert.match(r.stderr, /no such model/);
			assert.equal(run(dir, 'nope').status, 2);
			put(dir, 'plans/p/plan.md', '# Plan\n');
			assert.match(run(dir, 'approved', '--model', 'plans/p/model.c4ish.json').stderr, /no `Approved: <date> <commit>` line/);
		} finally {
			rmSync(dir, { recursive: true, force: true });
		}
	});
});

