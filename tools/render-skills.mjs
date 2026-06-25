#!/usr/bin/env node
// Skill renderer: composes harness-specific skill trees from one canonical source.
//
// Canonical skills live in `skills/<name>/` and are harness-neutral. They may use
// two macros:
//   {{delegate:ROLE skill=SKILL}}prompt text{{/delegate}}  (block; SKILL optional)
//   {{note:KEY}}                                            (inline)
// Frontmatter must NOT hardcode `compatibility:` — the renderer injects it per harness.
//
// Harness profiles live in `harnesses/<id>.json` and map semantic roles to a concrete
// implementation (named subagent vs category) plus harness-specific notes.
//
// Output is written to `dist/skills/<harness-id>/<name>/` (checked in, drift-tested).
//
// Usage:
//   node tools/render-skills.mjs --write    Regenerate dist/ from canonical sources
//   node tools/render-skills.mjs --check    Verify dist/ matches a fresh render (no writes)

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, '..');
const SKILLS_DIR = path.join(REPO_ROOT, 'skills');
const HARNESS_DIR = path.join(REPO_ROOT, 'harnesses');
const DIST_DIR = path.join(REPO_ROOT, 'dist', 'skills');

const DELEGATE_RE = /^[ \t]*\{\{delegate:([A-Za-z0-9_-]+)(?:\s+skill=([A-Za-z0-9_-]+))?\}\}[ \t]*\n([\s\S]*?)\n[ \t]*\{\{\/delegate\}\}[ \t]*$/gm;
const NOTE_RE = /\{\{note:([A-Za-z0-9_-]+)\}\}/g;
const LEFTOVER_RE = /\{\{[^}]*\}\}/;

function fail(message) {
  process.stderr.write(`render-skills: ${message}\n`);
  process.exit(1);
}

