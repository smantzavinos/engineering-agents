#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { TextDecoder } from 'node:util';

const SCHEMA_VERSION = 1;
const MAX_EVIDENCE_BYTES = 102400;
const LANES = new Set(['cheap', 'std', 'complex', 'visual', 'visual-complex']);
const RISKS = new Set(['migration', 'destructive', 'auth', 'api-contract']);
const RUNTIME_ENTRIES = ['plan.json', 'plan.md', 'tasks', 'blocks', 'artifacts', 'planning-progress.md', 'planning-outline.md'];
const TABLES = {
  Contracts: ['ID', 'Behavior', 'Evidence'],
  Decisions: ['ID', 'Decision', 'Resolution'],
  Checks: ['ID', 'Scope', 'Command', 'Cost', 'Worker-safe'],
  Tasks: ['ID', 'Deps', 'Lane', 'Estimate min', 'Risk labels', 'Integration', 'Deliverable', 'Write set', 'Contracts', 'Decisions', 'Check'],
};

function numericIdCompare(a, b) {
  const ad = a.replace(/^\D+/, '');
  const bd = b.replace(/^\D+/, '');
  return ad.length - bd.length || (ad < bd ? -1 : ad > bd ? 1 : 0) || (a < b ? -1 : a > b ? 1 : 0);
}
function lexicalCompare(a, b) { return a < b ? -1 : a > b ? 1 : 0; }
function sequenceCompare(a, b) {
  for (let i = 0; i < Math.min(a.length, b.length); i += 1) {
    const compared = numericIdCompare(a[i], b[i]);
    if (compared) return compared;
  }
  return a.length - b.length;
}
function diagnosticCompare(a, b) {
  return lexicalCompare(a.code, b.code) || lexicalCompare(a.location.section, b.location.section) ||
    a.location.row - b.location.row || lexicalCompare(a.location.field, b.location.field) || lexicalCompare(a.message, b.message);
}
function hash(value) { return crypto.createHash('sha256').update(value).digest('hex'); }
function exists(pathname) { try { fs.lstatSync(pathname); return true; } catch (error) { if (error.code === 'ENOENT') return false; throw error; } }
function inside(root, target) { const relative = path.relative(root, target); return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative)); }

function readUtf8(filename) {
  const bytes = fs.readFileSync(filename);
  return { bytes, text: new TextDecoder('utf-8', { fatal: true }).decode(bytes).replace(/\r\n/g, '\n') };
}

