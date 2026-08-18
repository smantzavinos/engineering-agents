#!/usr/bin/env node
// Plan gate: validate <plan-dir>/tasks.json and its agreement with plan.md.
//
//   node tools/check-plan.mjs <plan-dir> [--json]
//
// Exit 0 when the plan is executable, 1 when it is not. Rules are documented in
// skills/create-plan/references/tasks-schema.md. Graph validation is shared with
// workflows/wave.mjs so a plan cannot pass this gate and fail at execution.

import fs from 'node:fs';
import path from 'node:path';
import { validateGraph } from '../workflows/wave.mjs';

const VALID_CLASSES = ['contract', 'characterization', 'check', 'none'];
const SCHEMA_VERSION = 1;

/** Expand a declared write path into a matcher. Globs are supported loosely. */
function toMatcher(spec) {
  const normalized = String(spec).replace(/^\.\//, '').replace(/\/+$/, '');
  const source = normalized
    .split('*')
    .map((part) => part.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'))
    .join('[^/]*');
  return { normalized, re: new RegExp(`^${source}$`) };
}

/** Two write specs conflict if either matches the other, or one contains the other. */
function writesCollide(a, b) {
  const ma = toMatcher(a);
  const mb = toMatcher(b);
  if (ma.normalized === mb.normalized) return true;
  if (ma.re.test(mb.normalized) || mb.re.test(ma.normalized)) return true;
  return (
    mb.normalized.startsWith(`${ma.normalized}/`) ||
    ma.normalized.startsWith(`${mb.normalized}/`)
  );
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
  for (const line of markdown.split('\n')) {
    const m = line.match(/^\s*\|\s*([A-Za-z][A-Za-z0-9_-]*)\s*\|/);
    if (!m) continue;
    const id = m[1];
    if (id === 'ID' || /^-+$/.test(id)) continue;
    ids.add(id);
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
    }
  }

  // Rule 4 — the check that makes shared-tree parallelism safe. Two tasks may run
  // concurrently unless one transitively depends on the other.
  const identified = tasks.filter((t) => typeof t?.id === 'string' && t.id);
  const ancestors = ancestorMap(identified);
  for (let i = 0; i < identified.length; i += 1) {
    for (let j = i + 1; j < identified.length; j += 1) {
      const a = identified[i];
      const b = identified[j];
      if (ancestors.get(a.id)?.has(b.id) || ancestors.get(b.id)?.has(a.id)) continue;
      for (const wa of a.writes ?? []) {
        for (const wb of b.writes ?? []) {
          if (writesCollide(wa, wb)) {
            push(
              `tasks "${a.id}" and "${b.id}" can run in the same wave and both write ${wa === wb ? wa : `${wa} / ${wb}`}; add a dependency or merge them`,
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

const invokedDirectly = process.argv[1] &&
  path.resolve(process.argv[1]) === path.resolve(new URL(import.meta.url).pathname);

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
