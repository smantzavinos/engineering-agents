# ADR 0006: Retire parallel execution; sequential-first with opportunistic dispatch

Status: Accepted

Date: 2026-09-23

Requirement refs: FR-001, FR-002, OPR-001

## Context

The repo tried three parallel-execution architectures over its life: role-based
team mode (ADR 0002, revised 0003, replaced by 0004), the code-mode dynamic
workflow with a DAG scheduler, fence groups, and write-sets (ADR 0004, refined
0005), and the team planner/executor skills added for OpenCode. Each increased
planning overhead and coordination complexity. In practice none of them made
execution faster; the human owner's assessment is that they made it slower.
Sequential task-by-task execution with per-task verification was repeatedly the
fastest reliable path.

Separately, valuable ideas were introduced by the parallel experiments that are
independent of parallelism itself: per-task verification classes
(contract/characterization/check/none), baseline gate audits, and the rule that
plans reference the repo's canonical verification commands instead of inventing
new ones.

## Decision

1. The single software development pipeline is sequential:
   brief → research → approach → approach review → plan → plan review →
   worklog → execute → code review → PR review.
2. Opportunistic parallel dispatch is allowed during execution: the orchestrator
   may run obviously-independent tasks (no dependency edge, disjoint files)
   concurrently, with bounds chosen by that orchestrator for its environment.
   Any conflict or failure falls back to sequential. Parallelism is never a
   planning artifact — no DAG, no tasks.json, no fence groups.
3. The parallel machinery is retired and archived (not deleted): dynamic-*
   skills, `tools/check-plan.mjs`, `workflows/wave.mjs`, the tasks.json schema,
   the wave/plan-check specs, and the team-mode planner/executor skills move to
   `docs/investigations/2026-09-23-retired-parallel-execution/`.
4. The surviving ideas are promoted to canonical documentation, applying to
   every plan: verification classes in `docs/testing-strategy.md`, baseline
   gate audits and repo-hook referencing in the plan skills, and per-task
   execution tiers in the plan template.
5. Team-mode artifacts (`team_plan.md`, `team_plan_review.md`,
   `team-worklog.md`) are retired with the machinery; `worklog.md` is the one
   execution ledger.

## Consequences

- One pipeline and one execution ledger; plan templates carry verification
  class + execution tier per task.
- The break-it step is not a default anywhere; it survives only as a
  reviewer-initiated demand on high-risk invariant tests.
- `docs/approaches/parallel.md` and `docs/execution-patterns.md` remain as
  archived history and are no longer routing targets from AGENTS.md.
- The human approval gate between plan review and execution is retained
  unchanged.
- ADRs 0004 and 0005 are superseded by this ADR; ADRs 0002 and 0003 were
  already superseded (by 0004).

## Alternatives considered

- **Keep parallel mode as an opt-in for epic-scale plans.** Rejected: three
  architectures produced the same outcome — coordination cost exceeded speedup —
  and an opt-in path keeps two philosophies alive and drifting.
- **Keep team mode for OpenCode only.** Rejected for the same reason: it is the
  same parallel experiment in a different harness.
- **Delete the machinery outright.** Rejected: the archived implementations are
  the cheapest reference if opportunistic dispatch ever needs a scheduler again.
