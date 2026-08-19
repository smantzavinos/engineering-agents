# ADR 0005: Parallel execution is a DAG with planned fences

Status: Accepted

Date: 2026-08-19

Requirement refs: FR-008, NFR-003

Supersedes: the wave-engine / `maxWidth` / attended-DAG split in ADR 0004.
ADR 0004 still stands for retiring team mode, machine-readable `tasks.json`,
parent-run host verification, and per-task verification classes.

## Context

ADR 0004 replaced team mode with a ready-set wave engine. A later skill,
`dynamic-execute-dag-plan`, ran the same graph as one promise-chain script and
called the difference "attended vs unattended." That axis was wrong. The DAG
skill existed for maximum overlap. Waves existed to stop the world and verify.
Treating them as two runners made plans talk about waves while executing a DAG,
and blocked dependents behind unrelated slow tasks in the same ready-set.

## Decision

Pi has one execution approach after a reviewed approach: **Parallel**.

1. The scheduler is always a DAG. A task starts when its intra-group
   dependencies finish.
2. A **fence group** is a planned verify+commit cut. The parent generates
   `dataflow.<group>.js` with `buildGroupScript`, launches that file, host-verifies,
   and commits. Default is one implicit group (the whole graph).
3. Planning is ownership plus real edges plus optional fences. It is not a
   sequential checklist run in parallel, and it is not ready-set slicing.
4. Sequential TDD is frozen. Team / Crew is abandoned. OpenCode is not updated
   in this change.
5. `dynamic-execute-dag-plan` is removed. `dynamic-execute-plan` runs fence groups.

## Consequences

- `tasks.json` may include `fenceGroups`. The checker rejects unknown ids,
  omitted tasks, forward deps across groups, and intra-group write collisions.
- Cross-group tasks may share a write path.
- `maxWidth` is ignored.
- Skills keep the historical `dynamic-*` names.
- Process docs point at `docs/approaches/parallel.md` instead of teaching two
  runners at the top level.

## Alternatives considered

- Keep waves and DAG as two lanes with a shared planner — rejected; the
  planner is not shared in spirit, and the runners were one idea with a dial.
- Infer fences from the ready set — rejected; that is the old wave engine.
- Require a human to be watching before dropping fences — rejected; fences
  are about risk, not babysitting.
