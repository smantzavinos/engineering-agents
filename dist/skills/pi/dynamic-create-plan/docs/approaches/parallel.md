# Parallel Approach

How Pi turns an approved `approach.md` into implementation. This is the only execution
approach we are developing.

Pi implements this with `dynamic-create-plan`, `dynamic-review-plan`,
`dynamic-execute-plan`, and `dynamic-review-code`. There is no second executor.

## Idea

A **task graph** is the plan. A **DAG scheduler** runs it. A **fence** is a planned cut
where the parent stops the world, verifies on the host, and commits.

Waves and “attended DAG” were the same idea with the wrong defaults:

- A wave of *only independent* tasks is a fence group that forbids internal edges.
- A single end-to-end DAG is a graph with one implicit fence at the end.
- “Someone is watching” is not a rule. Fences exist so later work does not build on a lie.

## Scheduler

A task starts when its **dependencies in the current fence group** have finished — not when
a batch of unrelated ready tasks finishes.

If T4 depends only on T2, T4 starts when T2 finishes, even if T1 is still running. That is
the whole point. Ready-set waves cannot do this, because T4 is not “ready” until T2 is done,
so T4 is pushed to the next wave and waits for T1 too.

## Fences

A fence is a **planning** decision, not a runtime ready-set.

The plan partitions tasks into ordered **fence groups** (phases). Each group runs as a DAG.
When every task in the group has finished, the parent:

1. runs host verification for that subgraph
2. reviews if the plan asked for it
3. commits a checkpoint
4. starts the next group

Cross-group edges are allowed. A task in group N+1 does not start until group N has passed
its fence, even if its named dependency finished earlier. That wait is the fence.

### Default

If the plan names no groups, there is **one group: the whole graph**. One DAG. One host
verify. One commit. Maximum overlap.

Add groups only where you would be sad to let dependents start on unverified work.

Good fence points:

- after frozen contract tests
- after a shared module other tasks will import
- before a wide fan-out that would be expensive to rewind

Bad fence points:

- after every currently-ready independent task (that is the old wave engine)
- “because a human might look away”
- story order with no verification risk

### Shape in `tasks.json`

```json
{
  "fenceGroups": [
    { "id": "shared", "tasks": ["T1", "T2", "T3", "T4"] },
    { "id": "collect", "tasks": ["T5"] }
  ]
}
```

- Every task id appears in exactly one group.
- Groups run in listed order.
- Edges inside a group are scheduled as a DAG (`buildGroupScript`).
- A missing `fenceGroups` means one group containing every task.
- `check-plan.mjs` enforces membership, forward-deps, and intra-group write collisions.

## Planning

Do not write a sequential checklist and then “run it in parallel.” Plan ownership.

**Tasks**

- One write-set owner per path that may be in flight together.
- Small enough for one child (default 30 minutes).
- Briefs carry paths, not file contents.
- Name the verify command. “Done” is a command.

**Edges**

Keep an edge only if the dependent cannot type, build, or run without that artifact.
Drop story-order edges. If two tasks share a component, extract the component as its own
task and point both consumers at it.

**Fence groups**

Ask: “If this subgraph is wrong, what later work do I refuse to start?” Put that later
work in the next group. Everything that can safely overlap stays in the same group.

**Verification class** (unchanged meaning)

| Class | Use |
|---|---|
| `contract` | new observable behaviour; failing test authored by someone other than the implementer |
| `characterization` | refactor; existing suite must stay green |
| `check` | schema, wiring, generated output |
| `none` | prose with no structural contract |

Contract-first matters more here than in sequential TDD: several implementers will code
against the same shapes at once.

## Execution

Parent owns git, host verification, and dispatch. Children implement and report. Children
never commit.

Per fence group:

1. Persist the exact `workflowScript` body under the plan dir (e.g. `dataflow.shared.js`).
2. Launch that file. Do not keep a second inline copy.
3. Schedule with `runs.all` and promise joins on real edges only.
4. On failure: retry the failed branch, not the whole plan, unless the fence verify fails.
5. After the group succeeds: host verify → commit → next group.

After the last group: final host matrix + one fresh-context review of the whole diff.

## Artifacts

| File | Role |
|---|---|
| `plan.md` | Human narrative, including fence groups until they live in JSON |
| `tasks.json` | Graph: deps, write-sets, verify, class |
| `interfaces.md` | Shared signatures, written before implementers |
| `dataflow.<group>.js` | Exact script for that fence group |
| `code_review.md` | Fence and/or final review |

## Human gates

- Approve the approach (Design).
- Approve the plan, including fence groups.
- Approve each persisted script before it launches, unless that file was already approved.
- Decide retries, re-plan, backlog, or stop when the parent escalates.

Presence is not a substitute for a fence. Absence is not a reason to add one.

## Out of scope

- Sequential worklog / per-task TDD — frozen original, not this approach.
- Team / Crew — abandoned.
- Ready-set `maxWidth` waves — superseded by fence groups that may contain a DAG.
- OpenCode — leave it; do not port this note there yet.
