---
name: execute-plan
description: Execute an approved plan with the code-mode wave engine. Validates the task graph, freezes contracts, then drives waves of parallel implementers with host-run verification and a checkpoint commit per wave. Use after plan review passes and the human has approved.
compatibility: pi
---

# Execute Plan

Drive an approved plan to a verified, reviewed implementation. **You own the loop.** You
compute readiness, invoke one `workflowScript` per wave, run verification yourself on the
host, and commit a checkpoint. You never delegate verification and never hand the whole plan
to one script.

Read `docs/execution-patterns.md` before starting. It carries the runtime constraints and the
reasons behind each rule; this skill is the procedure.

## Inputs

- A plan directory containing `plan.md` and `tasks.json`.
- The repo's verification commands (`docs/testing-strategy.md`).
- Confirmation that the human approved the plan. If unclear, **stop and ask**.

## Preconditions

Run these before anything else. Do not skip on the assumption they passed earlier.

```bash
PLAN_DIR="plans/<slug>"
git status --porcelain            # must be clean; refuse to start on a dirty tree
node -e '
  const { validateGraph } = await import("./workflows/wave.mjs");
  const tasks = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).tasks;
  const errors = validateGraph(tasks);
  if (errors.length) { console.error(errors.join("\n")); process.exit(1); }
  console.log(`graph ok: ${tasks.length} tasks`);
' "$PLAN_DIR/tasks.json"
```

Then record the **baseline**: run the repo's verification command and note what already fails.
A pre-existing failure that you mistake for your own is the most common way this process
wastes a wave.

```bash
BASE="$(git rev-parse HEAD)"
```

## Phase 1 — Freeze

One strong child returns the interface surface every task will code against: the exact
signatures, file paths, and data shapes that cross task boundaries. It writes no
implementation.

subagent({
  agent: "planner",
  task: "Read PLAN_DIR/plan.md and tasks.json. Produce the interface surface the tasks share: exact function/type signatures, file paths, and data shapes crossing task boundaries. Write it to PLAN_DIR/interfaces.md. Do not implement anything."
})

Review the result yourself. A wrong interface here multiplies across every wave.

## Phase 2 — Contract

For every task of class `contract`, a **different agent than the implementer** authors the
failing test. This is the red half, and it is observed once, here, with evidence.

subagent({
  agent: "planner",
  task: "Author the failing tests for the tasks listed as class \"contract\" in PLAN_DIR/tasks.json, against the interfaces in PLAN_DIR/interfaces.md. Write tests only — no implementation. Each test must be able to fail because of a change in the behaviour it covers, without a manual edit of the test. Run them and report the exact red output.",
  skill: "create-tasks"
})

Confirm red yourself, then commit. This commit is the frozen baseline:

```bash
git add -A && git commit -m "test: freeze contracts for <plan>"
CONTRACT="$(git rev-parse HEAD)"
```

Tasks of class `characterization`, `check`, or `none` skip this phase.

## Phase 3 — Wave loop

Repeat until every task is done or you escalate.

**1. Compute the ready set.**

```bash
node -e '
  const { readySet } = await import("./workflows/wave.mjs");
  const { tasks } = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  const done = new Set(JSON.parse(process.argv[2]));
  console.log(JSON.stringify(readySet(tasks, done, Number(process.argv[3])), null, 2));
' "$PLAN_DIR/tasks.json" '["<done ids>"]' "$MAX_WIDTH"
```

`MAX_WIDTH` is `1` for a pipeline and the plan's declared width for a wave swarm.

**2. Build and run the wave.** Generate the script with `buildWaveScript`, then pass it as
`workflowScript` in a single `subagent` call. Every child carries an explicit `model`.

**3. Verify on the host.** You run this, not a child.

```bash
git diff --exit-code "$CONTRACT" -- <frozen test paths> && <verification command>
```

The `git diff` half is not optional for `contract` tasks: it proves the implementer made the
test pass rather than making the test agree.

**4. Classify any failure** with `classifyFailure` before spending a retry:

| Class | Meaning | Action |
|---|---|---|
| `acceptance` | reporting/paperwork, work may be fine | inspect the diff before retrying |
| `model` | configuration error | fix routing; do not retry |
| `spawn-budget` | fan-out ceiling hit | stop, escalate to the human |
| `failure` | real failure | one strong retry, then escalate |

Retry a genuine failure **once**, with the strong model and the failure output included. A
second failure is an escalation, not a third attempt.

**5. Review, then checkpoint.**

subagent({
  agent: "code-reviewer",
  task: "Review the diff for this wave against PLAN_DIR/plan.md. Report correctness, scope creep, and any test that cannot fail for a reason other than an edit to itself.",
  skill: "review-diff"
})

Apply fixes yourself, then:

```bash
git add -A && git commit -m "feat: <plan> wave <n>"
```

**The checkpoint commit is the resume mechanism.** If a wave crashed, check `git status`
before relaunching: aborted children leave partial edits that can produce a false pass. Reset
to the last checkpoint unless you have a specific reason not to.

## Phase 4 — Final gate

1. Full verification from a clean tree.
2. A **fresh-context strong reviewer** on the whole diff — not one that has watched the waves.

subagent({
  agent: "oracle",
  task: "Review the complete diff BASE..HEAD against PLAN_DIR/plan.md. You have not seen this work before. Report anything unfinished, unsafe, or inconsistent with the plan's intent."
})

3. Report to the human: what shipped, what was skipped, residual risk.

## Rules

- **Never delegate verification.** A child cannot carry it; `gate:` validates evidence before
  it consults the command result.
- **Never let a writer run without an explicit `model`**, and never cap a writer with
  `turnBudget` or a hard `toolBudget`. Bound it with `timeoutMs` and a narrow task.
- **Stop for the human** on: a `spawn-budget` failure, a second failure of the same task, any
  destructive or irreversible operation, or a discovery that contradicts the plan's premise.
- **Do not edit the plan to match the implementation.** If they disagree, that is a finding.
- Non-critical follow-ups go to `docs/backlog.md` with a `TASK-XXXX` ID. Critical discoveries
  are raised immediately, never deferred into the backlog.
