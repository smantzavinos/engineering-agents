// Parallel execution helpers.
//
// The scheduler is a DAG. The parent runs one generated workflowScript per
// planned fence group, then host-verifies and commits. See
// docs/approaches/parallel.md. readySet / buildWaveScript remain for older
// tests; new execution uses resolveFenceGroups + buildGroupScript.
//
// Runtime constraints were verified in
// docs/investigations/2026-08-18-code-mode-process/spike.md.

/** Agent used for UI-facing work. */
const UI_AGENT = 'ui-worker';
/** Agent used for everything else. */
const DEFAULT_AGENT = 'worker';

/**
 * Validate a task graph.
 * @returns {string[]} error strings; empty means valid.
 */
export function validateGraph(tasks) {
  const errors = [];
  if (!Array.isArray(tasks)) return ['task graph must be an array'];

  const seen = new Set();
  for (const [index, task] of tasks.entries()) {
    const label = task && task.id ? `task "${task.id}"` : `task at index ${index}`;
    if (!task || typeof task.id !== 'string' || task.id === '') {
      errors.push(`${label} is missing a string "id"`);
      continue;
    }
    if (typeof task.brief !== 'string' || task.brief === '') {
      errors.push(`${label} is missing a string "brief"`);
    }
    if (seen.has(task.id)) errors.push(`duplicate task id "${task.id}"`);
    seen.add(task.id);
  }

  for (const task of tasks) {
    if (!task || typeof task.id !== 'string') continue;
    for (const dep of task.deps ?? []) {
      if (!seen.has(dep)) errors.push(`task "${task.id}" depends on unknown id "${dep}"`);
    }
  }

  // Cycle detection: iteratively strip tasks whose deps are all satisfied.
  // Whatever cannot be stripped participates in, or is blocked by, a cycle.
  const known = tasks.filter((t) => t && typeof t.id === 'string');
  const resolved = new Set();
  let progressed = true;
  while (progressed) {
    progressed = false;
    for (const task of known) {
      if (resolved.has(task.id)) continue;
      const deps = task.deps ?? [];
      if (deps.every((d) => resolved.has(d) || !seen.has(d))) {
        resolved.add(task.id);
        progressed = true;
      }
    }
  }
  const cyclic = known.filter((t) => !resolved.has(t.id)).map((t) => t.id);
  if (cyclic.length > 0) {
    errors.push(`dependency cycle among: ${cyclic.join(', ')}`);
  }

  return errors;
}

/**
 * Tasks whose dependencies are all satisfied, excluding completed ones.
 * Input order is preserved so waves are deterministic.
 */
export function readySet(tasks, done, maxWidth) {
  const complete = done instanceof Set ? done : new Set(done ?? []);
  const limit = Number.isInteger(maxWidth) && maxWidth > 0 ? maxWidth : tasks.length;
  return tasks
    .filter((task) => !complete.has(task.id))
    .filter((task) => (task.deps ?? []).every((dep) => complete.has(dep)))
    .slice(0, limit);
}

/**
 * Classify a child failure so the parent does not spend a strong retry on a
 * configuration error or a reporting-format error.
 * @returns {"acceptance"|"model"|"spawn-budget"|"failure"}
 */
export function classifyFailure(errorString) {
  const text = typeof errorString === 'string' ? errorString : '';
  if (text.includes('Acceptance rejected:')) return 'acceptance';
  if (text.includes('Unknown subagent model')) return 'model';
  const fanout = text.match(/Run fan-out:\s*(\d+)\s*\/\s*(\d+)\s*used/);
  if (fanout && Number(fanout[1]) >= Number(fanout[2])) return 'spawn-budget';
  return 'failure';
}

/**
 * Build the `workflowScript` body for one wave.
 *
 * Deliberate constraints, each verified against the runtime:
 *  - `runs.all` only. `runs.run` throws on failure and aborts in-flight
 *    siblings, so a single bad child would destroy the wave.
 *  - No `gate:`. It implies acceptance level "verified", whose evidence
 *    validation short-circuits before the command result is consulted.
 *  - No `turnBudget` / `toolBudget` on writers.
 *  - No `async function` helpers; they are rejected as non-portable.
 *  - Task data is embedded with JSON.stringify, so briefs containing quotes,
 *    backticks, backslashes, newlines or `${}` cannot break the script.
 */
