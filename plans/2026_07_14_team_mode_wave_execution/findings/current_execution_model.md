# Current sequential execution model

**Created:** 2026-07-14
**Topic:** How the existing execution-orchestrator pipeline works today and which properties a parallel alternative must respect or replace
**Plan:** ../brief.md

## Summary
The current Execution phase is a strictly sequential pipeline driven by one lead that delegates every step to a fresh-context sub-agent via `task()`. It maximizes rigor and reproducibility: one sub-agent per task, a single mutable worklog cursor, strict TDD with a break-it check, and one atomic commit per task on a single branch. Its own skill states that all delegations must be synchronous "because every step depends on the previous step's output" — which is true for the artifact pipeline (plan → review → worklog → final review) but overstated for task execution, where the plan already encodes a dependency graph.

## Findings

### The pipeline is a fixed sequence
From [execution-orchestrator SKILL.md](../../../skills/execution-orchestrator/SKILL.md):
```
create-plan -> review-plan (loop <=5) -> [approval gate] -> commit plan
  -> create-worklog -> commit worklog
  -> execute-task T1 -> [opt per-task review] -> execute-task T2 -> ...   (ONE agent per task)
  -> final review-code (loop <=5, fix between) -> complete
```
- "ALL delegations must be **synchronous**. Wait for each result before proceeding." (skill, Delegation Calling Convention)
- Rationale given: "This process is a strict sequential pipeline … Every step depends on the output of the previous step. There is no independent work to do while a child runs."

### Each step runs in fresh context; the worklog is the durable handoff
- `docs/orchestration.md` (Context Strategy) is explicit: "Each sub-agent starts with **fresh context**… Implementation context from T1 would pollute T2… The worklog is the durable handoff mechanism."
- The [worklog template](../../../skills/create-worklog/references/worklog-template.md) has exactly one `NEXT STEP` section — a single serial cursor pointing at the current task. This is fundamentally incompatible with a parallel execution front.

### Task execution is one-task-per-call with strict TDD
From [execute-task SKILL.md](../../../skills/execute-task/SKILL.md):
- "You execute exactly ONE task… The orchestrator will call another sub-agent for the next task."
- The TDD cycle is Red → Green → **Break-it** → Verify. The break-it check (temporarily break the invariant, confirm the test fails, restore) is mandatory and is separately audited by code review.
- Each task ends with exactly one commit including source + tests + requirement docs (if any) + the matching `worklog.md` update, messaged `task(T<N>): …`.

### The task graph already encodes parallelism that is currently unused
- The [plan template](../../../skills/create-plan/references/plan-template.md) Task Graph has a `Depends on` column (`T1 | — `, `T2 | T1`, …).
- The orchestrator executes tasks in listed order regardless of whether their dependency sets are disjoint. Two tasks that both depend only on T1 still run one after the other.
- The plan template records file impact only at the plan level ("Modules/components likely touched"), not per task — so today there is no per-task file-set signal a scheduler could use to co-run tasks safely.

### Review is sequential and fresh-context by design
From [review-code SKILL.md](../../../skills/review-code/SKILL.md):
- Full mode (first review of whole branch) then delta mode (subsequent passes). Reviews are meant to carry no implementation bias, so they run in fresh context.
- Review already scans for test anti-patterns (tautological assertions, source-reading tests, export-exists-only coverage) and treats **missing break-it evidence in the worklog as a Major finding**. This test-adequacy gate is relevant to the parallel design because it partially substitutes for a dropped break-it step.
- In the OpenCode harness, reasoning-heavy roles (planning, all reviews) are delegated via `task(category="ultrabrain")`, and implementation via `category="deep"` (UI via `visual-engineering`) — see `docs/orchestration.md` harness note. These categories route through `sisyphus-junior`, which is exactly the tier team-mode category members use.

### Commits are process checkpoints on a single branch
`docs/orchestration.md` (Commit Checkpoints) enumerates local commits at each stage: approved plan, initialized worklog, each completed task, per-task review fix, final review fix, completion state. All commits are local; the process never pushes. There is one working tree and one branch.

## Properties a parallel alternative must respect or replace
| Property (today) | Status under a parallel mode |
|------------------|------------------------------|
| Synchronous, one-task-per-call execution | **Replace** — this is the parallelism opportunity (Step 5 only). |
| Single `NEXT STEP` worklog cursor | **Replace** — needs a parallel-aware board (team task list) + a wave-oriented durable log. |
| Fresh context per review | **Relax** — a persistent in-team reviewer gains useful cross-wave context; accept mild bias. |
| Strict TDD incl. break-it | **Relax** — drop break-it by default for speed; backstop with the reviewer's test-adequacy gate. |
| Atomic per-task commit on one branch | **Adapt** — one committer, per-wave commit granularity. |
| Backlog/requirement capture, local-only commits | **Preserve** — unchanged. |
| Plan → review → worklog → final review pipeline | **Preserve** — stays sequential and lead-driven. |

## References
- `skills/execution-orchestrator/SKILL.md` — the sequential pipeline, synchronous-only rule, convergence caps.
- `skills/execute-task/SKILL.md` — one-task-per-call, TDD incl. break-it, atomic commit.
- `skills/create-worklog/references/worklog-template.md` — single `NEXT STEP` cursor.
- `skills/create-plan/references/plan-template.md` — task graph with `Depends on`; plan-level file impact only.
- `skills/review-code/SKILL.md` — review modes, test-adequacy gate, break-it evidence as Major.
- `docs/orchestration.md` — context strategy, commit checkpoints, harness category mapping.