function listDirs(dir) {
  return fs
    .readdirSync(dir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort((a, b) => a.localeCompare(b));
}

function loadHarnesses() {
  const harnesses = [];
  for (const file of fs.readdirSync(HARNESS_DIR).sort()) {
    if (!file.endsWith('.json')) continue;
    const profile = JSON.parse(fs.readFileSync(path.join(HARNESS_DIR, file), 'utf8'));
    if (!profile.id) fail(`harness profile ${file} is missing "id"`);
    harnesses.push(profile);
  }
  if (harnesses.length === 0) fail('no harness profiles found in harnesses/');
  return harnesses;
}

function normalizePrompt(body) {
  return body
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .join(' ');
}

function renderDelegate(harness, skillName, role, skill, prompt) {
  const def = harness.roles?.[role];
  if (!def) {
    fail(`skill "${skillName}": harness "${harness.id}" has no mapping for delegate role "${role}"`);
  }
  if (harness.delegationStyle === 'pi-subagent') {
    if (def.kind !== 'agent') {
      fail(`skill "${skillName}": harness "${harness.id}" role "${role}" must map to an agent for pi-subagent style`);
    }
    const lines = ['subagent({', `  agent: "${def.agent}",`];
    if (skill) {
      lines.push(`  task: "${prompt}",`);
      lines.push(`  skill: "${skill}"`);
    } else {
      lines.push(`  task: "${prompt}"`);
    }
    lines.push('})');
    return lines.join('\n');
  }
  if (harness.delegationStyle === 'opencode-task') {
    if (def.kind === 'category') {
      const loadSkills = skill ? `["${skill}"]` : '[]';
      return `task(category="${def.category}", load_skills=${loadSkills}, prompt="${prompt}")`;
    }
    if (def.kind === 'subagent_type') {
      const loadSkills = skill ? `["${skill}"]` : '[]';
      return `task(subagent_type="${def.subagent_type}", load_skills=${loadSkills}, prompt="${prompt}")`;
    }
    if (def.kind === 'agent') {
      let message = prompt;
      if (skill) {
        message += ` Read your skill file at ${harness.skillPathPrefix}${skill}/SKILL.md and follow its process.`;
      }
      return ['task({', `  agent: "${def.agent}",`, `  message: "${message}"`, '})'].join('\n');
    }
    fail(`skill "${skillName}": harness "${harness.id}" role "${role}" has unknown kind "${def.kind}"`);
  }
  fail(`harness "${harness.id}" has unknown delegationStyle "${harness.delegationStyle}"`);
  return '';
}

function splitFrontmatter(source, skillName) {
  if (!source.startsWith('---\n')) {
    fail(`skill "${skillName}": SKILL.md must start with YAML frontmatter`);
  }
  const end = source.indexOf('\n---\n', 4);
  if (end === -1) fail(`skill "${skillName}": unterminated frontmatter`);
  return {
    fmLines: source.slice(4, end + 1).split('\n'),
    rest: source.slice(end + 5),
  };
}

// Optional `harnesses: [a, b]` frontmatter restricts a skill to specific harnesses.
// Absent => the skill renders for every harness.
function skillHarnesses(source, skillName) {
  const { fmLines } = splitFrontmatter(source, skillName);
  for (const line of fmLines) {
    const match = line.match(/^harnesses:\s*\[(.*)\]\s*$/);
    if (match) {
      return match[1]
        .split(',')
        .map((value) => value.trim())
        .filter((value) => value.length > 0);
    }
  }
  return null;
}

function injectCompatibility(source, harness, skillName) {
  const { fmLines, rest } = splitFrontmatter(source, skillName);
  const kept = [];
  let descIndex = -1;
  for (const line of fmLines) {
    if (/^compatibility:/.test(line)) continue; // renderer owns compatibility
    if (/^harnesses:/.test(line)) continue; // applicability is build-time only
    kept.push(line);
    if (/^description:/.test(line)) descIndex = kept.length - 1;
  }
  if (descIndex === -1) fail(`skill "${skillName}": frontmatter missing "description"`);
  kept.splice(descIndex + 1, 0, `compatibility: ${harness.compatibility}`);
  // kept ends with a trailing empty string from the split; rebuild cleanly.
  const fmText = kept.filter((line, idx) => !(idx === kept.length - 1 && line === '')).join('\n');
  return `---\n${fmText}\n---\n${rest}`;
}

function renderSkill(source, harness, skillName) {
  let out = injectCompatibility(source, harness, skillName);
  out = out.replace(DELEGATE_RE, (match, role, skill, body) => {
    const prompt = normalizePrompt(body);
    return renderDelegate(harness, skillName, role, skill, prompt);
  });
  out = out.replace(NOTE_RE, (match, key) => {
    const value = harness.notes?.[key];
    if (value === undefined) {
      fail(`skill "${skillName}": harness "${harness.id}" has no note "${key}"`);
    }
    return value;
  });
  const leftover = out.match(LEFTOVER_RE);
  if (leftover) {
    fail(`skill "${skillName}": unexpanded macro "${leftover[0]}" for harness "${harness.id}"`);
  }
  return out;
}

// Build the in-memory rendered tree: { "<harness>/<name>/<relpath>": contents }
function buildRenderTree() {
  const harnesses = loadHarnesses();
  const skills = listDirs(SKILLS_DIR).filter((name) =>
    fs.existsSync(path.join(SKILLS_DIR, name, 'SKILL.md')),
  );
  const tree = new Map();
  for (const harness of harnesses) {
    for (const skill of skills) {
      const skillDir = path.join(SKILLS_DIR, skill);
      const source = fs.readFileSync(path.join(skillDir, 'SKILL.md'), 'utf8');
      const applicable = skillHarnesses(source, skill);
      if (applicable && !applicable.includes(harness.id)) continue;
      const rendered = renderSkill(source, harness, skill);
      tree.set(path.join(harness.id, skill, 'SKILL.md'), rendered);
      // Copy supporting files (references/, templates/, etc.) verbatim.
      for (const rel of walkFiles(skillDir)) {
        if (rel === 'SKILL.md') continue;
        tree.set(path.join(harness.id, skill, rel), fs.readFileSync(path.join(skillDir, rel)));
      }
    }
  }
  return tree;
}

function walkFiles(root, prefix = '') {
  const result = [];
  for (const entry of fs.readdirSync(path.join(root, prefix), { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    const rel = prefix ? path.join(prefix, entry.name) : entry.name;
    if (entry.isDirectory()) result.push(...walkFiles(root, rel));
    else if (entry.isFile()) result.push(rel);
  }
  return result;
}

function writeTree(tree) {
  fs.rmSync(DIST_DIR, { recursive: true, force: true });
  for (const [rel, contents] of [...tree.entries()].sort((a, b) => a[0].localeCompare(b[0]))) {
    const dest = path.join(DIST_DIR, rel);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.writeFileSync(dest, contents);
  }
  process.stdout.write(`render-skills: wrote ${tree.size} file(s) to dist/skills/\n`);
}

function checkTree(tree) {
  const drift = [];
  for (const [rel, contents] of tree.entries()) {
    const dest = path.join(DIST_DIR, rel);
    if (!fs.existsSync(dest)) {
      drift.push(`missing: dist/skills/${rel}`);
      continue;
    }
    const onDisk = fs.readFileSync(dest);
    const expected = Buffer.isBuffer(contents) ? contents : Buffer.from(contents);
    if (!onDisk.equals(expected)) drift.push(`changed: dist/skills/${rel}`);
  }
  // Detect stray files in dist that the render no longer produces.
  const expectedPaths = new Set([...tree.keys()].map((rel) => path.join(DIST_DIR, rel)));
  for (const file of existingDistFiles()) {
    if (!expectedPaths.has(file)) drift.push(`stale: ${path.relative(REPO_ROOT, file)}`);
  }
  if (drift.length > 0) {
    process.stderr.write('render-skills: dist/ is out of date. Run `node tools/render-skills.mjs --write`.\n');
    for (const line of drift.sort()) process.stderr.write(`  ${line}\n`);
    process.exit(1);
  }
  process.stdout.write(`render-skills: dist/skills/ is up to date (${tree.size} file(s)).\n`);
}

function existingDistFiles() {
  if (!fs.existsSync(DIST_DIR)) return [];
  const result = [];
  const stack = [DIST_DIR];
  while (stack.length > 0) {
    const dir = stack.pop();
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) stack.push(full);
      else result.push(full);
    }
  }
  return result;
}

function main() {
  const mode = process.argv[2];
  if (mode !== '--write' && mode !== '--check') {
    fail('usage: render-skills.mjs --write | --check');
  }
  const tree = buildRenderTree();
  if (mode === '--write') writeTree(tree);
  else checkTree(tree);
}

main();
