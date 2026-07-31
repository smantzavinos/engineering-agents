# Substrate findings — `pi-messenger` source inspection

Read-only inspection of `pi-messenger` (v0.15.0) source, done in place of the five runtime
spikes originally planned in `implementation-plan.md` Phase 1. Every claim carries a
`file:line` citation against the upstream repo.

Reference material only — per the loading rule in `pi-team-execution.md` §6, none of this is
injected into task packets.

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
