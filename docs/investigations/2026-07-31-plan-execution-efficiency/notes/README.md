# Substrate findings — `pi-messenger` source inspection

Read-only inspection of `pi-messenger` (v0.15.0) source, done in place of the five runtime
spikes originally planned in `implementation-plan.md` Phase 1. Every claim carries a
`file:line` citation against the upstream repo.

Reference material only — per the loading rule in `pi-team-execution.md` §4, none of this is
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
| **SUB-7** | Actions are a **Pi tool**, not a CLI | `pi.registerTool({ name: "pi_messenger" })` (`index.ts:385`); `package.json` `bin` is only `install.mjs` | The board materializer **cannot be a standalone script**. It must run inside a Pi session as `pi_messenger` tool calls — i.e. lead-agent behavior. Only plan parsing, the gates, and telemetry harvesting (plain file reads) can be scripts. |
| **SUB-8** | `plan.json` has five required fields plus optional `prompt` | `createPlan` writes `prd`, optional `prompt`, `created_at`, `updated_at`, `task_count`, `completed_count` (`crew/store.ts:84-98`) | The direct-write coupling in SUB-3 is small and stable, not a broad internal schema. Lowers, but does not remove, the version-pin risk. |
| **SUB-9** | Matching risk labels gate editing tasks | An active profile's `approval.mode: "risk-labels"` and normalized `approval.labels` make `task.create` persist `{ required: true, status: "pending" }`; ready/start paths exclude pending tasks until `task.approve` changes status (`crew/team/store.ts:414-444`, `crew/handlers/task.ts:90-119`, `crew/handlers/task.ts:639-746`). Covered by `team-store.test.ts:152-175`, `team-work.test.ts:120-157`, and `team-task-approval.test.ts`. | Keep the label set exact and the profile active. Risk-labelled editing work cannot start before explicit approval. |

Source files below carry the full derivation for each.

## Verified by upstream's own test suite

`pi-messenger` v0.15.0 ships 408 tests (42 files, vitest). Running them against the pinned
source is stronger evidence than the integration smoke test originally planned — deterministic,
no model spend, ~1.4 s.

**Result (2026-07-31): 408/408 pass, 42 files, 1.35 s** — at tag `v0.15.0`, commit
`2f5e7dc9c77fd7a3fba4728931e8564ce48d9bab`, clean tree. Reproduced twice. This is the
implementation plan's Phase 0 gate, and it has passed; `pi-messenger@0.15.0` is the validated
pin.

These cover the substrate behaviors this design depends on:

| Design claim | Upstream test | What it proves |
|---|---|---|
| Lane roles route models [SUB-2] | `tests/crew/team-work.test.ts:94` | Executes our exact path: `saveProfile` → `setActiveTeam` → `createPlan` → `createTask(role)` → `work` → asserts the role's model lands on the spawned task |
| Model precedence order [SUB-2] | `tests/crew/model-override.test.ts:70` | `task → params → role → config → session → agent`, asserted at each level |
| The model actually reaches the worker | `tests/crew/model-override.test.ts:83` | Resolved override appears as the `--model` flag in real spawn args |
| Packaged-name collision [SUB-2a] | `tests/crew/team-work.test.ts:94` | Mixed-case packaged role resolves to the canonical role's model |
| Strict dependency ordering | `tests/crew/task-actions.test.ts:52,66` | `unmet_dependencies` under `strict`; permitted under `advisory` |
| Board/plan/task creation [SUB-3] | `tests/crew/store.test.ts` (41 tests) | Plan and task records, dependencies, resets |

**What the suite cannot establish** is narrower than it first appears. There is no build step
— `package.json` has no build script, ships `files: ['*.ts', 'crew/**', ...]`, and `npm pack`
emits raw TypeScript — so the published package *is* this source tree, and artifact-vs-source
parity is a non-question. What remains is that real provider/model IDs resolve (a config
concern, not a substrate one, and self-evident on first use) and behavior under true
concurrency (`spawnAgents` is mocked). Neither justifies a dedicated gate; both are exercised
for free while building against the tool and during the first real run.

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
verification where cheap verification suffices. Reading and upstream tests establish the
substrate contract. Repo integration, active-profile behavior, and true concurrency are proved
later by current-checkout deployment verification and the first calibrated run; there is no
separate bespoke smoke-test phase.

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
