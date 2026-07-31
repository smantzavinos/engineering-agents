# Substrate findings — `pi-messenger` source inspection

Read-only inspection of `pi-messenger` (v0.15.0) source, done in place of the five runtime
spikes originally planned in `implementation-plan.md` Phase 1. Every claim carries a
`file:line` citation against the upstream repo.

Reference material only — per the loading rule in `pi-team-execution.md` §6, none of this is
injected into task packets.

## Substrate constraints (`SUB-n`) — cite these, don't restate them

**These notes are the single source of truth for how the substrate behaves.** The design doc,
the visual plan, and the implementation plan state only the *consequence* of a constraint and
cite its ID. Mechanism detail and `file:line` citations live here and nowhere else — so when a
`pi-messenger` upgrade changes behavior, this table is the only place that needs editing.

| ID | Constraint | Mechanism | Design consequence |
|---|---|---|---|
| **SUB-1** | Crew executes tasks; `pi-subagents` does not | Workers are `pi --mode json --no-session` children spawned by Crew, which explicitly does not launch `pi-subagents` (`crew/handlers/plan.ts:599`; `crew/spawn.ts`, `crew/handlers/work.ts:172-204`) | No worker session resume, no watchdog coverage over workers, no `status.json` telemetry. `pi-subagents` is lead-side only. |
| **SUB-2** | A lane is a Team role | `task.create` accepts `role`, not `model`/`skills`; a role carries `model`/`thinking`/`skills` (`crew/team/types.ts:13-17`), resolved as `task.model → wave param → roleModel → config.models.worker → session model` (`crew/handlers/work.ts:176-183`) | One `role` string sets model, thinking, and skills. Materialization stays on the public API. |
| **SUB-2a** | Never name a lane with a bare packaged role | Resolution prefers the packaged canonical name when that key also exists (`crew/team/store.ts:391-402`); packaged non-editing roles are barred from editing (`crew/utils/team-roles.ts:25-28`) | Use the `worker-*` prefix. Avoid `worker`, `scout`, `researcher`, `oracle`, `planner`, `reviewer`, `context-builder`, `delegate`. |
| **SUB-2b** | An inactive Team profile degrades silently | Unresolved roles fall through to `config.models.worker` with no error (`crew/handlers/work.ts:176-183`) | The materializer must assert the profile is active before creating any task. |
| **SUB-3** | `plan.json` must be written directly | `store.createPlan()` exists (`crew/store.ts:84-98`) but no public `plan.create` action does; `task.create` fails `no_plan` without a plan record (`crew/handlers/task.ts:90-96`) | The one place we touch Crew internals. Pin the version; re-check this file on upgrade. |
| **SUB-4** | Reservations block structured edits only | Enforced via a `tool_call` hook returning `{ block: true }` (`index.ts:1177-1199`); bash writes (`sed -i`, `>`, `python -c`) bypass entirely; registry has no locking or atomic replace | A backstop, not a control. The plan-time disjoint-write-set gate is the real guarantee. |
| **SUB-5** | No per-task cost is recorded | Crew stores no cost and no persistent tool counts | Cost cannot be an acceptance criterion; the calibration run is not cost-comparable to the baseline. |
| **SUB-6** | Retry is fresh but not cold | Feedback persists to `task.last_review` and is injected into the retry prompt with up to 30 progress lines (`crew/prompt.ts:62-87`, `crew/handlers/review.ts:146-155`) | Retry #1 is a fresh worker carrying findings + progress; it does not re-discover from scratch. |

Source files below carry the full derivation for each.

| File | Answers | Headline |
|---|---|---|
| `board-materialization.md` | S1 | `task.create` takes `title`/`content`/`dependsOn`/`role`/`riskLabels` — but **not** `model` or `skills`. Needs a `plan.json` record, which has no public non-LLM create action. |
| `crew-execution-model.md` | S3 | Crew spawns its own `pi --mode json --no-session` children and **does not use `pi-subagents`**. No worker resume, no watchdog coverage, no `status.json` cost telemetry. |
| `review-loop.md` | S2 | Feedback persists to `task.last_review` and is injected into the retry prompt. Project `crew-reviewer.md` overrides the packaged reviewer. |
| `reservations-and-config.md` | S4 + config | Reservations block structured `edit`/`write` only — **bash writes bypass entirely**, and the registry has no locking. Includes the ready-to-paste config block. |

## Why this replaced the spikes

Four of the five questions were *does the code do X* — answerable by reading, which is
cheaper, faster, and more definitive than an experiment. The fifth (S3, resume vs fresh) was
decided by the source: resume does not exist for Crew workers.

This is the investigation's own finding #3 applied to itself — don't run expensive
verification where cheap verification suffices. What reading genuinely cannot establish is
integration reality, race behavior under true concurrency, and version skew. Those are
covered by the single smoke test that replaced Phase 1.

## What it changed in the design

1. **Lanes became Team roles.** `role` is settable at create time and carries `model`,
   `thinking`, and `skills` — so lane routing stays on the public API instead of requiring
   direct writes to Crew's task store. This removed the worst coupling risk in the plan.
2. **The resume-based context rule was deleted.** Retry #1 is a fresh worker carrying findings
   plus a progress log; escalation leaves Crew for a lead-spawned strong subagent.
3. **Reservations were demoted to a backstop.** The plan-time disjoint-write-set gate is the
   real control.
4. **Cost telemetry was downgraded.** Crew records no per-task cost, so the calibration run
   cannot be compared to the baseline on cost — only wall-clock and task counts.
