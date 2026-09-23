#!/usr/bin/env node
// Plan gate: validate <plan-dir>/tasks.json and its agreement with plan.md.
//
//   node check-plan.mjs <plan-dir> [--json]
//
// Exit 0 when the plan is executable, 1 when it is not. Rules are documented in
// docs/approaches/parallel.md and the create-plan skill tasks schema. Graph and
// fence validation is shared with workflows/wave.mjs.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { resolveFenceGroups, validateFenceGroups, validateGraph } from '../workflows/wave.mjs';

const VALID_CLASSES = ['contract', 'characterization', 'check', 'none'];
const SCHEMA_VERSION = 1;

/** Parse the deliberately small write-set glob dialect. */
function parseWriteSpec(spec) {
  if (typeof spec !== 'string' || spec.trim() === '') {
    return { error: 'must be a non-empty repository-relative path' };
  }
  const normalized = spec.replace(/^\.\//, '').replace(/\/+$/, '');
  if (path.posix.isAbsolute(normalized) || normalized.includes('\\')) {
    return { error: 'must be a repository-relative POSIX path' };
  }
  const parts = normalized.split('/');
  if (parts.some((part) => part === '' || part === '.' || part === '..')) {
    return { error: 'must stay within the repository as a repository-relative path' };
  }
  if (parts.some((part) => part.includes('*') && part !== '*')) {
    return { error: 'supports wildcard * only as a whole path segment; ** and partial-segment globs are unsupported' };
  }
  if (/[?\[\]{}]/.test(normalized)) {
    return { error: 'supports only the whole path segment wildcard *; ?, [], and {} are unsupported' };
  }
  return { normalized, parts };
}

/** Two write specs conflict when their paths or possible descendant paths overlap. */
function writesCollide(a, b) {
  const pa = parseWriteSpec(a);
  const pb = parseWriteSpec(b);
  if (pa.error || pb.error) return false;
  const sharedLength = Math.min(pa.parts.length, pb.parts.length);
  for (let index = 0; index < sharedLength; index += 1) {
    const sa = pa.parts[index];
    const sb = pb.parts[index];
    if (sa !== sb && sa !== '*' && sb !== '*') return false;
  }
  return true;
}

/** Map every task to the set of tasks it transitively depends on. */
function ancestorMap(tasks) {
  const direct = new Map(tasks.map((t) => [t.id, (t.deps ?? []).slice()]));
  const cache = new Map();
  const resolve = (id, seen) => {
    if (cache.has(id)) return cache.get(id);
    if (seen.has(id)) return new Set();
    seen.add(id);
    const out = new Set();
    for (const dep of direct.get(id) ?? []) {
      out.add(dep);
      for (const up of resolve(dep, seen)) out.add(up);
    }
    seen.delete(id);
    cache.set(id, out);
    return out;
  };
  return new Map(tasks.map((t) => [t.id, resolve(t.id, new Set())]));
}

/** Task IDs referenced by the plan's Task Overview table. */
function planTaskIds(markdown) {
  const ids = new Set();
  const lines = markdown.split('\n');
  const heading = lines.findIndex((line) => /^##\s+Task Overview\s*#*\s*$/i.test(line));
  if (heading === -1) return ids;

  for (const line of lines.slice(heading + 1)) {
    if (/^#{1,2}\s+/.test(line)) break;
    const match = line.match(/^\s*\|\s*([A-Za-z][A-Za-z0-9_-]*)\s*\|/);
    if (!match || match[1] === 'ID') continue;
    ids.add(match[1]);
  }
  return ids;
}

export function checkPlan(planDir) {
  const errors = [];
  const push = (msg) => errors.push(msg);

  if (!fs.existsSync(planDir) || !fs.statSync(planDir).isDirectory()) {
    return [`plan directory not found: ${planDir}`];
  }
  const planPath = path.join(planDir, 'plan.md');
  const tasksPath = path.join(planDir, 'tasks.json');
  if (!fs.existsSync(planPath)) push(`missing plan.md in ${planDir}`);
  if (!fs.existsSync(tasksPath)) push(`missing tasks.json in ${planDir}`);
  if (errors.length > 0) return errors;

  let doc;
  try {
    doc = JSON.parse(fs.readFileSync(tasksPath, 'utf8'));
  } catch (error) {
    return [`tasks.json is not valid JSON: ${error.message}`];
  }

  if (doc?.schema !== SCHEMA_VERSION) {
    push(`tasks.json schema must be ${SCHEMA_VERSION}, got ${JSON.stringify(doc?.schema)}`);
  }
  for (const tier of ['cheap', 'strong']) {
    const value = doc?.models?.[tier];
    if (typeof value !== 'string' || value.trim() === '') {
      push(`models.${tier} must be a non-empty string; the engine sets model explicitly on every child`);
    }
  }
  if (doc?.maxWidth !== undefined && !(Number.isInteger(doc.maxWidth) && doc.maxWidth > 0)) {
    push(`maxWidth must be a positive integer, got ${JSON.stringify(doc.maxWidth)}`);
  }

  const tasks = Array.isArray(doc?.tasks) ? doc.tasks : null;
  if (!tasks) {
    push('tasks.json must contain a "tasks" array');
    return errors;
  }

  // Rule 1 — shared with the execution engine.
  for (const message of validateGraph(tasks)) push(message);
  for (const message of validateFenceGroups(doc)) push(message);

  for (const [index, t] of tasks.entries()) {
    const id = typeof t?.id === 'string' && t.id ? t.id : `task at index ${index}`;

    if (!VALID_CLASSES.includes(t?.class)) {
      push(`task "${id}" has invalid class ${JSON.stringify(t?.class)}; expected one of ${VALID_CLASSES.join(', ')}`);
      continue;
    }
    // Rule 2 — nothing to freeze means the implementer could edit the oracle.
    if (t.class === 'contract') {
      const paths = t.testPaths;
      if (!Array.isArray(paths) || paths.length === 0) {
        push(`task "${id}" has class "contract" but declares no testPaths to freeze`);
      }
    }
    // Rule 3 — "done" must be a command.
    if (t.class !== 'none') {
      if (typeof t.verify !== 'string' || t.verify.trim() === '') {
        push(`task "${id}" has class "${t.class}" but declares no verify command`);
      }
    }
    if (t.writes !== undefined && !Array.isArray(t.writes)) {
      push(`task "${id}" writes must be an array of paths`);
    } else {
      for (const spec of t.writes ?? []) {
        const parsed = parseWriteSpec(spec);
        if (parsed.error) push(`task "${id}" write spec ${JSON.stringify(spec)} ${parsed.error}`);
      }
    }
  }

  // Rule 4 — shared-tree safety. Two tasks may run concurrently only when they
  // share a fence group and neither transitively depends on the other.
  const identified = tasks.filter((t) => typeof t?.id === 'string' && t.id);
  const ancestors = ancestorMap(identified);
  const groupOf = new Map();
  for (const group of resolveFenceGroups(doc)) {
    for (const id of group.tasks) groupOf.set(id, group.id);
  }
  for (let i = 0; i < identified.length; i += 1) {
    for (let j = i + 1; j < identified.length; j += 1) {
      const a = identified[i];
      const b = identified[j];
      if (groupOf.get(a.id) !== groupOf.get(b.id)) continue;
      if (ancestors.get(a.id)?.has(b.id) || ancestors.get(b.id)?.has(a.id)) continue;
      for (const wa of a.writes ?? []) {
        for (const wb of b.writes ?? []) {
          if (writesCollide(wa, wb)) {
            push(
              `tasks "${a.id}" and "${b.id}" can run concurrently in fence group "${groupOf.get(a.id)}" and both write ${wa === wb ? wa : `${wa} / ${wb}`}; add a dependency, split fence groups, or merge them`,
            );
          }
        }
      }
    }
  }

  // Rule 5 — the document a human approved must match the graph a machine runs.
  const declared = new Set(identified.map((t) => t.id));
  const referenced = planTaskIds(fs.readFileSync(planPath, 'utf8'));
  for (const id of referenced) {
    if (!declared.has(id)) push(`plan.md references task "${id}" which is absent from tasks.json`);
  }
  for (const id of declared) {
    if (!referenced.has(id)) push(`tasks.json declares task "${id}" which is absent from the plan.md Task Overview`);
  }

  return errors;
}

let invokedDirectly = false;
if (process.argv[1]) {
  try {
    invokedDirectly = fs.realpathSync(path.resolve(process.argv[1])) ===
      fs.realpathSync(fileURLToPath(import.meta.url));
  } catch {
    invokedDirectly = false;
  }
}

if (invokedDirectly) {
  const args = process.argv.slice(2);
  const json = args.includes('--json');
  const target = args.find((a) => !a.startsWith('--'));

  if (!target) {
    process.stderr.write('usage: check-plan.mjs <plan-dir> [--json]\n');
    process.exit(1);
  }

  let errors;
  try {
    errors = checkPlan(target);
  } catch (error) {
    errors = [`plan check failed: ${error.message}`];
  }

  if (json) {
    process.stdout.write(`${JSON.stringify({ ok: errors.length === 0, errors })}\n`);
  } else if (errors.length === 0) {
    process.stdout.write(`plan check ok: ${target}\n`);
  } else {
    for (const message of errors) process.stderr.write(`${message}\n`);
  }
  process.exit(errors.length === 0 ? 0 : 1);
}