export function buildWaveScript(tasks, opts = {}) {
  const { cheapModel, strongModel } = opts;
  if (typeof cheapModel !== 'string' || cheapModel === '') {
    throw new Error('buildWaveScript requires opts.cheapModel');
  }
  if (typeof strongModel !== 'string' || strongModel === '') {
    throw new Error('buildWaveScript requires opts.strongModel');
  }

  const children = tasks.map((task) => {
    const child = {
      key: `impl-${task.id}`,
      agent: task.ui ? UI_AGENT : DEFAULT_AGENT,
      // Explicit per child: an unresolved default model fails the child before
      // it starts, and the flake default is not resolvable everywhere.
      model: task.class === 'complex' ? strongModel : cheapModel,
      task: task.brief,
    };
    if (Number.isInteger(task.timeoutMs) && task.timeoutMs > 0) {
      // The runtime default is 30 minutes per child; longer work must opt up.
      child.timeoutMs = task.timeoutMs;
    }
    return child;
  });

  return `return runs.all(${JSON.stringify(children, null, 2)});`;
}

/**
 * Planned fence groups, or one implicit group of every task.
 * @returns {Array<{id: string, tasks: string[]}>}
 */
export function resolveFenceGroups(doc) {
  const tasks = Array.isArray(doc?.tasks) ? doc.tasks : [];
  const ids = tasks
    .filter((task) => task && typeof task.id === 'string' && task.id)
    .map((task) => task.id);
  if (!Array.isArray(doc?.fenceGroups) || doc.fenceGroups.length === 0) {
    return [{ id: 'all', tasks: ids }];
  }
  return doc.fenceGroups.map((group, index) => ({
    id: typeof group?.id === 'string' && group.id ? group.id : `group-${index}`,
    tasks: Array.isArray(group?.tasks) ? group.tasks.slice() : [],
  }));
}

/**
 * Validate optional fenceGroups on a tasks.json document.
 * @returns {string[]} error strings; empty means valid or omitted.
 */
export function validateFenceGroups(doc) {
  const errors = [];
  if (doc?.fenceGroups === undefined) return errors;
  if (!Array.isArray(doc.fenceGroups) || doc.fenceGroups.length === 0) {
    errors.push('fenceGroups must be a non-empty array when present');
    return errors;
  }

  const known = new Set(
    (Array.isArray(doc.tasks) ? doc.tasks : [])
      .filter((task) => task && typeof task.id === 'string' && task.id)
      .map((task) => task.id),
  );
  const seenGroup = new Set();
  const seenTask = new Map();

  doc.fenceGroups.forEach((group, index) => {
    const label = group && typeof group.id === 'string' && group.id
      ? `fence group "${group.id}"`
      : `fence group at index ${index}`;
    if (typeof group?.id !== 'string' || group.id === '') {
      errors.push(`${label} is missing a string "id"`);
    } else if (seenGroup.has(group.id)) {
      errors.push(`duplicate fence group id "${group.id}"`);
    } else {
      seenGroup.add(group.id);
    }
    if (!Array.isArray(group?.tasks) || group.tasks.length === 0) {
      errors.push(`${label} must list at least one task`);
      return;
    }
    for (const id of group.tasks) {
      if (typeof id !== 'string' || id === '') {
        errors.push(`${label} contains a non-string task id`);
        continue;
      }
      if (!known.has(id)) errors.push(`${label} references unknown task "${id}"`);
      if (seenTask.has(id)) {
        errors.push(`task "${id}" appears in fence groups "${seenTask.get(id)}" and "${group.id}"`);
      } else {
        seenTask.set(id, group?.id ?? label);
      }
    }
  });

  for (const id of known) {
    if (!seenTask.has(id)) errors.push(`task "${id}" is not in any fence group`);
  }

  const groupIndex = new Map();
  doc.fenceGroups.forEach((group, index) => {
    for (const id of group?.tasks ?? []) groupIndex.set(id, index);
  });
  for (const task of Array.isArray(doc.tasks) ? doc.tasks : []) {
    if (!task || typeof task.id !== 'string') continue;
    const here = groupIndex.get(task.id);
    if (here === undefined) continue;
    for (const dep of task.deps ?? []) {
      const there = groupIndex.get(dep);
      if (there !== undefined && there > here) {
        errors.push(
          `task "${task.id}" in an earlier fence group depends on "${dep}" in a later group`,
        );
      }
    }
  }

  return errors;
}

function intraDeps(task, groupIds) {
  return (task.deps ?? []).filter((dep) => groupIds.has(dep));
}

function topoTasks(tasks) {
  const groupIds = new Set(tasks.map((task) => task.id));
  const remaining = new Map(tasks.map((task) => [task.id, task]));
  const ordered = [];
  while (remaining.size > 0) {
    const ready = [...remaining.values()].filter((task) =>
      intraDeps(task, groupIds).every((dep) => !remaining.has(dep)),
    );
    if (ready.length === 0) {
      ordered.push(...remaining.values());
      break;
    }
    for (const task of ready) {
      ordered.push(task);
      remaining.delete(task.id);
    }
  }
  return ordered;
}