function compilePlan(filename, writeRoot = process.cwd()) {
  const diagnostics = [];
  let sortedTasks = [];
  let groups = [];
  const add = (code, message, section = 'Plan', row = 1, field = '') => diagnostics.push({ code, message, location: { section, row, field } });
  let text;
  try { ({ text } = readUtf8(filename)); }
  catch (error) {
    add('PLAN_IO', `cannot read UTF-8 plan: ${error.message}`);
    return result(2);
  }
  if (text.includes('\r')) add('PLAN_LINE_ENDING', 'bare carriage returns are unsupported');
  const lines = text.split('\n');
  if (lines.at(-1) === '') lines.pop();
  const headings = [];
  lines.forEach((line, index) => { if (line.startsWith('## ')) headings.push({ name: line.slice(3), row: index + 1, index }); });
  const expectedSections = Object.keys(TABLES);
  for (const name of expectedSections) {
    const matches = headings.filter((heading) => heading.name === name);
    if (matches.length !== 1) add(matches.length ? 'PLAN_DUPLICATE_SECTION' : 'PLAN_MISSING_SECTION', `${name} section must occur exactly once`, name, matches[0]?.row ?? 1, 'section');
  }
  for (const heading of headings) if (!expectedSections.includes(heading.name)) add('PLAN_UNKNOWN_SECTION', `unsupported section ${heading.name}`, heading.name, heading.row, 'section');
  if (headings.length !== 4 || headings.some((heading, index) => heading.name !== expectedSections[index])) add('PLAN_SECTION_ORDER', 'sections must be Contracts, Decisions, Checks, Tasks in that order', 'Plan', 1, 'section');

  if (!/^# .+/.test(lines[0] ?? '')) add('PLAN_TITLE', 'a non-empty level-one title is required', 'Plan', 1, 'title');
  const firstHeading = headings[0]?.index ?? lines.length;
  const metadata = new Map();
  for (let index = 1; index < firstHeading; index += 1) {
    if (lines[index] === '') continue;
    const match = /^(Plan schema|Intent|Approval): (.*)$/.exec(lines[index]);
    if (!match) { add('PLAN_PREAMBLE', 'unsupported preamble content', 'Plan', index + 1, 'preamble'); continue; }
    if (metadata.has(match[1])) add('PLAN_DUPLICATE_FIELD', `${match[1]} occurs more than once`, 'Plan', index + 1, match[1]);
    else metadata.set(match[1], { value: match[2], row: index + 1 });
  }
  for (const field of ['Plan schema', 'Intent', 'Approval']) if (!metadata.has(field) || !metadata.get(field).value) add('PLAN_REQUIRED_FIELD', `${field} is required`, 'Plan', metadata.get(field)?.row ?? 1, field);
  if (metadata.get('Plan schema')?.value !== '1') add('PLAN_SCHEMA', 'only Plan schema: 1 is supported', 'Plan', metadata.get('Plan schema')?.row ?? 1, 'Plan schema');
  if (metadata.has('Approval') && !['auto', 'requested'].includes(metadata.get('Approval').value)) add('PLAN_APPROVAL', 'Approval must be auto or requested', 'Plan', metadata.get('Approval').row, 'Approval');

  const parsed = {};
  if (headings.length === 4 && headings.every((heading, index) => heading.name === expectedSections[index])) {
    for (let sectionIndex = 0; sectionIndex < headings.length; sectionIndex += 1) {
      const heading = headings[sectionIndex];
      const end = headings[sectionIndex + 1]?.index ?? lines.length;
      parsed[heading.name] = parseTable(lines, heading, end, TABLES[heading.name], add);
    }
  }
  if (diagnostics.length) return result(2);

  const contracts = parseReferenceRows(parsed.Contracts, /^C[1-9][0-9]*$/, 'Contracts', add);
  const decisions = parseReferenceRows(parsed.Decisions, /^D[1-9][0-9]*$/, 'Decisions', add);
  const checks = parseChecks(parsed.Checks, add);
  const tasks = parseTasks(parsed.Tasks, writeRoot, add);
  if (!tasks.length) add('PLAN_TASKS_EMPTY', 'at least one task is required', 'Tasks', parsed.Tasks.headingRow, 'table');
  validateUnique(contracts, 'Contracts', add);
  validateUnique(decisions, 'Decisions', add);
  validateUnique(checks, 'Checks', add);
  validateUnique(tasks, 'Tasks', add);

  const contractMap = new Map(contracts.map((entry) => [entry.id, entry]));
  const decisionMap = new Map(decisions.map((entry) => [entry.id, entry]));
  const checkMap = new Map(checks.map((entry) => [entry.id, entry]));
  const taskMap = new Map(tasks.map((entry) => [entry.id, entry]));
  for (const task of tasks) {
    for (const dependency of task.deps) if (!taskMap.has(dependency)) add('PLAN_DANGLING_DEPENDENCY', `${task.id} references missing dependency ${dependency}`, 'Tasks', task.row, 'Deps');
    for (const id of task.contracts) if (!contractMap.has(id)) add('PLAN_DANGLING_CONTRACT', `${task.id} references missing contract ${id}`, 'Tasks', task.row, 'Contracts');
    for (const id of task.decisions) if (!decisionMap.has(id)) add('PLAN_DANGLING_DECISION', `${task.id} references missing decision ${id}`, 'Tasks', task.row, 'Decisions');
    const check = checkMap.get(task.check);
    if (!check) add('PLAN_DANGLING_CHECK', `${task.id} references missing check ${task.check}`, 'Tasks', task.row, 'Check');
    else if (check.scope !== 'worker' || check.workerSafe !== 'yes') add('PLAN_WORKER_CHECK', `${task.id} check must have worker scope and Worker-safe yes`, 'Tasks', task.row, 'Check');
  }
  groups = [...new Set(tasks.map((task) => task.integration))].sort(numericIdCompare);
  for (const group of groups) {
    const groupChecks = checks.filter((check) => check.scope === `integration:${group}`);
    if (groupChecks.length !== 1) add('PLAN_INTEGRATION_CHECK', `${group} must have exactly one integration check`, 'Checks', groupChecks[0]?.row ?? parsed.Checks.headingRow, 'Scope');
  }
  for (const check of checks.filter((entry) => entry.scope.startsWith('integration:'))) {
    const group = check.scope.slice('integration:'.length);
    if (!groups.includes(group)) add('PLAN_UNUSED_INTEGRATION_CHECK', `${check.id} references unused integration group ${group}`, 'Checks', check.row, 'Scope');
  }
  const finalChecks = checks.filter((check) => check.scope === 'final');
  if (finalChecks.length !== 1) add('PLAN_FINAL_CHECK', 'exactly one final check is required', 'Checks', finalChecks[0]?.row ?? parsed.Checks.headingRow, 'Scope');

  let graph = null;
  if (!diagnostics.length) {
    graph = computeGraph(tasks);
    if (!graph) add('PLAN_DEPENDENCY_CYCLE', 'task dependencies must form a DAG', 'Tasks', parsed.Tasks.headingRow, 'Deps');
  }
  if (diagnostics.length) return result(2);

  sortedTasks = [...tasks].sort((a, b) => numericIdCompare(a.id, b.id));
  const waves = computeWaves(sortedTasks, graph.depth);
  const taskWave = new Map();
  waves.forEach((wave, index) => wave.taskIds.forEach((id) => taskWave.set(id, index)));
  for (const group of groups) {
    const finalWave = Math.max(...sortedTasks.filter((task) => task.integration === group).map((task) => taskWave.get(task.id)));
    waves[finalWave].integrationGroups.push(group);
  }
  const metrics = computeMetrics(sortedTasks, graph);
  if (metrics.criticalPathRatio > 0.6) add('GATE_CRITICAL_PATH_RATIO', `critical path ratio ${metrics.criticalPathRatio} exceeds 0.6`, 'Tasks', parsed.Tasks.headingRow, 'Estimate min');
  if (metrics.largestCriticalTask.criticalPathShare > 0.2) add('GATE_CRITICAL_TASK_SHARE', `${metrics.largestCriticalTask.id} critical-path share ${metrics.largestCriticalTask.criticalPathShare} exceeds 0.2`, 'Tasks', taskMap.get(metrics.largestCriticalTask.id).row, 'Estimate min');
  for (const wave of waves) {
    for (let leftIndex = 0; leftIndex < wave.taskIds.length; leftIndex += 1) for (let rightIndex = leftIndex + 1; rightIndex < wave.taskIds.length; rightIndex += 1) {
      const left = taskMap.get(wave.taskIds[leftIndex]); const right = taskMap.get(wave.taskIds[rightIndex]);
      for (const leftPath of left.writeSet) for (const rightPath of right.writeSet) if (writeSpecsOverlap(leftPath, rightPath)) add('GATE_WRITE_OVERLAP', `${left.id} and ${right.id} overlap at ${leftPath} and ${rightPath}`, 'Tasks', right.row, 'Write set');
    }
  }
  const publicTasks = sortedTasks.map((task) => publicTask(task, contractMap, decisionMap, checkMap));
  return result(diagnostics.length ? 1 : 0, metrics, waves, publicTasks);

  function result(exitCode, metrics = null, waves = [], tasks = []) {
    diagnostics.sort(diagnosticCompare);
    return { exitCode, output: { schemaVersion: SCHEMA_VERSION, valid: exitCode === 0, diagnostics, metrics, waves, tasks }, internal: exitCode === 2 ? null : { rawTasks: sortedTasks, groups } };
  }
}

function parseTable(lines, heading, end, expectedHeaders, add) {
  let cursor = heading.index + 1;
  while (cursor < end && lines[cursor] === '') cursor += 1;
  const headingRow = heading.row;
  const result = { headingRow, rows: [] };
  if (cursor >= end) { add('PLAN_TABLE_MISSING', `${heading.name} table is required`, heading.name, heading.row, 'table'); return result; }
  const header = splitTableRow(lines[cursor]);
  if (!header || JSON.stringify(header) !== JSON.stringify(expectedHeaders)) add('PLAN_TABLE_HEADER', `${heading.name} header must exactly match the schema`, heading.name, cursor + 1, 'header');
  cursor += 1;
  const separator = splitTableRow(lines[cursor] ?? '');
  if (!separator || separator.length !== expectedHeaders.length || separator.some((cell) => !/^:?-{3,}:?$/.test(cell))) add('PLAN_TABLE_SEPARATOR', `${heading.name} separator is malformed`, heading.name, cursor + 1, 'separator');
  cursor += 1;
  for (; cursor < end; cursor += 1) {
    if (lines[cursor] === '') continue;
    const cells = splitTableRow(lines[cursor]);
    if (!cells || cells.length !== expectedHeaders.length) { add('PLAN_TABLE_ROW', `${heading.name} row must have ${expectedHeaders.length} cells and no embedded pipes`, heading.name, cursor + 1, 'row'); continue; }
    result.rows.push({ row: cursor + 1, values: Object.fromEntries(expectedHeaders.map((headerName, index) => [headerName, cells[index]])) });
  }
  return result;
}
function splitTableRow(line) {
  if (!line.startsWith('|') || !line.endsWith('|') || line.includes('\\|')) return null;
  return line.slice(1, -1).split('|').map((cell) => cell.trim());
}
function parseReferenceRows(table, regex, section, add) {
  return table.rows.map(({ row, values }) => {
    if (!regex.test(values.ID)) add('PLAN_ID', `invalid ${section} ID ${values.ID}`, section, row, 'ID');
    for (const [field, value] of Object.entries(values)) if (!value) add('PLAN_REQUIRED_FIELD', `${field} is required`, section, row, field);
    return { id: values.ID, ...Object.fromEntries(Object.entries(values).filter(([key]) => key !== 'ID').map(([key, value]) => [key.toLowerCase(), value])), row };
  });
}
function parseChecks(table, add) {
  return table.rows.map(({ row, values }) => {
    if (!/^K[1-9][0-9]*$/.test(values.ID)) add('PLAN_ID', `invalid check ID ${values.ID}`, 'Checks', row, 'ID');
    if (!values.Command || !values.Cost) add('PLAN_REQUIRED_FIELD', 'check Command and Cost are required', 'Checks', row, !values.Command ? 'Command' : 'Cost');
    if (!['worker', 'final'].includes(values.Scope) && !/^integration:G[1-9][0-9]*$/.test(values.Scope)) add('PLAN_CHECK_SCOPE', `invalid check scope ${values.Scope}`, 'Checks', row, 'Scope');
    if (!['yes', 'no'].includes(values['Worker-safe'])) add('PLAN_WORKER_SAFE', 'Worker-safe must be yes or no', 'Checks', row, 'Worker-safe');
    return { id: values.ID, scope: values.Scope, command: values.Command, cost: values.Cost, workerSafe: values['Worker-safe'], row };
  });
}
function parseTasks(table, writeRoot, add) {
  return table.rows.map(({ row, values }) => {
    if (!/^T[1-9][0-9]*$/.test(values.ID)) add('PLAN_ID', `invalid task ID ${values.ID}`, 'Tasks', row, 'ID');
    const deps = parseList(values.Deps, /^T[1-9][0-9]*$/, 'Deps', row, add);
    const risks = parseList(values['Risk labels'], null, 'Risk labels', row, add);
    const contracts = parseList(values.Contracts, /^C[1-9][0-9]*$/, 'Contracts', row, add);
    const decisions = parseList(values.Decisions, /^D[1-9][0-9]*$/, 'Decisions', row, add);
    const writeSet = parseList(values['Write set'], null, 'Write set', row, add);
    if (!LANES.has(values.Lane)) add('PLAN_LANE', `invalid lane ${values.Lane}`, 'Tasks', row, 'Lane');
    for (const risk of risks) if (!RISKS.has(risk)) add('PLAN_RISK_LABEL', `invalid risk label ${risk}`, 'Tasks', row, 'Risk labels');
    if (!/^[1-9][0-9]*$/.test(values['Estimate min']) || !Number.isSafeInteger(Number(values['Estimate min']))) add('PLAN_ESTIMATE', 'Estimate min must be a positive safe integer', 'Tasks', row, 'Estimate min');
    if (!/^G[1-9][0-9]*$/.test(values.Integration)) add('PLAN_INTEGRATION_ID', `invalid integration group ${values.Integration}`, 'Tasks', row, 'Integration');
    if (!values.Deliverable) add('PLAN_REQUIRED_FIELD', 'Deliverable is required', 'Tasks', row, 'Deliverable');
    if (!/^K[1-9][0-9]*$/.test(values.Check)) add('PLAN_CHECK_ID', `invalid check ID ${values.Check}`, 'Tasks', row, 'Check');
    if (!writeSet.length) add('PLAN_REQUIRED_FIELD', 'Write set is required', 'Tasks', row, 'Write set');
    for (const writePath of writeSet) validateWritePath(writePath, writeRoot, row, add);
    return { id: values.ID, deps, lane: values.Lane, estimateMin: Number(values['Estimate min']), riskLabels: risks, integration: values.Integration, deliverable: values.Deliverable, writeSet, contracts, decisions, check: values.Check, row };
  });
}
function parseList(value, regex, field, row, add) {
  if (value === '—') return [];
  if (!value) { add('PLAN_REQUIRED_FIELD', `${field} is required (use — for none)`, 'Tasks', row, field); return []; }
  const items = value.split(',').map((item) => item.trim());
  if (items.some((item) => !item)) add('PLAN_LIST', `${field} contains an empty value`, 'Tasks', row, field);
  if (new Set(items).size !== items.length) add('PLAN_LIST', `${field} contains duplicate values`, 'Tasks', row, field);
  if (regex) for (const item of items) if (!regex.test(item)) add('PLAN_REFERENCE_ID', `invalid ${field} reference ${item}`, 'Tasks', row, field);
  return items;
}
function validateWritePath(spec, root, row, add) {
  const raw = spec.endsWith('/') ? spec.slice(0, -1) : spec;
  const invalid = !raw || path.posix.isAbsolute(raw) || raw.includes('\\') || raw.includes('\0') || /[*?\[\]{}]/.test(raw) || raw.split('/').some((part) => !part || part === '.' || part === '..') || path.posix.normalize(raw) !== raw;
  if (invalid) { add('PLAN_WRITE_PATH', `unsafe write-set path ${spec}`, 'Tasks', row, 'Write set'); return; }
  let current = path.resolve(root);
  for (const segment of raw.split('/')) {
    current = path.join(current, segment);
    try { if (fs.lstatSync(current).isSymbolicLink()) { add('PLAN_WRITE_SYMLINK', `write-set path traverses symlink ${spec}`, 'Tasks', row, 'Write set'); return; } }
    catch (error) { if (error.code === 'ENOENT') return; throw error; }
  }
}
function validateUnique(rows, section, add) {
  const seen = new Set();
  for (const entry of rows) { if (seen.has(entry.id)) add('PLAN_DUPLICATE_ID', `duplicate ID ${entry.id}`, section, entry.row, 'ID'); seen.add(entry.id); }
}
function computeGraph(tasks) {
  const byId = new Map(tasks.map((task) => [task.id, task]));
  const state = new Map(); const depth = new Map(); const paths = new Map();
  const visit = (id) => {
    if (state.get(id) === 1) return false;
    if (state.get(id) === 2) return true;
    state.set(id, 1); const task = byId.get(id); let bestDepth = 0; let best = { sum: task.estimateMin, ids: [id] };
    for (const dependency of [...task.deps].sort(numericIdCompare)) {
      if (!visit(dependency)) return false;
      bestDepth = Math.max(bestDepth, depth.get(dependency) + 1);
      const previous = paths.get(dependency); const candidate = { sum: previous.sum + task.estimateMin, ids: [...previous.ids, id] };
      if (candidate.sum > best.sum || (candidate.sum === best.sum && sequenceCompare(candidate.ids, best.ids) < 0)) best = candidate;
    }
    depth.set(id, bestDepth); paths.set(id, best); state.set(id, 2); return true;
  };
  for (const task of [...tasks].sort((a, b) => numericIdCompare(a.id, b.id))) if (!visit(task.id)) return null;
  return { depth, paths };
}
function computeWaves(tasks, depth) {
  const depthGroups = new Map();
  for (const task of tasks) { const level = depth.get(task.id); if (!depthGroups.has(level)) depthGroups.set(level, []); depthGroups.get(level).push(task.id); }
  const waves = [];
  for (const level of [...depthGroups.keys()].sort((a, b) => a - b)) {
    const ids = depthGroups.get(level).sort(numericIdCompare);
    for (let offset = 0; offset < ids.length; offset += 4) waves.push({ index: waves.length + 1, taskIds: ids.slice(offset, offset + 4), integrationGroups: [] });
  }
  return waves;
}
function computeMetrics(tasks, graph) {
  const serialEstimateMin = tasks.reduce((sum, task) => sum + task.estimateMin, 0);
  let critical = null;
  for (const task of tasks) { const candidate = graph.paths.get(task.id); if (!critical || candidate.sum > critical.sum || (candidate.sum === critical.sum && sequenceCompare(candidate.ids, critical.ids) < 0)) critical = candidate; }
  const byId = new Map(tasks.map((task) => [task.id, task]));
  let largest = critical.ids[0];
  for (const id of critical.ids.slice(1)) if (byId.get(id).estimateMin > byId.get(largest).estimateMin || (byId.get(id).estimateMin === byId.get(largest).estimateMin && numericIdCompare(id, largest) < 0)) largest = id;
  return { serialEstimateMin, criticalPathMin: critical.sum, criticalPathRatio: critical.sum / serialEstimateMin, largestCriticalTask: { id: largest, estimateMin: byId.get(largest).estimateMin, criticalPathShare: byId.get(largest).estimateMin / critical.sum } };
}
function publicTask(task, contracts, decisions, checks) {
  const contractRows = task.contracts.map((id) => contracts.get(id)).sort((a, b) => numericIdCompare(a.id, b.id));
  const decisionRows = task.decisions.map((id) => decisions.get(id)).sort((a, b) => numericIdCompare(a.id, b.id));
  const check = checks.get(task.check);
  const contractLines = contractRows.length ? contractRows.map((row) => `- ${row.id}: ${row.behavior} | Evidence: ${row.evidence}`).join('\n') : '- none';
  const decisionLines = decisionRows.length ? decisionRows.map((row) => `- ${row.id}: ${row.decision} | Resolution: ${row.resolution}`).join('\n') : '- none';
  const content = `# Plan task ${task.id}\n\nLane: ${task.lane}\nEstimate min: ${task.estimateMin}\nIntegration: ${task.integration}\n\n## Deliverable\n${task.deliverable}\n\n## Write set\n${task.writeSet.map((item) => `- ${item}`).join('\n')}\n\n## Contracts\n${contractLines}\n\n## Decisions\n${decisionLines}\n\n## Minimal check\n${check.id}: ${check.command}\n\n## Worker rules\n- Modify only the declared write set.\n- Use structured edit/write tools; do not mutate files through bash.\n- Run only the minimal check above.\n- Do not commit or run broad gates.\n- Record concise progress and complete the Crew task with evidence.\n`;
  return { id: task.id, title: `${task.id} — ${[...task.deliverable].slice(0, 80).join('')}`, content, deps: [...task.deps].sort(numericIdCompare), lane: task.lane, estimateMin: task.estimateMin, riskLabels: [...task.riskLabels].sort(lexicalCompare), integration: task.integration, deliverable: task.deliverable, writeSet: [...task.writeSet].sort(lexicalCompare), contracts: [...task.contracts].sort(numericIdCompare), decisions: [...task.decisions].sort(numericIdCompare), check: task.check };
}
function writeSpecsOverlap(left, right) {
  const leftDirectory = left.endsWith('/'); const rightDirectory = right.endsWith('/');
  const leftPath = leftDirectory ? left.slice(0, -1) : left; const rightPath = rightDirectory ? right.slice(0, -1) : right;
  return leftPath === rightPath || (leftDirectory && rightPath.startsWith(`${leftPath}/`)) || (rightDirectory && leftPath.startsWith(`${rightPath}/`));
}
function pathMatchesSpec(changedPath, spec) { const target = spec.endsWith('/') ? spec.slice(0, -1) : spec; return changedPath === target || (spec.endsWith('/') && changedPath.startsWith(`${target}/`)); }

function printCheck(compiled, json) {
  if (json) process.stdout.write(`${JSON.stringify(compiled.output)}\n`);
  else {
    process.stdout.write(compiled.exitCode === 0 ? `Valid plan: ${compiled.output.tasks.length} tasks, ${compiled.output.waves.length} waves\n` : `Invalid plan: ${compiled.output.diagnostics.length} error(s)\n`);
    for (const item of compiled.output.diagnostics) process.stderr.write(`${item.code}: ${item.message} (${item.location.section}:${item.location.row}:${item.location.field})\n`);
  }
}
function parseOptions(values, names) {
  const result = {};
  for (let index = 0; index < values.length; index += 1) {
    const key = values[index];
    if (!names.includes(key) || index + 1 >= values.length || values[index + 1].startsWith('--') || result[key]) throw new Error(`invalid or duplicate option ${key}`);
    result[key] = values[index + 1]; index += 1;
  }
  for (const name of names) if (!result[name]) throw new Error(`missing required option ${name}`);
  return result;
}
function runGit(root, args, allowDifference = false) {
  const result = spawnSync('git', args, { cwd: root, encoding: null, maxBuffer: 100 * 1024 * 1024 });
  if (result.error) throw result.error;
  if (result.status !== 0 && !(allowDifference && result.status === 1)) throw new Error(`git ${args[0]} failed: ${result.stderr.toString('utf8').trim()}`);
  return result.stdout;
}
function parseIdSet(value, label) {
  const ids = value.split(',');
  if (!ids.length || ids.some((id) => !/^T[1-9][0-9]*$/.test(id)) || new Set(ids).size !== ids.length) throw new Error(`${label} must be a unique comma-separated task ID set`);
  return ids.sort(numericIdCompare);
}

async function initBoard(plan, args) {
  let options;
  try { options = parseOptions(args, ['--crew-dir', '--repo-root']); } catch (error) { process.stderr.write(`PLAN_ARGUMENT: ${error.message}\n`); return 2; }
  try {
    const root = fs.realpathSync(options['--repo-root']);
    const planStat = fs.lstatSync(plan); if (planStat.isSymbolicLink() || !planStat.isFile()) throw new Error('PLAN must be a regular non-symlink file');
    const resolvedPlan = fs.realpathSync(plan); if (!inside(root, resolvedPlan)) throw new Error('PLAN must resolve inside ROOT');
    const compiled = compilePlan(resolvedPlan, root);
    if (compiled.exitCode) { printCheck(compiled, false); return compiled.exitCode; }
    const crew = path.resolve(options['--crew-dir']); fs.mkdirSync(crew, { recursive: true });
    for (const entry of RUNTIME_ENTRIES) if (exists(path.join(crew, entry))) { process.stderr.write(`BOARD_RUNTIME_EXISTS: refusing existing runtime entry ${entry}\n`); return 1; }
    const timestamp = new Date().toISOString();
    const record = { prd: path.relative(root, resolvedPlan).split(path.sep).join('/'), created_at: timestamp, updated_at: timestamp, task_count: 0, completed_count: 0 };
    const token = `${process.pid}-${crypto.randomBytes(8).toString('hex')}`; const tempRecord = path.join(crew, `.plan.json.${token}`); const tempPlan = path.join(crew, `.plan.md.${token}`);
    try {
      fs.writeFileSync(tempRecord, `${JSON.stringify(record)}\n`, { flag: 'wx' });
      fs.copyFileSync(resolvedPlan, tempPlan, fs.constants.COPYFILE_EXCL);
      fs.renameSync(tempRecord, path.join(crew, 'plan.json'));
      try { fs.renameSync(tempPlan, path.join(crew, 'plan.md')); } catch (error) { fs.rmSync(path.join(crew, 'plan.json'), { force: true }); throw error; }
    } finally { fs.rmSync(tempRecord, { force: true }); fs.rmSync(tempPlan, { force: true }); }
    return 0;
  } catch (error) { process.stderr.write(`PLAN_IO: ${error.message}\n`); return 2; }
}

function changedPaths(root) {
  const data = runGit(root, ['status', '--porcelain=v1', '-z', '--untracked-files=all']);
  const entries = data.toString('utf8').split('\0'); const paths = []; const untracked = new Set();
  for (let index = 0; index < entries.length; index += 1) {
    const entry = entries[index]; if (!entry) continue;
    const status = entry.slice(0, 2); const pathname = entry.slice(3); paths.push(pathname); if (status === '??') untracked.add(pathname);
    if (status.includes('R') || status.includes('C')) { const source = entries[++index]; if (source) paths.push(source); }
  }
  return { paths: [...new Set(paths)].sort(lexicalCompare), untracked };
}
function taskDiff(root, base, paths, untracked) {
  const chunks = [];
  for (const pathname of paths) {
    if (untracked.has(pathname)) chunks.push(runGit(root, ['diff', '--binary', '--no-index', '--', '/dev/null', pathname], true));
    else chunks.push(runGit(root, ['diff', '--binary', base, '--', pathname]));
  }
  return Buffer.concat(chunks);
}
function scopeIsValid(scope, waves, rawTasks) {
  const scopeSet = new Set(scope); const byGroup = new Map();
  for (const task of rawTasks) { if (!byGroup.has(task.integration)) byGroup.set(task.integration, []); byGroup.get(task.integration).push(task.id); }
  return waves.some((wave) => {
    if (wave.taskIds.some((id) => !scopeSet.has(id))) return false;
    const remainder = scope.filter((id) => !wave.taskIds.includes(id));
    return remainder.every((id) => [...byGroup.values()].some((ids) => ids.includes(id) && ids.every((member) => scopeSet.has(member))));
  });
}
function collectGroupRecords(root, specs) {
  const records = new Map();
  const visit = (relative) => {
    const absolute = path.join(root, relative); let stat;
    try { stat = fs.lstatSync(absolute); } catch (error) { if (error.code === 'ENOENT') { records.set(relative, ['missing', hash(Buffer.alloc(0))]); return; } throw error; }
    if (stat.isSymbolicLink()) throw new Error(`symlink in integration content: ${relative}`);
    if (stat.isDirectory()) {
      records.set(relative, ['directory', hash(Buffer.alloc(0))]);
      for (const name of fs.readdirSync(absolute).sort(lexicalCompare)) visit(`${relative}/${name}`);
    } else if (stat.isFile()) records.set(relative, ['file', hash(fs.readFileSync(absolute))]);
    else throw new Error(`unsupported file type in integration content: ${relative}`);
  };
  for (const spec of [...new Set(specs)].sort(lexicalCompare)) visit(spec.endsWith('/') ? spec.slice(0, -1) : spec);
  const chunks = [];
  for (const [relative, [type, contentHash]] of [...records.entries()].sort((a, b) => lexicalCompare(a[0], b[0]))) chunks.push(Buffer.from(`${relative}\0${type}\0${contentHash}`));
  return hash(Buffer.concat(chunks));
}

async function reviewWave(plan, args) {
  let options;
  try { options = parseOptions(args, ['--scope', '--bundle', '--repo-root', '--base', '--output-dir']); } catch (error) { process.stderr.write(`PLAN_ARGUMENT: ${error.message}\n`); return 2; }
  try {
    const root = fs.realpathSync(options['--repo-root']); const resolvedPlan = fs.realpathSync(plan); if (!inside(root, resolvedPlan)) throw new Error('PLAN must resolve inside ROOT');
    const compiled = compilePlan(resolvedPlan, root); if (compiled.exitCode) { printCheck(compiled, false); return compiled.exitCode; }
    const scope = parseIdSet(options['--scope'], 'scope'); const bundle = parseIdSet(options['--bundle'], 'bundle');
    const rawTasks = compiled.internal.rawTasks; const taskMap = new Map(rawTasks.map((task) => [task.id, task]));
    if (scope.some((id) => !taskMap.has(id)) || bundle.some((id) => !taskMap.has(id))) throw new Error('scope or bundle references an unknown task');
    if (bundle.some((id) => !scope.includes(id))) throw new Error('bundle must be a subset of scope');
    if (!scopeIsValid(scope, compiled.output.waves, rawTasks)) throw new Error('scope must be one computed chunk plus complete integration groups');
    const output = path.resolve(options['--output-dir']); if (exists(output)) { process.stderr.write('REVIEW_OUTPUT_EXISTS: output directory already exists\n'); return 1; }
    const head = runGit(root, ['rev-parse', 'HEAD']).toString('utf8').trim(); const base = runGit(root, ['rev-parse', `${options['--base']}^{commit}`]).toString('utf8').trim();
    if (head !== base) { process.stderr.write('REVIEW_HEAD_MISMATCH: HEAD does not equal BASE\n'); return 1; }
    const changed = changedPaths(root); const allowedSpecs = scope.flatMap((id) => taskMap.get(id).writeSet);
    const outside = changed.paths.filter((pathname) => !allowedSpecs.some((spec) => pathMatchesSpec(pathname, spec)));
    if (outside.length) { process.stderr.write(`REVIEW_OUT_OF_SCOPE: ${outside.join(', ')}\n`); return 1; }
    const records = [];
    for (const id of bundle) {
      const paths = changed.paths.filter((pathname) => taskMap.get(id).writeSet.some((spec) => pathMatchesSpec(pathname, spec))).sort(lexicalCompare);
      if (!paths.length) { process.stderr.write(`REVIEW_NO_CHANGE: ${id} has no changed path\n`); return 1; }
      const bytes = taskDiff(root, base, paths, changed.untracked);
      if (bytes.length > MAX_EVIDENCE_BYTES) { process.stderr.write(`REVIEW_OVERSIZE: ${id} evidence is ${bytes.length} bytes\n`); return 1; }
      records.push({ id, filename: `${id}.diff`, bytes, changedPaths: paths });
    }
    const affectedGroups = [...new Set(rawTasks.filter((task) => task.writeSet.some((spec) => changed.paths.some((pathname) => pathMatchesSpec(pathname, spec)))).map((task) => task.integration))].sort(numericIdCompare).map((id) => {
      const specs = rawTasks.filter((task) => task.integration === id).flatMap((task) => task.writeSet);
      return { id, revision: collectGroupRecords(root, specs) };
    });
    const manifest = { schemaVersion: 1, base, tasks: records.map((record) => ({ id: record.id, bundle: record.filename, bytes: record.bytes.length, sha256: hash(record.bytes), changedPaths: record.changedPaths })), affectedGroups };
    const parent = path.dirname(output); fs.mkdirSync(parent, { recursive: true }); const temp = path.join(parent, `.${path.basename(output)}.${process.pid}-${crypto.randomBytes(8).toString('hex')}`);
    try {
      fs.mkdirSync(temp);
      for (const record of records) fs.writeFileSync(path.join(temp, record.filename), record.bytes, { flag: 'wx' });
      fs.writeFileSync(path.join(temp, 'manifest.json'), `${JSON.stringify(manifest)}\n`, { flag: 'wx' });
      fs.renameSync(temp, output);
    } finally { fs.rmSync(temp, { recursive: true, force: true }); }
    return 0;
  } catch (error) { process.stderr.write(`PLAN_IO: ${error.message}\n`); return 2; }
}

async function main() {
  const [command, plan, ...args] = process.argv.slice(2);
  if (!command || !plan) { process.stderr.write('Usage: pi-team.mjs check PLAN.md [--json] | init-board PLAN.md --crew-dir DIR --repo-root ROOT | review-wave PLAN.md --scope IDS --bundle IDS --repo-root ROOT --base COMMIT --output-dir DIR\n'); return 2; }
  if (command === 'check') {
    if (args.some((argument) => argument !== '--json') || args.filter((argument) => argument === '--json').length > 1) { process.stderr.write('PLAN_ARGUMENT: check accepts only --json\n'); return 2; }
    const compiled = compilePlan(plan); printCheck(compiled, args.includes('--json')); return compiled.exitCode;
  }
  if (command === 'init-board') return initBoard(plan, args);
  if (command === 'review-wave') return reviewWave(plan, args);
  process.stderr.write(`PLAN_ARGUMENT: unknown command ${command}\n`); return 2;
}
process.exitCode = await main();
