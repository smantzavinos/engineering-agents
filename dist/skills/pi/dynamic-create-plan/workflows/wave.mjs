// Wave engine for code-mode execution.
//
// Pure, dependency-free helpers plus a builder that emits a `workflowScript`
// body for one wave. The parent owns the loop: it computes the ready set,
// invokes ONE workflowScript per wave, runs verification on the host, reviews,
// and commits a checkpoint. See docs/execution-patterns.md for why the loop
// cannot live inside a single script.
//
// Every rule encoded here was verified against the real runtime; see
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