function childSpec(task, cheapModel, strongModel) {
  const spec = {
    key: `impl-${task.id}`,
    agent: task.ui ? UI_AGENT : DEFAULT_AGENT,
    model: task.class === 'contract' ? strongModel : cheapModel,
    task: task.brief,
  };
  if (Number.isInteger(task.timeoutMs) && task.timeoutMs > 0) {
    spec.timeoutMs = task.timeoutMs;
  }
  return spec;
}

/**
 * Build a DAG workflowScript for one fence group.
 * Intra-group deps become promise joins; a task starts when those deps finish,
 * not when the whole group is ready.
 */
export function buildGroupScript(tasks, opts = {}) {
  const { cheapModel, strongModel, freezeCommit = '' } = opts;
  if (typeof cheapModel !== 'string' || cheapModel === '') {
    throw new Error('buildGroupScript requires opts.cheapModel');
  }
  if (typeof strongModel !== 'string' || strongModel === '') {
    throw new Error('buildGroupScript requires opts.strongModel');
  }
  if (!Array.isArray(tasks) || tasks.length === 0) {
    throw new Error('buildGroupScript requires a non-empty tasks array');
  }

  const payload = tasks.map((task) => ({
    id: task.id,
    brief: task.brief,
    deps: intraDeps(task, new Set(tasks.map((item) => item.id))),
    writes: task.writes ?? [],
    class: task.class,
    verify: task.verify,
    testPaths: task.testPaths ?? [],
    ui: !!task.ui,
    timeoutMs: task.timeoutMs,
    child: childSpec(task, cheapModel, strongModel),
  }));

  const ordered = topoTasks(tasks);
  const lines = [
    `const FREEZE = ${JSON.stringify(freezeCommit)};`,
    `const TASKS = ${JSON.stringify(payload, null, 2)};`,
    'const byId = {};',
    'for (const t of TASKS) byId[t.id] = t;',
    'function footer(t) {',
    '  var lines = ["", "WRITE-SET (you may modify only these): " + JSON.stringify(t.writes)];',
    '  if (t.verify) lines.push("After implementing, run exactly: " + t.verify);',
    '  if (t.class === "contract" && t.testPaths.length && FREEZE) {',
    '    lines.push("and: git diff --exit-code " + FREEZE + " -- " + t.testPaths.join(" "));',
    '    lines.push("Do not edit frozen test files; report a mismatch instead.");',
    '  }',
    '  lines.push("Never run git commit or any state-changing git command.");',
    '  return lines.join("\\n");',
    '}',
    'function child(t) {',
    '  var spec = {};',
    '  for (var key in t.child) spec[key] = t.child[key];',
    '  spec.task = t.brief + footer(t);',
    '  return spec;',
    '}',
    'function launch(t) { return runs.all([child(t)]); }',
    'function ok(r) {',
    '  if (Array.isArray(r)) return !!(r[0] && r[0].ok === true);',
    '  if (r && r.results) {',
    '    var keys = Object.keys(r.results);',
    '    return keys.length > 0 && keys.every(function (k) { return r.results[k] && r.results[k].ok; });',
    '  }',
    '  return !!(r && r.ok === true);',
    '}',
    'var p = {};',
  ];

  const groupIds = new Set(tasks.map((task) => task.id));
  for (const task of ordered) {
    const deps = intraDeps(task, groupIds);
    const launchCall = `launch(byId[${JSON.stringify(task.id)}])`;
    if (deps.length === 0) {
      lines.push(`p[${JSON.stringify(task.id)}] = ${launchCall};`);
    } else if (deps.length === 1) {
      lines.push(
        `p[${JSON.stringify(task.id)}] = p[${JSON.stringify(deps[0])}].then(function (r) { return ok(r) ? ${launchCall} : r; });`,
      );
    } else {
      const list = deps.map((dep) => `p[${JSON.stringify(dep)}]`).join(', ');
      lines.push(
        `p[${JSON.stringify(task.id)}] = Promise.all([${list}]).then(function (rs) { return rs.every(ok) ? ${launchCall} : rs.find(function (r) { return !ok(r); }); });`,
      );
    }
  }

  const all = ordered.map((task) => `p[${JSON.stringify(task.id)}]`).join(', ');
  lines.push(`return Promise.all([${all}]).then(function (rs) {`);
  lines.push('  return { ok: rs.every(ok), results: rs };');
  lines.push('});');
  return `${lines.join('\n')}\n`;
}
