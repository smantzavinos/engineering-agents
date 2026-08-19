# Dataflow workflowScript skeleton

One `workflowScript` expressing the task DAG as promise chains. Assumes
`tasks.json` with disjoint write-sets, frozen contract tests, and a
`VERIFY_FOOTER` appended to every brief. Adapt names, models, and routing to
the plan. Read this alongside the parent skill; every constraint here is
mechanical (sandbox-enforced or runtime-verified), not stylistic.

```js
// Models from tasks.json; every child carries an explicit model.
const CHEAP = /* tasks.json models.cheap */;
const STRONG = /* tasks.json models.strong */;

// Standard footer every brief carries. Children paste evidence; never trust it
// unverified — the parent re-checks everything on the host afterward.
const FOOTER = (t) => (t.class === 'contract'
  ? `\n\nWRITE-SET (you may modify only these): ${JSON.stringify(t.writes)}\n` +
    `After implementing, run exactly: ${t.verify}\n` +
    `and: git diff --exit-code <freeze-commit> -- ${t.testPaths.join(' ')}\n` +
    'Paste both raw outputs in your report. Do not edit frozen test files; if a ' +
    'test looks wrong, report the mismatch instead. Never run git commit or any ' +
    'state-changing git command.'
  : `\n\nWRITE-SET (you may modify only these): ${JSON.stringify(t.writes)}` +
    (t.verify ? `\nAfter implementing, run exactly: ${t.verify}\nPaste the raw output in your report.` : '') +
    '\nNever run git commit or any state-changing git command.');

// Launch ONE task. runs.all only — runs.run throws on child failure and aborts
// in-flight siblings. Returns the promise for chaining.
const launch = (t) => runs.all([{
  key: 'impl-' + t.id,
  agent: t.ui ? 'ui-worker' : 'worker',
  model: t.class === 'contract' ? STRONG : CHEAP,
  task: t.brief + FOOTER(t),
  timeoutMs: t.timeoutMs ?? undefined
}]);

// ok() checks a branch result without throwing; done() chains the next task
// only when its predecessor succeeded. Plain functions only — the sandbox
// rejects nested async function declarations and async arrows.
const ok = (r) => Array.isArray(r) && r[0] && r[0].ok === true;
const then = (prev, t) => prev.then((r) => (ok(r) ? launch(t) : r));

// ---- Branches: each is a promise chain; no barriers, no readySet ----
// Readiness is structural: a task launches only inside its predecessor's
// .then(), so it cannot start early, and joins are Promise.all.

const backend = launch(T1).then((r) => (ok(r) ? launch(T2) : r));          // T1 -> T2
const lib      = then(backend /* or its own root */, T5);                  // example shapes —
const picker   = Promise.all([lib, T4done, T2done]).then(() => launch(T6)); // mirror the
const surfaces = Promise.all([lib, filterDone]).then(() =>                 // real deps from
  runs.all([T8, T9, T10, T11].map(launch)));                              // tasks.json

// Joins collect the report; failures propagate as { ok:false } results
// without throwing, so sibling branches complete independently.
const report = await Promise.all([backend, picker, surfaces /* , ... */]);

// Normalize into a structured summary: every task id -> ok/blocked/failed,
// with error text for triage. emit() gives the parent live progress.
const flat = [];
const walk = (r) => (Array.isArray(r) ? r.forEach(walk) : flat.push(r));
walk(report);
emit(flat.map(({ key, ok, error }) => ({ key, ok, error: error ?? null })));
return JSON.stringify(flat.map(({ key, ok, error }) => ({ key, ok, error: error ?? null })), null, 2);
```

## Construction rules

1. **Mirror `deps` exactly.** Chain a task in its last dependency's `.then()`;
   join multiple dependencies with `Promise.all([...])`. No task appears twice.
2. **Never let a rejection escape**: every chain resolves (never throws) —
   `then` returns the failing result instead of launching, and `runs.all`
   resolves rather than rejects per child. A script that throws loses all
   branch reports.
3. **Embed task data with exact `JSON.stringify`** output — briefs contain
   quotes, backticks, backslashes, newlines, `${}`; hand-concatenation breaks.
4. **No `gate:` on children** (acceptance-level evidence validation short-circuits
   before the command result is consulted), no `turnBudget`/hard `toolBudget` on
   writers. Bound with `timeoutMs` and narrow briefs.
5. **Await every launched promise** before returning (`Promise.all` at the end) —
   the runtime rejects scripts with floating promises.
6. **Read-only children may use stronger tooling bounds**; writers never do.

## Persist before launch

Write this body to `<plan-dir>/dataflow.js` (raw JavaScript, no fence). Commit it.
Stop and give the human that path unless they have already approved this file.
Launch by reading the file and passing its contents as `workflowScript`. Do not
keep a second hand-authored inline copy. Later rounds use `dataflow.retry-N.js`
or `dataflow.resume.js`.

## After the script returns

The parent (never a child) then runs, on the host:

```bash
git status --porcelain                          # expect accumulated work, no commits
git diff --exit-code <freeze-commit> -- <all frozen test paths>   # oracle immobility
<full verification matrix from plan.md>         # format, lint, unit, e2e, gates
```

Classify any `{ ok:false }` per the parent skill's triage table, fix with
targeted new runs (fresh spawn budget), and re-verify only the failed slices
plus everything downstream of them.
