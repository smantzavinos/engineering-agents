// Tests for tools/model-check.mjs. Run: node --test tools/model-check.test.mjs
// The last group builds a small git repository and runs the real diagram tool; it is skipped
// when `c4ish` is not on PATH. Its git submodule cases are skipped when the tool does not look
// inside submodules.

import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, renameSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, it } from 'node:test';
import { blockCommentLines, changeStyles, checkApproved, checkCode, dataRelationshipKinds, expectedTag, firstComment, globToRegExp, isTagLine, kindCategories, matchAny, parseLedger, parsePlan, parseTag, tagMismatches } from './model-check.mjs';

const SCRIPT = join(dirname(fileURLToPath(import.meta.url)), 'model-check.mjs');

describe('started through a symlink, as an installed copy is', () => {
	it('still runs: no command is a usage error, not a silent pass', () => {
		const dir = mkdtempSync(join(tmpdir(), 'model-check-link-'));
		try {
			const link = join(dir, 'model-check.mjs');
			symlinkSync(SCRIPT, link);
			const r = spawnSync(process.execPath, [link], { encoding: 'utf8' });
			assert.equal(r.status, 2);
			assert.match(r.stderr, /give a command/);
		} finally {
			rmSync(dir, { recursive: true, force: true });
		}
	});
});

describe('globs', () => {
	it('** crosses directories, * stays in one segment', () => {
		assert.ok(matchAny('docs/a/b.md', ['docs/**']));
		assert.ok(matchAny('src/a/b.test.ts', ['**/*.test.ts']));
		assert.ok(matchAny('b.test.ts', ['**/*.test.ts']));
		assert.ok(!matchAny('src/a/b.ts', ['src/*.ts']));
		assert.ok(matchAny('src/b.ts', ['src/*.ts']));
		assert.ok(!globToRegExp('a.ts').test('aXts'));
	});

	it('a glob with no wildcard also matches everything under it', () => {
		assert.ok(matchAny('docs/patterns/api.md', ['docs/patterns']));
		assert.ok(matchAny('docs/patterns/a/b.md', ['docs/patterns/']));
		assert.ok(matchAny('rules/guard.yml', ['rules/guard.yml']));
		assert.ok(!matchAny('docs/patterns2/api.md', ['docs/patterns']));
		assert.ok(matchAny('conf/profile.json', ['./conf/profile.json']));
		assert.ok(matchAny('conf/profile.json', ['./conf/']));
	});
});

describe('plan.md', () => {
	const plan = [
		'# Plan',
		'Approved: 2026-01-02 abc1234',
		'```',
		'Approved: 2026-01-03 fff0000',
		'```',
		'## 4. Changes outside the model',
		'- `docs/patterns/api.md`: new entry',
		'We do not touch `docs/patterns/web.md`.',
		'- also not `this/one.md`',
		'```sh',
		'# a comment in a code block is not a heading',
		'```',
		'### Config',
		'- `config/*.json`',
		'## Risks',
		'- `not/this.md`',
		'- **Re-approved:** 2026-01-05 `def5678` enforcement',
		'## No changes outside the model here',
		'- `nor/this.md`'
	].join('\n');

	it('reads approvals in order, and the paths that start a list item under Changes outside the model', () => {
		const p = parsePlan(plan);
		assert.deepEqual(p.approvals, [
			{ kind: 'Approved', date: '2026-01-02', commit: 'abc1234' },
			{ kind: 'Re-approved', date: '2026-01-05', commit: 'def5678' }
		]);
		assert.deepEqual(p.outsideModel, ['docs/patterns/api.md', 'config/*.json']);
	});

	it('reads deviations from the section headed Deviations, by key', () => {
		const ledger = ['## Review 1', '- `element:x` not a deviation', '### Deviations', '- `element:svc` flipped to modified; the guard moved', '* `relationship:w`  rerouted', '- `src/a.ts` not a key', 'text', '## Deviations not recorded (findings)', '- `element:late` no'];
		assert.deepEqual([...parseLedger(ledger.join('\n'))], [
			['element:svc', 'flipped to modified; the guard moved'],
			['relationship:w', 'rerouted']
		]);
	});
});

