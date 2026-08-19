---
name: dynamic-execute-dag-plan
description: Execute an approved plan's task graph as one attended dataflow run — parallel branches as promise chains in a single workflowScript, no wave barriers. Use when a human is supervising the session, branches have cross-branch file dependencies, and wall-clock speed matters more than per-wave checkpoints. For unattended runs use dynamic-execute-plan instead.
compatibility: pi
---

# Dynamic: Execute DAG Plan (attended dataflow)

Take an approved plan's task graph and run it at full parallelism in one attended
session: parallel branches execute concurrently as promise chains inside a single
`workflowScript`, joining only where tasks actually depend on each other. You own
verification, commits, and failure triage — children only implement and report.

## Role

You are the execution architect. You shape the plan for dataflow execution, freeze
contracts, launch the DAG once, verify everything on the host at the end, and
triage failures with targeted follow-up runs. The human is present throughout —
that presence is what licenses the weaker checkpointing (see rule classes below).

## Relationship to the other dynamic skills

- **Plan authoring is unchanged**: the plan is authored and gated with
  `dynamic-create-plan` (`plan.md` + `tasks.json`, same schema, same gate) — including
  its "Decomposing for parallel execution" guidance, which every plan should follow.
  This skill changes only the execution contract for the graph: a wave engine merely
  tolerates an over-serialized graph, while this one is built to exploit a well-shaped
  one.
- **`dynamic-execute-plan` remains the engine for unattended runs.** Its wave
  barriers (per-wave host verification, checkpoint commits, per-wave review)
  exist to make long unsupervised runs safe. This skill deliberately drops them
  for attended runs and keeps everything that is actually load-bearing.

## Rule classes — know which is which

Before deviating from anything, classify the rule. The wave engine's loop
imposes cadence rules that are **not** correctness rules.

**Load-bearing (never drop):**

| Rule | Why it exists |
| --- | --- |
| Contract-first tests authored by a different agent than the implementer | Oracle independence is what makes "tests pass" mean anything |
| The parent runs the contract freeze commit | The frozen baseline must not be movable by anyone who benefits from moving it |
| Disjoint write-sets per task, verified by the plan gate | Makes concurrent children in one shared tree safe |
| `runs.all` only, never `runs.run`, for fan-out | `runs.run` throws on child failure and aborts in-flight siblings |
| No child performs git operations | Concurrent committers race on `index.lock`; the parent is the sole committer |
| Final host-run verification of the full matrix + frozen-test diffs | Terminal evidence that cannot be faked by a child report |
| One fresh-context review of the whole diff | Catches what per-task tunnel vision misses |

**Cadence rules (droppable when attended):**

| Rule | What it buys | Why it is droppable here |
| --- | --- | --- |
| Per-wave host verification | Catches a bad task before dependents build on it | Blast radius is branch-local (disjoint files); failures surface in the end matrix; only the affected branch re-runs |
| Checkpoint commit per wave | Crash resumability for long unattended runs | Worst case is re-running the graph; the expensive artifact (frozen contracts) survives any crash; the human is watching |
| Per-wave code review | Early scope-creep detection | The final whole-diff review still catches it; cost is rework time, not correctness |
| `maxWidth` wave slicing | Bounds concurrent writers in unattended runs | Write-set disjointness already bounds safety; scheduling freedom adds throughput |

## When to use / when not

**Use when:** a human is supervising the session; the graph has cross-branch file
dependencies (branch B imports what branch A builds); wall-clock time matters.

**Do not use when:** the run is unattended (use `dynamic-execute-plan`); the plan
is a strict pipeline (one branch — dataflow adds nothing); branches are truly
file-independent end-to-end — then prefer N concurrent top-level runs in isolated
worktrees with host-side merging instead of one shared-tree script.

**Topology decision table:**

| Graph shape | Topology |
| --- | --- |
| Branches coupled by file dependencies (most feature plans) | One shared-tree dataflow `workflowScript` (this skill) |
| Strictly sequential tasks | Single-branch pipeline; dataflow adds nothing |
| Genuinely independent branches (no shared files at any join point) | Optional: worktree-isolated branches + concurrent top-level runs; parent merges and commits |

A worktree per *coupled* branch does not work: a branch cannot import files its
siblings have not merged, so branches would have to be staged at dependency
frontiers — recreating the barriers this skill exists to remove.

## Process

### Phase 0 — Validate