describe('plan.md and ledger, as people write them', () => {
	it('reads CRLF files, numbered and + lists, a heading with a colon, and a path with a space', () => {
		const text = ['Approved: 2026-01-02 abc1234', '## Changes outside the model:', '1. `docs/a b.md` renamed', '+ `config/x.json`', '2) `rules/y.yml`', '## Deviations:', '1. `element:svc` moved'].join('\r\n');
		assert.deepEqual(parsePlan(text), { approvals: [{ kind: 'Approved', date: '2026-01-02', commit: 'abc1234' }], outsideModel: ['docs/a b.md', 'config/x.json', 'rules/y.yml'] });
		assert.deepEqual([...parseLedger(text)], [['element:svc', 'moved']]);
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

	it('a tag starts its comment line; a mention is not a tag', () => {
		assert.equal(parseTag('// TODO: remove @pattern a/b'), null);
		assert.equal(parseTag("const s = 'see @pattern a/b';"), null);
		assert.ok(isTagLine('  @pattern web/page'));
		assert.ok(isTagLine('\t * @pattern a/b'));
		assert.ok(!isTagLine('// @patterns a/b'));
	});

	it('knows the comment markers; a line with no marker is a tag only inside a comment', () => {
		for (const line of ['//! @pattern a/b', '/// @pattern a/b', '/** @pattern a/b */', '{/* @pattern a/b */}', '# @pattern a/b', '-- @pattern a/b', '; @pattern a/b', '% @pattern a/b', '<!-- @pattern a/b -->']) assert.ok(isTagLine(line, false), line);
		assert.equal(parseTag('{/* @pattern web/page partial: no frame */}').pattern, 'web/page');
		assert.equal(parseTag('//! @pattern a/b').pattern, 'a/b');
		assert.ok(isTagLine('@pattern a/b'));
		assert.ok(!isTagLine('@pattern a/b', false));
		assert.ok(!isTagLine("'@pattern a/b'", true));
	});

	it('finds the lines inside a block comment that opens a line', () => {
		const text = ['/**', ' * doc', '@pattern a/b', ' */', 'const glob = "src/*";', '@pattern a/b', '<!--', 'x', '-->', '/* one line */', 'y', '{/*', 'z', '*/}'].join('\n');
		assert.deepEqual([...blockCommentLines(text)], [2, 3, 4, 8, 9, 13, 14]);
	});

	it('a tag wrapped onto a second line loses its further patterns, so it cannot agree by accident', () => {
		assert.deepEqual(parseTag('// @pattern a/b\n//   ; also c/d').also, []);
	});

	it('finds the first comment of a file', () => {
		assert.deepEqual(firstComment('#!/usr/bin/env node\n\n// @pattern a/b\n// more\nconst x = 1;\n// later'), { start: 3, end: 4, text: '// @pattern a/b\n// more' });
		assert.equal(firstComment('<script lang="ts">\n\t// @pattern web/page\n\tlet a;\n</script>').text.trim(), '// @pattern web/page');
		assert.equal(firstComment('<!--\n  @pattern web/page\n-->\n<div/>').end, 3);
		assert.equal(firstComment('const x = 1;\n// @pattern a/b'), undefined);
		assert.equal(firstComment('"use client";\n\n// @pattern web/page\nexport {};').text, '// @pattern web/page');
		assert.equal(firstComment("#!/bin/node\n'use strict'\n/* @pattern a/b */\nx").start, 3);
		assert.equal(firstComment('{/* @pattern web/page */}\n<div/>').end, 1);
	});

	const model = {
		elements: [
			{ id: 'box', kind: 'container' },
			{ id: 'full', pattern: 'api/mutation', patterns: ['api/mutation', 'api/guard'] },
			{ id: 'part', pattern: 'api/mutation', patternFit: 'partial', parts: [{ title: 'Guard', pattern: 'api/guard' }, { title: 'Plain' }, { title: 'Loose', pattern: 'api/guard', patternFit: 'partial' }, { title: 'Retry', bespoke: 'Only here.' }, { title: 'None', pattern: null }] },
			{ id: 'one', bespoke: 'A one-off importer.' },
			{ id: 'none', pattern: null }
		]
	};

	it('says what the model expects', () => {
		assert.deepEqual(expectedTag(model, { element: 'box' }), { none: true });
		assert.deepEqual(expectedTag(model, { element: 'full' }), { pattern: 'api/mutation', bespoke: false, partial: false, also: ['api/guard'] });
		assert.equal(expectedTag(model, { element: 'part' }).partial, true);
		assert.deepEqual(expectedTag(model, { element: 'part', part: 'Guard' }), { pattern: 'api/guard', bespoke: false, partial: false, also: [] });
		// a part with no pattern of its own carries the element's tag
		assert.equal(expectedTag(model, { element: 'part', part: 'Plain' }).pattern, 'api/mutation');
		// a part states its own fit, and can be bespoke where its element is not
		assert.equal(expectedTag(model, { element: 'part', part: 'Loose' }).partial, true);
		assert.deepEqual(expectedTag(model, { element: 'part', part: 'Retry' }), { bespoke: true, partial: false, also: [] });
		assert.deepEqual(expectedTag(model, { element: 'one' }), { bespoke: true, partial: false, also: [] });
		// a bespoke element can still carry further patterns
		assert.deepEqual(expectedTag({ elements: [{ id: 'b', bespoke: 'x', patterns: ['api/guard'] }] }, { element: 'b' }).also, ['api/guard']);
		// `pattern: null` says no pattern applies: it is not bespoke, on an element or on a part
		assert.deepEqual(expectedTag(model, { element: 'none' }), { none: true });
		assert.deepEqual(expectedTag(model, { element: 'part', part: 'None' }), { none: true });
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
		assert.match(tagMismatches(parseTag('// @pattern bespoke: importer'), expectedTag(model, { element: 'none' }))[0], /gives its element no pattern/);
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
		assert.deepEqual(messages(r), ['element m: is modified, but `m.ts#f` does not resolve (missing-name); it may now be `m.ts#g` (renamed)']);
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
		const r = checkCode({ elements: [el('n', 'new', 'a/b'), el('one', 'modified', undefined, { bespoke: 'A one-off.' }), el('box', 'new'), el('r', 'reused', 'a/b')] }, { references: [] });
		assert.deepEqual(messages(r), ['element n: is new and has a pattern, but no code reference', 'element one: is modified and is bespoke, but no code reference']);
	});

	it('an element the build creates or changes in code must say what it is and name its code', () => {
		const categories = { component: 'code', data: 'data', container: 'container' };
		const bare = (id, kind, change, extra = {}) => ({ id, kind, title: id, change, ...extra });
		const model = {
			elements: [
				bare('box', 'container', 'new'),
				bare('ext', 'external', 'new'),
				bare('quiet', 'component', 'new'),
				bare('table', 'data', 'modified'),
				bare('nulled', 'component', 'modified', { pattern: null }),
				bare('context', 'component', 'reused', { pattern: null }),
				bare('gone', 'component', 'removed'),
				bare('split', 'component', 'new', { parts: [{ title: 'a', pattern: 'a/b' }, { title: 'b', bespoke: 'Only here.' }] }),
				bare('half', 'component', 'new', { parts: [{ title: 'a', pattern: 'a/b' }, { title: 'b' }] }),
				bare('nullPart', 'component', 'new', { parts: [{ title: 'a', pattern: null }] })
			]
		};
		assert.deepEqual(messages(checkCode(model, { references: [] }, { categories })), [
			'element quiet: is new code, but states neither a pattern nor `bespoke` with a reason',
			'element quiet: is new and is code, but no code reference',
			'element table: is modified data, but states neither a pattern nor `bespoke` with a reason',
			'element table: is modified and is data, but no code reference',
			'element nulled: is modified code, but says `pattern: null`: name a pattern, or say `bespoke` with a reason',
			'element nulled: is modified and is code, but no code reference',
			'element split: is new and has parts with patterns, but no code reference',
			'element half: is new code, but states neither a pattern nor `bespoke` with a reason (on itself or on each of its parts)',
			'element half: is new and is code, but no code reference',
			'element nullPart: is new code, but says `pattern: null`: name a pattern, or say `bespoke` with a reason (on itself or on each of its parts)',
			'element nullPart: is new and is code, but no code reference'
		]);
		// with a reference the state is still required
		const one = { elements: [bare('quiet', 'component', 'new', { code: ['q.ts#f'] })] };
		assert.deepEqual(messages(checkCode(one, { references: [named('q.ts#f', { element: 'quiet' }, 'added')] }, { categories })), ['element quiet: is new code, but states neither a pattern nor `bespoke` with a reason']);
		// a profile that gives its kinds no category asks for nothing
		assert.equal(checkCode({ elements: [bare('quiet', 'component', 'new')] }, { references: [] }).ok, true);
	});

	it('changed code must carry a tag that agrees; untouched code may be untagged', () => {
		const model = { elements: [el('m', 'modified', 'a/b')] };
		const report = { references: [named('m.ts#f', { element: 'm' }, 'modified'), named('m.ts#g', { element: 'm' }, 'unchanged'), named('m.ts#h', { element: 'm' }, 'unchanged')] };
		report.references[1].head.extents = [{ kind: 'function', start: 6, end: 6 }];
		report.references[2].head.extents = [{ kind: 'function', start: 8, end: 8, comment: { start: 7, end: 7 } }];
		const text = '// plain comment\nexport function f() {\n\treturn 1;\n}\n\nexport function g() {}\n// @pattern c/d\nexport function h() {}\n';
		assert.deepEqual(messages(checkCode(model, report, { read: files({ 'm.ts': text }) })), ['element m: `m.ts#f` has no @pattern tag', 'element m: `m.ts#h` is tagged `c/d` but the model says `a/b`']);
	});

	it('a retag of code the build left alone must still agree with the model, in a reused element too', () => {
		const model = { elements: [el('r', 'reused', 'api/guard')] };
		const report = { references: [named('r.ts#f', { element: 'r' }, 'unchanged', { commentChanged: true })] };
		const retagged = '// @pattern api/guard partial: skips the tenant check\nexport function f() {\n\treturn 1;\n}\n';
		assert.deepEqual(messages(checkCode(model, report, { read: files({ 'r.ts': retagged }) })), ['element r: `r.ts#f` is tagged partial but the model marks a full fit']);
		assert.equal(checkCode(model, report, { read: files({ 'r.ts': tagged('api/guard') }) }).ok, true);
		assert.equal(checkCode(model, report, { read: files({ 'r.ts': 'export function f() {}\n' }) }).ok, true);
	});

	it('a part with its own change state is judged by it', () => {
		const model = { elements: [el('m', 'modified', 'a/b', { parts: [{ title: 'Gone', change: 'removed' }, { title: 'Kept', change: 'reused' }, { title: 'Fresh', change: 'new' }] })] };
		const part = (title, change) => ({ element: 'm', part: title, change });
		const good = { references: [named('m.ts#gone', part('Gone', 'removed'), 'removed'), named('m.ts#kept', part('Kept', 'reused'), 'unchanged'), named('m.ts#f', { element: 'm' }, 'modified')] };
		assert.deepEqual(messages(checkCode(model, good, { read: files({ 'm.ts': tagged('a/b') }) })), []);
		const bad = { references: [named('m.ts#gone', part('Gone', 'removed'), 'unchanged'), named('m.ts#kept', part('Kept', 'reused'), 'modified'), named('m.ts#fresh', part('Fresh', 'new'), 'modified')] };
		assert.deepEqual(messages(checkCode(model, bad)), [
			'element m: part "Gone" is removed, but `m.ts#gone` is still there (unchanged)',
			'element m: part "Kept" is reused, but `m.ts#kept` is modified: that makes it modified, a model change',
			'element m: part "Fresh" is new, but `m.ts#fresh` is modified: it existed at the base',
			'element m: `m.ts#fresh` (part "Fresh") has no @pattern tag'
		]);
		// a modified element whose only change is a part that went away has changed
		assert.equal(checkCode(model, { references: [named('m.ts#gone', part('Gone', 'removed'), 'removed')] }).ok, true);
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
		const text = `${tagged('a/b')}\n// @pattern a/b\nexport function stray() { return 'not a tag: @pattern a/b'; }\n`;
		const report = {
			references: [named('n.ts#f', { element: 'n' }, 'added')],
			files: [{ path: 'n.ts', status: 'added', base: [], head: [{ start: 1, end: 1, refs: [{ ref: 'n.ts#f', in: 'comment' }] }, { start: 2, end: 4, refs: [{ ref: 'n.ts#f', in: 'body' }] }, { start: 5, end: 7, refs: [] }] }]
		};
		const r = checkCode(model, report, { read: files({ 'n.ts': text }) });
		assert.deepEqual(messages(r), ['n.ts:6: a @pattern tag was added or changed here, but no element references this definition: `// @pattern a/b`']);
		assert.deepEqual(r.unaccounted.runs, [{ path: 'n.ts', side: 'head', start: 5, end: 7, lines: 3 }]);
	});

	it('a line that only looks like a tag inside a string is not one; a bare line in a block comment is', () => {
		const text = ['const help = `', '@pattern a/b', '`;', '/**', '@pattern a/b', ' */', 'export function stray() {}', ''].join('\n');
		const report = { references: [], files: [{ path: 's.ts', status: 'added', base: [], head: [{ start: 1, end: 7, refs: [] }] }] };
		const r = checkCode({ elements: [] }, report, { read: files({ 's.ts': text }) });
		assert.deepEqual(
			r.failures.map((f) => f.where),
			['s.ts:5']
		);
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
const categories = { data: 'data', container: 'container', feature: 'product', component: 'code' };
const project = { catalog: ['docs/patterns/**'], rules: ['rules/**'], profile: 'docs/patterns/profile.c4ish.json' };
const classes = (r) => r.differences.map((d) => `${d.key} ${d.class}${d.reasons ? `: ${d.reasons.join('; ')}` : ''}`);

describe('approved versus shipped', () => {
	it('passes with no difference, and with model changes the ledger records', () => {
		assert.equal(checkApproved(diffOf(), { categories, project }).verdict, 'pass');
		const diff = diffOf({ kind: 'element', id: 'svc', change: 'changed', before: { kind: 'component' }, after: { kind: 'component' }, fields: [{ path: ['change'], change: 'changed', before: 'reused', after: 'modified' }] });
		const r = checkApproved(diff, { categories, project, deviations: new Map([['element:svc', 'the guard moved in']]) });
		assert.equal(r.verdict, 'pass');
		assert.deepEqual(r.differences, [{ key: 'element:svc', change: 'changed', fields: [{ path: 'change', change: 'changed' }], class: 'model-change', recorded: true, deviation: 'the guard moved in' }]);
	});

	it('fails on a model change the ledger does not record, and notes a record with no difference', () => {
		const diff = diffOf({ kind: 'element', id: 'job', change: 'added', after: { kind: 'component' } });
		const r = checkApproved(diff, { categories, project, deviations: new Map([['element:other', 'x']]) });
		assert.equal(r.verdict, 'fail');
		assert.deepEqual(classes(r), ['element:job model-change']);
		assert.deepEqual(r.stale, ['element:other']);
	});

	it('a data element, container or product element added or removed needs re-approval, recorded or not', () => {
		const diff = diffOf(
			{ kind: 'element', id: 't', change: 'added', after: { kind: 'data' } },
			{ kind: 'element', id: 'c', change: 'removed', before: { kind: 'container' } },
			{ kind: 'element', id: 'p', change: 'added', after: { kind: 'feature' } },
			{ kind: 'element', id: 'gone', change: 'changed', before: { kind: 'data' }, after: { kind: 'data' }, fields: [{ path: ['change'], change: 'changed', before: 'modified', after: 'removed' }] },
			{ kind: 'element', id: 'dropped', change: 'changed', before: { kind: 'component' }, after: { kind: 'component' }, fields: [{ path: ['change'], change: 'changed', before: 'reused', after: 'removed' }] },
			{ kind: 'element', id: 'turned', change: 'changed', before: { kind: 'component' }, after: { kind: 'data' }, fields: [{ path: ['kind'], change: 'changed', before: 'component', after: 'data' }] },
			{ kind: 'element', id: 'left', change: 'changed', before: { kind: 'container' }, after: { kind: 'component' }, fields: [{ path: ['kind'], change: 'changed', before: 'container', after: 'component' }] },
			{ kind: 'element', id: 'plain', change: 'removed', before: { kind: 'component' } }
		);
		const r = checkApproved(diff, { categories, project, deviations: new Map([['element:t', 'needed']]) });
		assert.equal(r.verdict, 're-approval');
		assert.deepEqual(classes(r), [
			'element:t re-approval: data element added',
			'element:c re-approval: container removed',
			'element:p re-approval: product element added',
			'element:gone re-approval: data element removed (change state became removed)',
			'element:dropped model-change',
			'element:turned re-approval: data element added (kind was `component`)',
			'element:left re-approval: container removed (kind is now `component`)',
			'element:plain model-change'
		]);
	});

	it('enforcement moved down needs re-approval; moved up is a model change', () => {
		const rel = (id, before, after) => ({ kind: 'relationship', id, change: 'changed', fields: [{ path: ['enforcement'], change: 'changed', before, after }] });
		const r = checkApproved(diffOf(rel('down', 'platform', 'our-code'), rel('up', 'nothing', 'platform'), rel('derived', 'platform-correlated', 'derived'), rel('fromDerived', 'derived', 'our-code'), rel('odd', 'platform', 'custom')), { categories, project });
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
		assert.deepEqual(classes(checkApproved(diff, { categories, project: mapped })), ['relationship:w re-approval: enforcement on data relationship moved down: `db` → `db-correlated`']);
		assert.match(classes(checkApproved(diff, { categories, project }))[0], /cannot rank/);
	});

	it('a new data relationship or tie enforced by our-code or nothing needs re-approval', () => {
		const diff = diffOf(
			{ kind: 'relationship', id: 'weak', change: 'added', after: { enforcement: 'nothing' } },
			{ kind: 'relationship', id: 'strong', change: 'added', after: { enforcement: 'platform' } },
			{ kind: 'relationship', id: 'call', change: 'added', after: { kind: 'calls' } },
			{ kind: 'relationship', id: 'silent', change: 'added', after: { kind: 'writes' } },
			{ kind: 'relationship', id: 'became', change: 'changed', before: { kind: 'calls' }, after: { kind: 'reads' }, fields: [{ path: ['kind'], change: 'changed', before: 'calls', after: 'reads' }] },
			{ kind: 'relationship', id: 'stated', change: 'changed', before: { kind: 'reads' }, after: { kind: 'reads', enforcement: 'our-code' }, fields: [{ path: ['enforcement'], change: 'added', after: 'our-code' }] },
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
		assert.deepEqual(classes(checkApproved(diff, { categories, project })), [
			'relationship:weak re-approval: new data relationship enforced by `nothing`',
			'relationship:strong model-change',
			'relationship:call model-change',
			'relationship:silent re-approval: new data relationship enforced by `nothing stated`',
			'relationship:became re-approval: new data relationship enforced by `nothing stated`',
			// it had no enforcement, which is the bottom: stating one is not a move down
			'relationship:stated model-change',
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
			{ kind: 'contract', id: 'new', change: 'added', after: {} },
			{ kind: 'contract', id: 'marked', change: 'changed', fields: [{ path: ['change'], change: 'changed', before: 'new', after: 'removed' }] }
		);
		assert.deepEqual(classes(checkApproved(diff, { categories, project })), ['contract:gone re-approval: contract removed', 'contract:a re-approval: access clause changed', 'contract:b re-approval: clause `limits` removed', 'contract:c model-change', 'contract:new model-change', 'contract:marked re-approval: contract removed (change state became removed)']);
	});

	it('drops a proposed pattern that the profile now holds, and keeps one it does not', () => {
		const diff = diffOf({ kind: 'pattern', id: 'api/batch', change: 'removed' }, { kind: 'pattern', id: 'api/other', change: 'removed' });
		assert.deepEqual(classes(checkApproved(diff, { categories, project, profilePatterns: new Set(['api/batch']) })), ['pattern:api/other model-change']);
	});

	it('ignores differences that are not structure', () => {
		const diff = { differences: [{ kind: 'element', id: 'e', change: 'changed', aspects: ['text'], fields: [{ path: ['title'], aspect: 'text', change: 'changed' }] }] };
		assert.deepEqual(checkApproved(diff, { categories, project }).differences, []);
	});

	it('a scenario dropped needs re-approval; one added is a model change', () => {
		const diff = diffOf({ kind: 'scenario', id: 'S1', change: 'removed', before: { id: 'S1', title: 'Save an item' } }, { kind: 'scenario', id: 'S3', change: 'added', after: { id: 'S3', title: 'Undo' } });
		const r = checkApproved(diff, { categories, project, deviations: new Map([['scenario:S1', 'not needed'], ['scenario:S3', 'asked for in review']]) });
		assert.equal(r.verdict, 're-approval');
		assert.deepEqual(classes(r), ['scenario:S1 re-approval: scenario removed', 'scenario:S3 model-change']);
	});

	it('guards a kind by the category its profile gives it; with no categories nothing is guarded', () => {
		const diff = diffOf({ kind: 'element', id: 't', change: 'added', after: { kind: 'data' } }, { kind: 'element', id: 'x', change: 'added', after: { kind: 'external' } });
		assert.deepEqual(classes(checkApproved(diff, { categories: kindCategories({ elementKinds: { data: { category: 'product' }, external: { label: 'External' }, component: { category: 'code' } } }), project })), ['element:t re-approval: product element added', 'element:x model-change']);
		assert.deepEqual(classes(checkApproved(diff, { project })), ['element:t model-change', 'element:x model-change']);
	});

	it('judges "became removed" by the style of the change state, not its name', () => {
		const styles = { ...changeStyles(), gone: 'removed', removed: 'reused' };
		const to = (after) => [{ path: ['change'], change: 'changed', before: 'new', after }];
		const diff = diffOf({ kind: 'contract', id: 'a', change: 'changed', fields: to('gone') }, { kind: 'contract', id: 'b', change: 'changed', fields: to('removed') }, { kind: 'element', id: 't', change: 'changed', after: { kind: 'data' }, fields: to('gone') });
		assert.deepEqual(classes(checkApproved(diff, { categories, project, styles })), ['contract:a re-approval: contract removed (change state became removed)', 'contract:b model-change', 'element:t re-approval: data element removed (change state became removed)']);
	});

	it('guards the profile wherever it sits and however the path file spells it', () => {
		const own = { ...project, profile: './conf/profile.c4ish.json' };
		const r = checkApproved(diffOf(), { categories, project: own, changedPaths: ['conf/profile.c4ish.json', 'conf/other.json'] });
		assert.deepEqual(r.paths, [{ path: 'conf/profile.c4ish.json', kind: 'profile' }]);
		assert.equal(checkApproved(diffOf(), { categories, project: own, changedPaths: ['conf/profile.c4ish.json'], outsideModel: ['conf/profile.c4ish.json'] }).verdict, 'pass');
		assert.equal(checkApproved(diffOf(), { categories, project: { ...project, profile: undefined }, changedPaths: ['conf/profile.c4ish.json'] }).verdict, 'pass');
	});

	it('a catalog, rule or profile file the approved plan does not list needs re-approval', () => {
		const changedPaths = ['src/a.ts', 'docs/patterns/api.md', 'docs/patterns/web.md', 'rules/guard.yml', 'docs/patterns/profile.c4ish.json'];
		const r = checkApproved(diffOf(), { categories, project, changedPaths, outsideModel: ['docs/patterns/api.md', 'docs/patterns/profile.c4ish.json'] });
		assert.equal(r.verdict, 're-approval');
		assert.deepEqual(r.paths, [
			{ path: 'docs/patterns/web.md', kind: 'catalog' },
			{ path: 'rules/guard.yml', kind: 'rule' }
		]);
		assert.equal(checkApproved(diffOf(), { categories, project, changedPaths, outsideModel: ['docs/patterns/**', 'rules/guard.yml'] }).verdict, 'pass');
	});

	it('the path file itself is guarded the same way', () => {
		const r = checkApproved(diffOf(), { categories, project, projectPath: 'project.json', changedPaths: ['project.json'] });
		assert.deepEqual(r.paths, [{ path: 'project.json', kind: 'path' }]);
		assert.equal(checkApproved(diffOf(), { categories, project, projectPath: 'project.json', changedPaths: ['project.json'], outsideModel: ['project.json'] }).verdict, 'pass');
	});

	it('takes data relationship kinds from the profile', () => {
		assert.deepEqual([...dataRelationshipKinds({ extends: 'default', relationshipKinds: { stores: { category: 'data' }, reads: { category: 'runtime' } } })].sort(), ['pins', 'references', 'stores', 'writes']);
		assert.deepEqual([...dataRelationshipKinds({ relationshipKinds: { stores: { enforcementRequired: true } } })], ['stores']);
	});
});

/* ------------------------------------------------------------------------- */

// the tool must be there, and new enough to print the profile it reads
const probe = spawnSync(process.env.C4ISH ?? 'c4ish', ['profile'], { encoding: 'utf8' });
const hasTool = probe.status === 0 && probe.stdout.trimStart().startsWith('{');

describe('against a real repository', { skip: hasTool ? false : 'c4ish is not on PATH, or has no `profile` command' }, () => {
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
		put(dir, 'project.json', JSON.stringify({ leftOut: ['plans/**', '**/*.test.ts', 'project.json'], rules: ['rules'], catalog: ['docs/patterns'] }));
		put(dir, 'rules/guard.yml', 'id: guard\nseverity: error\n');
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
			assert.match(good.stdout, /^judged by the plan as approved: Approved 2026-01-02 [0-9a-f]{10}\nmodel-to-code \(base [0-9a-f]{10}\): pass — 5 element\(s\) with references, 0 failing/);
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

	const stops = (r) => JSON.parse(r.stdout).approved.paths.map((p) => `${p.path} (${p.kind})`);
	const planWith = (dir, ...listed) => put(dir, 'plans/p/plan.md', `# Plan\n\nApproved: 2026-01-02 ${git(dir, 'rev-parse', 'HEAD')}\n\n## Changes outside the model\n${['migrations/001.sql', ...listed].map((l) => `- \`${l}\`\n`).join('')}`);

	it('reads the path file as approved: loosening it in the build changes nothing, and is itself a stop', () => {
		const { dir, model, args } = repository();
		try {
			// the build leaves everything out and names no rule or catalog path, adds a table, and records it
			put(dir, 'project.json', JSON.stringify({ leftOut: ['**'] }));
			rewrite(dir, model, (m) => void m.elements.push({ id: 'extra', kind: 'data', title: 'extra', change: 'new', pattern: 'data/table' }));
			put(dir, 'plans/p/review.md', '## Deviations\n- `element:extra` needed a table\n');
			const r = run(dir, 'approved', ...args, '--json');
			assert.equal(r.status, 1, r.stdout + r.stderr);
			const approved = JSON.parse(r.stdout).approved;
			assert.equal(approved.verdict, 're-approval');
			assert.deepEqual(approved.differences.find((d) => d.key === 'element:extra').reasons, ['data element added']);
			assert.deepEqual(stops(r), ['project.json (path)']);
			// the code check also keeps the approved left-out list: the glue is still unaccounted
			const code = JSON.parse(run(dir, 'code', ...args, '--json').stdout).code;
			assert.ok(code.unaccounted.runs.some((u) => u.path === 'src/glue.ts'));
		} finally {
			rmSync(dir, { recursive: true, force: true });
		}
	});

	it('needs the path file for the approved check, and refuses one that still lists kinds', () => {
		const { dir } = repository();
		try {
			const none = run(dir, 'approved', '--model', 'plans/p/model.c4ish.json');
			assert.equal(none.status, 2);
			assert.match(none.stderr, /needs the project path file/);
			git(dir, 'add', '-A');
			git(dir, 'commit', '-q', '-m', 'build');
			// which kinds are data, containers and product elements is the profile's to say
			put(dir, 'other.json', JSON.stringify({ leftOut: [], kinds: { container: ['container'] } }));
			git(dir, 'add', 'other.json');
			git(dir, 'commit', '-q', '-m', 'a path file that lists kinds');
			planWith(dir);
			for (const command of ['approved', 'code']) {
				const kinds = run(dir, command, '--model', 'plans/p/model.c4ish.json', '--project', 'other.json');
				assert.equal(kinds.status, 2, kinds.stdout);
				assert.match(kinds.stderr, /the path file has `kinds`, which this check no longer reads: give each element kind a `category` in the profile/);
			}
			const missing = run(dir, 'approved', '--model', 'plans/p/model.c4ish.json', '--project', 'nope.json');
			assert.equal(missing.status, 2);
			assert.match(missing.stderr, /no such path file/);
			put(dir, 'broken.json', '{ not json');
			git(dir, 'add', 'broken.json');
			git(dir, 'commit', '-q', '-m', 'a broken path file');
			planWith(dir);
			const broken = run(dir, 'code', '--model', 'plans/p/model.c4ish.json', '--project', 'broken.json');
			assert.equal(broken.status, 2);
			assert.match(broken.stderr, /broken\.json at [0-9a-f]+ is not JSON/);
		} finally {
			rmSync(dir, { recursive: true, force: true });
		}
	});

	it('a rule or catalog file changed stops unless the approved plan lists it; the working copy of the plan does not count', () => {
		const { dir, args } = repository();
		try {
			put(dir, 'rules/guard.yml', 'id: guard\nseverity: off\n');
			planWith(dir, 'rules/guard.yml'); // listed by the build, not by the approved plan
			const r = run(dir, 'approved', ...args, '--json');
			assert.equal(r.status, 1);
			assert.deepEqual(stops(r), ['rules/guard.yml (rule)']);

			// approve a plan that lists it: now a further change to it passes
			git(dir, 'add', '-A');
			git(dir, 'commit', '-q', '-m', 'plan lists the rule file');
			planWith(dir, 'rules/guard.yml');
			put(dir, 'rules/guard.yml', 'id: guard\nseverity: warn\n');
			const ok = run(dir, 'approved', ...args, '--json');
			assert.equal(ok.status, 0, ok.stdout + ok.stderr);
		} finally {
			rmSync(dir, { recursive: true, force: true });
		}
	});

	it('sees a rule file moved away, and a new catalog file with a name git would quote', () => {
		const { dir, args } = repository();
		try {
			git(dir, 'mv', 'rules/guard.yml', 'src/guard-old.yml');
			put(dir, 'docs/patterns/café notes.md', '# new\n');
			const r = run(dir, 'approved', ...args, '--json');
			assert.equal(r.status, 1, r.stdout + r.stderr);
			assert.deepEqual(stops(r).sort(), ['docs/patterns/café notes.md (catalog)', 'rules/guard.yml (rule)']);
		} finally {
			rmSync(dir, { recursive: true, force: true });
		}
	});

	it('gives the same verdict when the model is reached through a symlink', () => {
		const { dir } = repository();
		const link = `${dir}-link`;
		try {
			symlinkSync(dir, link);
			put(dir, 'rules/guard.yml', 'id: guard\nseverity: off\n');
			planWith(dir, 'rules/guard.yml');
			const r = run(tmpdir(), 'approved', '--model', join(link, 'plans/p/model.c4ish.json'), '--project', join(link, 'project.json'), '--json');
			assert.equal(r.status, 1, r.stdout + r.stderr);
			assert.deepEqual(stops(r), ['rules/guard.yml (rule)']);
		} finally {
			rmSync(link, { force: true });
			rmSync(dir, { recursive: true, force: true });
		}
	});

	it('an approval commit that is not there, or a plan that was not in it, is an error and not a verdict', () => {
		const { dir, args } = repository();
		try {
			put(dir, 'plans/p/plan.md', '# Plan\n\nApproved: 2026-01-02 0123456789abcdef0123456789abcdef01234567\n');
			const gone = run(dir, 'approved', ...args);
			assert.equal(gone.status, 2, gone.stdout);
			assert.equal(run(dir, 'code', ...args).status, 2);
			// a plan moved since approval: its approved list cannot be read
			planWith(dir);
			mkdirSync(join(dir, 'plans/q'));
			renameSync(join(dir, 'plans/p/plan.md'), join(dir, 'plans/q/plan.md'));
			const moved = run(dir, 'approved', ...args, '--plan', 'plans/q/plan.md');
			assert.equal(moved.status, 2, moved.stdout);
			assert.match(moved.stderr, /cannot read plans\/q\/plan\.md at/);
		} finally {
			rmSync(dir, { recursive: true, force: true });
		}
	});

	const commit = (dir, message) => {
		git(dir, 'add', '-A');
		git(dir, 'commit', '-q', '-m', message);
		return git(dir, 'rev-parse', 'HEAD');
	};
	const runs = (r) => JSON.parse(r.stdout).code.unaccounted.runs.map((u) => `${u.path}${u.outsideModel ? ' (listed)' : ''}`);

	it('is judged by the approved plan and path file whatever the build writes, commits or passes as the base', () => {
		const { dir, args } = repository();
		try {
			// the build lists its own glue in the plan, then commits a path file that leaves everything out
			planWith(dir, 'src/glue.ts');
			assert.deepEqual(runs(run(dir, 'code', ...args, '--json')), ['migrations/001.sql (listed)', 'src/glue.ts']);
			put(dir, 'project.json', JSON.stringify({ leftOut: ['**'], noTag: ['**'] }));
			put(dir, 'src/page.ts', '// @pattern api/mutation\nexport function page() {\n\treturn [];\n}\n');
			const loosened = commit(dir, 'build: loosen the path file');
			const later = run(dir, 'code', ...args, '--base', loosened);
			assert.equal(later.status, 2, later.stdout);
			assert.match(later.stderr, /--base [0-9a-f]+ is not the first approval commit/);
			const r = run(dir, 'code', ...args, '--json');
			assert.equal(r.status, 1);
			assert.ok(JSON.parse(r.stdout).code.failures.some((f) => /is tagged `api\/mutation` but the model says `api\/read-query`/.test(f.message)));
			assert.deepEqual(runs(r), ['migrations/001.sql (listed)', 'src/glue.ts']);
		} finally {
			rmSync(dir, { recursive: true, force: true });
		}
	});

	it('after a re-approval, takes the settings from the latest approval and keeps the first as the code baseline', () => {
		const { dir, args } = repository();
		try {
			const first = git(dir, 'rev-parse', 'HEAD');
			put(dir, 'project.json', JSON.stringify({ leftOut: ['plans/**', '**/*.test.ts', 'project.json', 'src/glue.ts'], rules: ['rules'], catalog: ['docs/patterns'] }));
			const second = commit(dir, 're-approved: the glue is left out');
			put(dir, 'plans/p/plan.md', `# Plan\n\nApproved: 2026-01-02 ${first}\nRe-approved: 2026-01-05 ${second}\n\n## Changes outside the model\n- \`migrations/001.sql\`\n`);
			const r = run(dir, 'code', ...args, '--json');
			const out = JSON.parse(r.stdout);
			assert.deepEqual(out.approvals, [
				{ kind: 'Approved', date: '2026-01-02', commit: first },
				{ kind: 'Re-approved', date: '2026-01-05', commit: second }
			]);
			assert.equal(out.code.base, first);
			assert.deepEqual(runs(r), ['migrations/001.sql (listed)']);
			assert.match(run(dir, 'approved', ...args).stdout, /^judged by the plan as approved: Approved 2026-01-02 [0-9a-f]{10} → Re-approved 2026-01-05 [0-9a-f]{10}\napproved versus shipped \(against Re-approved/);
		} finally {
			rmSync(dir, { recursive: true, force: true });
		}
	});

	it('a path file or profile that was not in the approval commit is an error: the working copy is never trusted', () => {
		const { dir, model } = repository();
		try {
			// a path file git does not track, which leaves everything out
			put(dir, '.gitignore', 'local.json\n');
			put(dir, 'local.json', JSON.stringify({ leftOut: ['**'] }));
			rewrite(dir, model, (m) => void m.elements.push({ id: 'extra', kind: 'data', title: 'extra', change: 'new', pattern: 'data/table' }));
			put(dir, 'plans/p/review.md', '## Deviations\n- `element:extra` needed a table\n');
			for (const command of ['approved', 'code']) {
				const r = run(dir, command, '--model', 'plans/p/model.c4ish.json', '--project', 'local.json');
				assert.equal(r.status, 2, r.stdout);
				assert.match(r.stderr, /cannot read local\.json at [0-9a-f]+, the commit the plan was approved at; the path file must be committed before approval/);
			}
			// an approved path file that names a profile the approval commit does not have
			put(dir, 'project.json', JSON.stringify({ profile: 'conf/profile.c4ish.json' }));
			commit(dir, 'path file names a profile');
			planWith(dir);
			put(dir, 'conf/profile.c4ish.json', JSON.stringify({ profileVersion: 0, id: 't', title: 'T', extends: 'default' }));
			const r = run(dir, 'approved', '--model', 'plans/p/model.c4ish.json', '--project', 'project.json');
			assert.equal(r.status, 2, r.stdout);
			assert.match(r.stderr, /cannot read conf\/profile\.c4ish\.json at .*the profile must be committed before approval/);
		} finally {
			rmSync(dir, { recursive: true, force: true });
		}
	});

	it('classifies by the profile as approved, and a changed profile stops, however the path file spells it', () => {
		const { dir, model, args } = repository();
		try {
			const profile = { profileVersion: 0, id: 't', title: 'T', extends: 'default', elementKinds: { ledger: { label: 'Ledger', category: 'data' } } };
			const loosened = { ...profile, elementKinds: { ledger: { label: 'Ledger' } }, relationshipKinds: { writes: { label: 'writes', category: 'runtime' } } };
			const settings = { profile: './conf/profile.c4ish.json' };
			put(dir, 'conf/profile.c4ish.json', JSON.stringify(profile));
			put(dir, 'project.json', JSON.stringify(settings));
			commit(dir, 'approved with a profile');
			planWith(dir);
			assert.equal(run(dir, 'approved', ...args).status, 0);

			// the build makes `writes` a runtime kind and `ledger` a kind of no category, adds a write
			// nothing enforces and a ledger, and records both
			const build = (m) => {
				m.relationships.push({ id: 'save', from: 'page', to: 'items', kind: 'writes', change: 'new' });
				m.elements.push({ id: 'book', kind: 'ledger', title: 'book', change: 'reused' });
			};
			const reasons = (r, key) => JSON.parse(r.stdout).approved.differences.find((d) => d.key === key).reasons;
			put(dir, 'conf/profile.c4ish.json', JSON.stringify(loosened));
			rewrite(dir, model, build);
			put(dir, 'plans/p/review.md', '## Deviations\n- `relationship:save` the page now saves\n- `element:book` kept for the audit\n');
			const r = run(dir, 'approved', ...args, '--json');
			assert.equal(r.status, 1, r.stdout + r.stderr);
			assert.deepEqual(stops(r), ['conf/profile.c4ish.json (profile)']);
			assert.deepEqual(reasons(r, 'relationship:save'), ['new data relationship enforced by `nothing stated`']);
			assert.deepEqual(reasons(r, 'element:book'), ['data element added']);

			// even when the approved plan lets the build change the profile, the approved profile classifies
			planWith(dir, 'conf/profile.c4ish.json');
			put(dir, 'conf/profile.c4ish.json', JSON.stringify(profile));
			put(dir, 'plans/p/model.c4ish.json', JSON.stringify(model, null, '\t'));
			commit(dir, 'approved: the plan may change the profile');
			planWith(dir, 'conf/profile.c4ish.json');
			put(dir, 'conf/profile.c4ish.json', JSON.stringify(loosened));
			rewrite(dir, model, build);
			const listed = run(dir, 'approved', ...args, '--json');
			assert.equal(listed.status, 1, listed.stdout + listed.stderr);
			assert.deepEqual(stops(listed), []);
			assert.deepEqual(reasons(listed, 'relationship:save'), ['new data relationship enforced by `nothing stated`']);
			assert.deepEqual(reasons(listed, 'element:book'), ['data element added']);
		} finally {
			rmSync(dir, { recursive: true, force: true });
		}
	});

	it('asks the tool what each kind is: code that states no pattern fails, and `pattern: null` is not bespoke', () => {
		const { dir, model, args } = repository();
		try {
			put(dir, 'src/quiet.ts', 'export function quiet() {\n\treturn 1;\n}\n');
			put(dir, 'src/loose.ts', '// @pattern bespoke: a one-off\nexport function loose() {\n\treturn 1;\n}\n');
			const next = rewrite(dir, model, (m) => {
				m.elements.push({ id: 'quiet', kind: 'component', parent: 'api', title: 'Quiet', change: 'new', code: ['src/quiet.ts#quiet'] });
				m.elements.push({ id: 'loose', kind: 'component', parent: 'api', title: 'Loose', change: 'new', pattern: null, code: ['src/loose.ts#loose'] });
				m.elements.push({ id: 'ghost', kind: 'component', parent: 'api', title: 'Ghost', change: 'new' });
				m.elements.push({ id: 'ext', kind: 'external', title: 'Mail', change: 'new' });
			});
			const failures = (r) =>
				JSON.parse(r.stdout)
					.code.failures.map((f) => `${f.where}: ${f.message}`)
					.filter((f) => /quiet|loose|ghost|ext/.test(f));
			assert.deepEqual(failures(run(dir, 'code', ...args, '--json')), [
				'element quiet: is new code, but states neither a pattern nor `bespoke` with a reason',
				'element loose: is new code, but says `pattern: null`: name a pattern, or say `bespoke` with a reason',
				'element loose: `src/loose.ts#loose` has the tag `@pattern bespoke: a one-off` but the model gives its element no pattern',
				'element ghost: is new code, but states neither a pattern nor `bespoke` with a reason',
				'element ghost: is new and is code, but no code reference'
			]);
			// said properly: bespoke with a reason, tagged as such
			put(dir, 'src/quiet.ts', '// @pattern bespoke: the only caller\nexport function quiet() {\n\treturn 1;\n}\n');
			rewrite(dir, next, (m) => {
				const by = (id) => m.elements.find((e) => e.id === id);
				by('quiet').bespoke = 'The only caller.';
				delete by('loose').pattern;
				by('loose').bespoke = 'A one-off.';
				m.elements = m.elements.filter((e) => e.id !== 'ghost');
			});
			assert.deepEqual(failures(run(dir, 'code', ...args, '--json')), []);
		} finally {
			rmSync(dir, { recursive: true, force: true });
		}
	});

	it('a scenario the build drops stops; one it adds is a model change to record', () => {
		const { dir, model, args } = repository();
		try {
			const scenarios = [
				{ id: 'S1', title: 'Read a page' },
				{ id: 'S2', title: 'Read the next page' }
			];
			rewrite(dir, model, (m) => void (m.scenarios = scenarios));
			commit(dir, 'approved with scenarios');
			planWith(dir);
			assert.equal(run(dir, 'approved', ...args).status, 0);
			rewrite(dir, model, (m) => void (m.scenarios = [{ id: 'S2', title: 'Read the page after' }, { id: 'S3', title: 'Read backwards' }]));
			put(dir, 'plans/p/review.md', '## Deviations\n- `scenario:S1` not needed after all\n- `scenario:S3` asked for in review\n');
			const r = run(dir, 'approved', ...args, '--json');
			assert.equal(r.status, 1, r.stdout + r.stderr);
			const approved = JSON.parse(r.stdout).approved;
			assert.equal(approved.verdict, 're-approval');
			// a reworded title is text, not structure
			assert.deepEqual(
				approved.differences.map((d) => `${d.key} ${d.class}${d.reasons ? `: ${d.reasons}` : ''}`).sort(),
				['scenario:S1 re-approval: scenario removed', 'scenario:S3 model-change']
			);
		} finally {
			rmSync(dir, { recursive: true, force: true });
		}
	});

	it('an approval line must name a commit in the history of HEAD, in order', () => {
		const { dir, args } = repository();
		try {
			const approved = git(dir, 'rev-parse', 'HEAD');
			git(dir, 'stash', '-q', '-u');
			git(dir, 'checkout', '-q', '-b', 'elsewhere');
			put(dir, 'project.json', JSON.stringify({ leftOut: ['**'] }));
			const elsewhere = commit(dir, 'a loose path file on another branch');
			git(dir, 'checkout', '-q', '-');
			git(dir, 'stash', 'pop', '-q');
			put(dir, 'plans/p/plan.md', `# Plan\n\nApproved: 2026-01-02 ${approved}\nRe-approved: 2026-01-03 ${elsewhere}\n`);
			const other = run(dir, 'all', ...args);
			assert.equal(other.status, 2, other.stdout);
			assert.match(other.stderr, /`Re-approved:` line names [0-9a-f]+, which is not in the history of HEAD/);

			const later = commit(dir, 'build');
			put(dir, 'plans/p/plan.md', `# Plan\n\nApproved: 2026-01-02 ${later}\nRe-approved: 2026-01-03 ${approved}\n`);
			const order = run(dir, 'all', ...args);
			assert.equal(order.status, 2, order.stdout);
			assert.match(order.stderr, /approval lines are out of order/);
		} finally {
			rmSync(dir, { recursive: true, force: true });
		}
	});

	it('runs a plan with no approval line only as a trial, and only a trial may use reports made beforehand', () => {
		const { dir, args } = repository();
		try {
			put(dir, 'diff.json', JSON.stringify({ differences: [] }));
			put(dir, 'changed.txt', 'rules/guard.yml\r\nsrc/a.ts\n');
			// an approved plan: git and the tool, nothing made beforehand, no way to call it a trial
			for (const option of [['--diff-report', 'diff.json'], ['--changed-paths', 'changed.txt'], ['--code-report', 'diff.json']]) {
				const r = run(dir, 'all', ...args, ...option);
				assert.equal(r.status, 2, r.stdout);
				assert.match(r.stderr, new RegExp(`${option[0]} is for trials`));
			}
			const claimed = run(dir, 'all', ...args, '--no-approval');
			assert.equal(claimed.status, 2, claimed.stdout);
			assert.match(claimed.stderr, /has an approval line/);

			put(dir, 'plans/p/plan.md', '# Plan\n');
			const plain = run(dir, 'code', ...args, '--base', 'HEAD');
			assert.equal(plain.status, 2, plain.stdout);
			assert.match(plain.stderr, /pass --no-approval to run a trial/);
			const trial = run(dir, 'code', ...args, '--base', 'HEAD', '--no-approval');
			assert.equal(trial.status, 1, trial.stderr);
			assert.match(trial.stdout, /^TRIAL \(--no-approval\): judged by the working copy, not by an approved plan\nmodel-to-code/);
			assert.equal(JSON.parse(run(dir, 'code', ...args, '--base', 'HEAD', '--no-approval', '--json').stdout).trial, true);

			const stop = run(dir, 'approved', ...args, '--no-approval', '--diff-report', 'diff.json', '--changed-paths', 'changed.txt', '--json');
			assert.equal(stop.status, 1, stop.stderr);
			assert.deepEqual(stops(stop), ['rules/guard.yml (rule)']);
			const nothing = run(dir, 'approved', ...args, '--no-approval');
			assert.equal(nothing.status, 2);
			assert.match(nothing.stderr, /pass --diff-report/);
			const missing = run(dir, 'approved', ...args, '--no-approval', '--diff-report', 'diff.json', '--changed-paths', 'nope.txt');
			assert.equal(missing.status, 2);
			assert.match(missing.stderr, /^model-check: cannot read .*nope\.txt: ENOENT\n$/);
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
	/** A root repository with an approved plan, whose code sits in one submodule, `lib`. */
	function rootWithSubmodule() {
		const top = mkdtempSync(join(tmpdir(), 'model-check-sub-'));
		const [origin, dir] = [join(top, 'origin'), join(top, 'root')];
		mkdirSync(origin);
		mkdirSync(dir);
		git(origin, 'init', '-q');
		put(origin, 'src/budget.ts', 'export function meter(n: number) {\n\treturn n;\n}\n');
		put(origin, 'docs/patterns/api.md', '# api\n');
		git(origin, 'add', '-A');
		git(origin, 'commit', '-q', '-m', 'lib');
		git(dir, 'init', '-q');
		git(dir, '-c', 'protocol.file.allow=always', 'submodule', '--quiet', 'add', origin, 'lib');
		const model = {
			schemaVersion: 1,
			title: 'Paged reads',
			views: [{ id: 'eng', kind: 'engineering', title: 'Paged reads' }],
			elements: [
				{ id: 'api', kind: 'container', title: 'API', change: 'modified' },
				{ id: 'page', kind: 'component', parent: 'api', title: 'Page', change: 'new', pattern: 'api/read-query', code: ['lib/src/page.ts#page'] },
				{ id: 'budget', kind: 'component', parent: 'api', title: 'Budget', change: 'reused', pattern: 'api/guard', code: ['lib/src/budget.ts#meter'] }
			]
		};
		put(dir, 'plans/p/model.c4ish.json', JSON.stringify(model, null, '\t'));
		put(dir, 'plans/p/plan.md', '# Plan\n');
		put(dir, 'project.json', JSON.stringify({ leftOut: ['plans/**', 'project.json', '.gitmodules'], catalog: ['lib/docs/patterns'] }));
		git(dir, 'add', '-A');
		git(dir, 'commit', '-q', '-m', 'approved plan');
		const approved = git(dir, 'rev-parse', 'HEAD');
		put(dir, 'plans/p/plan.md', `# Plan\n\nApproved: 2026-01-02 ${approved}\n`);
		const lib = join(dir, 'lib');
		/** Commits in the submodule, then in the root, which moves its pointer. */
		const commitBoth = () => {
			git(lib, 'add', '-A');
			git(lib, 'commit', '-q', '--allow-empty', '-m', 'next');
			git(dir, 'add', '-A');
			git(dir, 'commit', '-q', '-m', 'next');
		};
		return { top, dir, lib, model, commitBoth, args: ['--model', 'plans/p/model.c4ish.json', '--project', 'project.json'] };
	}
	const probeSub = (() => {
		if (!hasTool) return false;
		const { top, dir, args } = rootWithSubmodule();
		try {
			return !/does not look inside them/.test(run(dir, 'code', ...args).stderr);
		} finally {
			rmSync(top, { recursive: true, force: true });
		}
	})();

	describe('code in a git submodule', { skip: probeSub ? false : 'the c4ish in use does not look inside git submodules' }, () => {
		it('judges tags and changed lines inside the submodule, by paths from the root', () => {
			const { top, dir, lib, commitBoth, args } = rootWithSubmodule();
			try {
				// the build, inside the submodule: a new query without its tag, and glue
				put(lib, 'src/page.ts', 'export function page() {\n\treturn [];\n}\n');
				put(lib, 'src/glue.ts', 'export const glue = 1;\n');
				const untagged = run(dir, 'code', ...args, '--json');
				assert.equal(untagged.status, 1, untagged.stderr);
				const result = JSON.parse(untagged.stdout).code;
				assert.deepEqual(result.failures.map((f) => `${f.where}: ${f.message}`), ['element page: `lib/src/page.ts#page` has no @pattern tag']);
				assert.deepEqual(result.unaccounted.runs.map((r) => r.path), ['lib/src/glue.ts']);

				put(lib, 'src/page.ts', '// @pattern api/read-query\nexport function page() {\n\treturn [];\n}\n');
				const tagged = run(dir, 'code', ...args);
				assert.equal(tagged.status, 0, tagged.stdout + tagged.stderr);
				// the run names the submodule commits it compared: here nothing is committed, so both are the pinned one
				const pinned = git(lib, 'rev-parse', 'HEAD');
				assert.ok(tagged.stdout.includes(`  submodule lib: ${pinned.slice(0, 10)} → ${pinned.slice(0, 10)}\n`), tagged.stdout);

				// committed in the submodule and pinned by the root: the same result, and the pointer is no changed line
				commitBoth();
				const committed = run(dir, 'all', ...args, '--json');
				assert.equal(committed.status, 0, committed.stdout + committed.stderr);
				const all = JSON.parse(committed.stdout);
				assert.deepEqual(all.code.unaccounted.runs.map((r) => r.path), ['lib/src/glue.ts']);
				assert.deepEqual(all.approved.paths, []);
				assert.deepEqual(all.code.submodules, [{ path: 'lib', base: pinned, head: git(lib, 'rev-parse', 'HEAD') }]);
				assert.notEqual(all.code.submodules[0].head, pinned);
			} finally {
				rmSync(top, { recursive: true, force: true });
			}
		});

		it('a catalog file changed inside the submodule stops for re-approval', () => {
			const { top, dir, lib, commitBoth, args } = rootWithSubmodule();
			try {
				put(lib, 'docs/patterns/api.md', '# api\n\nA new rule.\n');
				const uncommitted = run(dir, 'approved', ...args, '--json');
				assert.equal(uncommitted.status, 1, uncommitted.stderr);
				assert.deepEqual(JSON.parse(uncommitted.stdout).approved.paths, [{ path: 'lib/docs/patterns/api.md', kind: 'catalog' }]);
				commitBoth();
				const committed = run(dir, 'approved', ...args, '--json');
				assert.equal(committed.status, 1, committed.stderr);
				assert.deepEqual(JSON.parse(committed.stdout).approved.paths, [{ path: 'lib/docs/patterns/api.md', kind: 'catalog' }]);
			} finally {
				rmSync(top, { recursive: true, force: true });
			}
		});

		it('a submodule that is needed and not checked out cannot be judged', () => {
			const { top, dir, lib, commitBoth, args } = rootWithSubmodule();
			try {
				put(lib, 'src/page.ts', '// @pattern api/read-query\nexport function page() {\n\treturn [];\n}\n');
				commitBoth();
				const clone = join(top, 'clone');
				git(top, 'clone', '-q', dir, clone);
				for (const command of ['code', 'approved', 'all']) {
					const r = run(clone, command, ...args);
					assert.equal(r.status, 2, `${command}: ${r.stdout}`);
					assert.match(r.stderr, /cannot judge: submodule lib is not checked out, so its files cannot be read or compared/);
				}
			} finally {
				rmSync(top, { recursive: true, force: true });
			}
		});
	});

	it('refuses a diagram tool that does not look inside submodules, where the repository has one', { skip: probeSub ? false : 'needs a c4ish that does' }, () => {
		const { top, dir, args } = rootWithSubmodule();
		try {
			// a stand-in for an older tool: the same report without the list of submodules it used
			const old = join(top, 'old-c4ish.mjs');
			const real = process.env.C4ISH ?? 'c4ish';
			writeFileSync(
				old,
				`#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
const r = spawnSync(${JSON.stringify(real)}, process.argv.slice(2), { encoding: 'utf8' });
let out = r.stdout;
if (process.argv[2] === 'code') { const j = JSON.parse(out); delete j.repositories; out = JSON.stringify(j); }
process.stdout.write(out); process.stderr.write(r.stderr); process.exit(r.status);
`,
				{ mode: 0o755 }
			);
			for (const command of ['code', 'approved']) {
				const r = spawnSync(process.execPath, [SCRIPT, command, ...args], { cwd: dir, encoding: 'utf8', env: { ...process.env, C4ISH: old } });
				assert.equal(r.status, 2, r.stdout);
				assert.match(r.stderr, /has git submodules, and the c4ish in use does not look inside them: update c4ish/);
			}
		} finally {
			rmSync(top, { recursive: true, force: true });
		}
	});
});