1. Plan exists, gate passes (`node tools/check-plan.mjs <plan-dir>` — invoke via
   the resolved real path; see the skill's known-issues), human approved it.
2. Record the baseline: run the final gate matrix once; note pre-existing
   failures so they are never mistaken for regressions.
3. Budget check: spawns are capped per run (~64) and never refunded; at roughly
   four spawns per task (implement + review + retry) one run caps near 16 tasks.
   Larger graphs split into multiple runs at natural branch boundaries.

### Phase 1 — Freeze (identical to `dynamic-execute-plan`)

One strong child returns the interface surface every task codes against (exact
signatures, paths, data shapes) into `<plan-dir>/interfaces.md`. Then a
**different agent than any implementer** authors failing tests for every
`contract` task, runs them, and reports the exact red output. Confirm red
yourself, then **you** commit the freeze. This commit is the immutable oracle.

subagent({
  agent: "planner",
  task: "Read <plan-dir>/plan.md and tasks.json. Produce the interface surface the tasks share: exact function/type signatures, file paths, and data shapes crossing task boundaries. Write it to <plan-dir>/interfaces.md. Do not implement anything."
})

subagent({
  agent: "planner",
  task: "Author the failing tests for the tasks listed as class \"contract\" in <plan-dir>/tasks.json, against the interfaces in <plan-dir>/interfaces.md. Write tests only — no implementation. Each test must be able to fail because of a change in the behaviour it covers, without a manual edit of the test. Run them and report the exact red output.",
  skill: "dynamic-create-plan"
})

### Phase 2 — Persist, then execute

Write the DAG as one `workflowScript` body to **`<plan-dir>/dataflow.js`** before
any launch. The file is the record; the tool argument is a copy of that file.

1. Author the script from [references/dataflow-script.md](references/dataflow-script.md):
   promise chains, no `readySet`, no `maxWidth`, no barrier. Sandbox constraints
   apply (no imports, no nested async function declarations or async arrows —
   use plain helpers and Promise chains; embed task data with exact
   `JSON.stringify`; `runs.all` only). The file is raw JavaScript, no markdown fence.
2. Commit `<plan-dir>/dataflow.js` as an orchestration record, separate from the
   contract freeze.
3. Tell the human the path. **Do not launch until they approve this script.**
   Approving the plan is not approval of the script.
4. Launch by reading `dataflow.js` and passing its contents as `workflowScript`.
   Do not hand-author a second inline copy.
5. Fix or resume rounds write `<plan-dir>/dataflow.retry-N.js` or
   `dataflow.resume.js`. Do not silently overwrite an approved `dataflow.js`.
   Announce the new path and wait unless that file was already approved.

Every child brief carries, verbatim from `tasks.json`:

- the task brief (paths, never file contents),
- its write-set ("you may modify only these paths"),
- a standard footer: run your verify command and the frozen-diff check for your
  test paths, and **paste the raw output in your report**; do not edit frozen
  test files — if a test looks wrong, report the mismatch instead; no git
  commands.

Children paste evidence; the parent does not trust it, it *checks* it in Phase 3.
Routing: `ui: true` tasks go to the ui worker (`ui-worker`);
every child carries an explicit `model` (strong for `contract`-heavy or
architecture-adjacent work, cheap for mechanical work); bound writers with
`timeoutMs` and narrow briefs, never with `turnBudget` or hard `toolBudget`.

### Phase 3 — Host end-verification

When the script returns, you run — on the host, yourself, never a child:

1. **Frozen-oracle check**, per contract task:
   `git diff --exit-code <freeze-commit> -- <test paths>` — a diff means a child
   moved the oracle; treat as a critical finding regardless of green suites.
2. **The full verification matrix** from the plan (format, lint, unit,
   integration/E2E, requirements gates — the plan's commands, not inventions).
3. **Failure triage**: for each failed task or red slice, classify before
   spending a retry — `Acceptance rejected:` is paperwork (inspect the diff
   first), `Unknown subagent model` is routing (fix, never retry), fan-out
   ceiling is a stop-and-escalate, anything else is real (one strong retry,
   then escalate to the human).

Fix rounds are new runs (fresh spawn budget): either apply small fixes yourself
or launch a targeted fix child per failed task, then re-verify only the failed
slices plus anything downstream.

**Resume-from-tree:** a crashed or partially failed run needs no checkpoint
ledger. `tasks.json` is the resume format: each task's write-set names what to
inspect, and its verify command re-derives done-ness from the tree. Relaunch a
new dataflow script over the *remaining* subgraph only. Per-task progress
documents are redundant — do not ask children to keep them.

### Phase 4 — Review and commit

1. One fresh-context strong review of the whole diff — an agent that watched no
   waves:
subagent({
  agent: "oracle",
  task: "Review the complete diff <baseline>..HEAD against <plan-dir>/plan.md. You have not seen this work before. Report anything unfinished, unsafe, or inconsistent with the plan's intent."
})
2. Apply review fixes yourself, re-run affected verification slices.
3. Commit as a logical series (one commit per branch or coherent concern, not
   one blob), then report to the human: what shipped, what was skipped, residual
   risk.

## Failure semantics (what a failed child does and does not kill)

- A failed child does **not** abort siblings or other branches — every launch is
  `runs.all`, which resolves `{ ok: false, error }` per child.
- A failed task short-circuits **only its downstream dependents** (they are
  skipped and reported as blocked-by-failure); independent branches run to
  completion. The script returns a structured per-task report either way.
- API errors, timeouts, and agent crashes all surface as `ok: false` — classify,
  do not assume.
- Second failure of the same task is an escalation to the human, not a third
  attempt. A discovery that contradicts the plan's premise stops the run.

## What this skill gives up, on purpose

Per-wave checkpoints (crash insurance), per-wave verification (early blast-radius
containment), per-wave review (early scope-creep detection). Accepted cost for
an attended run: bounded rework risk in exchange for removing every
slowest-member barrier. If the session turns unattended mid-run — the human
leaves — stop at the current safe point, run the end-verification you have, and
hand back with a status report rather than continuing unattended.
