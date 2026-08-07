# Pi-team execution model: planning through execution

**Status:** plan artifact. T7 folds this into `docs/pi-team-setup.md` §"Execution model" and
`docs/team-mode-execution.md`. Governed by
`docs/adr/0004-continuous-crew-execution-and-per-task-review.md` as amended by ADR 0005.

This document answers three questions end to end: how a plan is authored, how it is executed,
and who performs review.

---

## 1. Review ownership: what we use, and what we deliberately do not

**We do not use Crew's built-in automatic review.** `config/pi-team/crew-config.json` keeps
`review.enabled: false`. This is a forced choice, not a preference:

| Crew native review | Why it cannot serve this design |
|---|---|
| Reviews `git diff ${baseCommit}..HEAD` and `git log ${baseCommit}..HEAD` (`crew/handlers/review.ts`) | It reads **committed** history only. Workers never commit and the lead commits only at integration gates, so at review time `HEAD == BASE` and the reviewer would see `*No changes*` |
| Truncates diffs over 50,000 characters | Below observed bundle sizes (61–79 KB for a single task in the failed run) |
| One fixed `crew-reviewer` prompt, one `models.reviewer` model | No negative scope contract, no in/out-of-scope finding tags, no reviewer rotation — the three failure modes the regression investigation recorded |

**What we use instead:** the repo's own `pi-team review-wave` bundles plus fresh
`pi-team-reviewer` subagents, run by the lead under a bounded two-round protocol.

**What we still use from Crew.** This is not a rejection of Crew — it owns most of the loop:

| Concern | Owner |
|---|---|
| Task board, dependency graph, readiness | **Crew** (`store.getReadyTasks`) |
| Worker dispatch, concurrency, lobby reuse | **Crew** (`work` + `spawnAgents`) |
| Retry lifecycle after a defect | **Crew** (`task.reset`, attempt counting) |
| Risk-label approval gating | **Crew** (`task.approve`) |
| Autonomous wave chaining | **Crew** (`crew_continue` steer) |
| Review evidence, verdicts, scope enforcement | **Us** (`review-wave` + `pi-team-reviewer`) |
| Git, integration gates, commits | **Us** (lead only) |

The board stays the single source of task state. We add review; we do not mirror Crew.

---

## 2. Planning

Authored with `skills/pi-team-plan` into `plans/YYYY_MM_DD_<slug>/plan.md` (schema 1).

1. **Decompose by file ownership, not narrative phase.** Each task is named by the files it
   owns. Write sets must be disjoint within a wave. This is what makes waves wide, and wave
   width is what makes the execution model fast.
2. **Exclude human-gated evidence tasks.** Operator records that need a live migrated host stay
   as plan steps; boarding them adds width-1 waves and approval stops for work Crew cannot run.
3. **Match check strength to risk.** A task labelled `destructive` or `migration` must name an
   executable check that runs real fixtures and reports assertion totals. `bash -n` and
   presence-only `rg` are rejected mechanically by `GATE_RISK_CHECK`.
4. **Validate:** `pi-team check <plan> --json` must exit 0. It hard-gates the critical-path
   ratio and oversized critical tasks, and reports parallelism warnings.
5. **Review the shape.** Read the reported metrics against the worker pool before approving:

   ```
   metrics.meanWaveWidth    → want near pool size (4)
   metrics.maxWaveWidth
   metrics.widthOneShare    → want low; high means a serial plan
   WARN_MEAN_WAVE_WIDTH     → advisory, exit 0
   WARN_WIDTH_ONE_SHARE     → advisory, exit 0
   ```

   A plan that trips both warnings will execute nearly serially no matter how good the
   execution model is. Fix the plan, not the scheduler.
6. **Fresh semantic review**, then human approval where requested. Risk-labelled tasks always
   wait for individual human approval.

---

## 3. Execution

### The loop

```text
        ┌──────────────────────────────────────────┐
        │  work(autonomous: true, concurrency: 4)   │
        └───────────────────┬──────────────────────┘
                            │ wave completes → crew_continue steer
                            ▼
                ┌───────────────────────┐
                │   WAVE BARRIER        │   HEAD == BASE, tree holds
                │  1 review-wave bundle │   exactly the completed wave
                │  2 fresh reviewers    │
                │  3 bounded 2 rounds   │
                │  4 effective verdict  │
                └───────────┬───────────┘
                            ▼
              all reviewed → re-invoke work (next wave)
                            │
                integration group complete
                            ▼
                    gate → lead commit
```

Review happens **at the wave barrier**, before the next wave is dispatched. Overlapping review
with the next wave is Phase B — see §5.

### At each barrier, in order

1. **Bundle** with `pi-team review-wave` — unchanged from today. The tree holds exactly the
   completed wave, which is its existing scope contract.
2. **Launch fresh reviewers** — one `pi-team-reviewer` per changed bundle. Never reuse reviewer
   context; never let a reviewer see a peer's write set.
3. **Apply the finding filter** and record the effective verdict.
4. **Retry or rescue** as needed, then re-invoke `work` for the next wave.

### The finding filter (how negative scope is enforced, not merely stated)

Every reviewer finding must be tagged `IN-SCOPE:<path>` or `OUT-OF-SCOPE:<reason>`. The lead then
computes the **effective verdict**:

- any finding whose path is outside the task's write set is reclassified out-of-scope,
  regardless of how the reviewer tagged it;
- out-of-scope findings go to `docs/backlog.md`, never to a worker retry;
- a `NEEDS_WORK` with zero surviving in-scope findings is **downgraded to `SHIP`** plus backlog
  entries.

The verdict a worker sees is computed, not trusted. This is what stops the failed run's pattern
of three `NEEDS_WORK` verdicts that contained no code defect.

### Rounds

- **Round 1** admits blocking, in-scope, write-set-actionable defects only.
- **Round 2** verifies those fixes and may raise regressions only, using a **different reviewer
  model** than round 1.
- There is no round 3. Anything further becomes a backlog item.
- `MAJOR_RETHINK` or attempt exhaustion routes to the fresh strong rescue pass, unchanged.

Retries go through Crew's own `task.reset`, so the board remains authoritative.

### Barriers and commits

- **Waves are review and commit checkpoints.** Integration gates test merged state.
- **Commits happen only at gates**, staged by explicit write-set paths, always lead-owned.
- **Configuration is never mutated mid-run.** If it is wrong, stop, fix, restart. The failed run
  mutated config 15 times and produced no product value.

## 4. Worked example

A six-task plan, worker pool 4. Write sets are disjoint by construction.

| Task | Owns | Deps | Risk |
|---|---|---|---|
| T1 | `src/schema.ts` | — | — |
| T2 | `src/validate.ts` | — | — |
| T3 | `src/cli.ts` | — | — |
| T4 | `README.md` | — | — |
| T5 | `src/wire.ts` | T2, T3 | — |
| T6 | `tests/integration.test.ts` | T5 | `migration` |

`pi-team check` reports: waves `[T1,T2,T3,T4]`, `[T5]`, `[T6]`; mean width 2.0; max 4;
width-1 share 67%. T6 carries a risk label, so its check must be an executable spec —
`bash -n` would be rejected by `GATE_RISK_CHECK`, and T6 additionally waits for human approval.

### Execution trace

| Step | What happens |
|---|---|
| **Wave 1** | `work(autonomous, 4)` dispatches T1, T2, T3, T4 in parallel. Batch completes in minutes. |
| **Barrier 1** | `review-wave` bundles all four; four fresh reviewers run. T1, T2 → `SHIP`. T3 → `NEEDS_WORK`, one in-scope defect in `src/cli.ts`. T4 → `NEEDS_WORK`, but its only finding demands a change in `src/schema.ts`, outside T4's write set: the filter reclassifies it out-of-scope, files it to backlog, and **downgrades T4 to `SHIP`**. No worker round trip. |
| **Wave 2** | T3 retries alone (`task.reset`). T5 is not ready — Crew agrees, since T3 is back to `todo`. |
| **Barrier 2** | T3 round 2, different reviewer model, verifies the fix → `SHIP`. Two rounds, cap reached; anything further would have gone to backlog. |
| **Wave 3** | T5 dispatched. |
| **Barrier 3** | T5 reviewed → `SHIP`. |
| **Approval** | T6 carries `migration`, so it stays blocked until the human runs `task.approve`. |
| **Wave 4** | T6 dispatched. Its check is a real fixture suite — `GATE_RISK_CHECK` rejected `bash -n` at planning time, so the worker actually verified its own work. |
| **Barrier 4** | T6 reviewed → `SHIP`. |
| **Gate** | Integration group complete → run the group's integration check on merged state → green → lead stages the write-set paths and commits. |
| **Closure** | Final gate on clean `HEAD`, fresh full-diff review, telemetry written. |

### What the trace demonstrates

- **The filter prevented a worker round trip** for T4's out-of-scope finding — and turned a
  `NEEDS_WORK` containing no code defect into a `SHIP` plus a backlog item. Three such verdicts
  occurred in the failed run.
- **Review stayed bounded** — T3 took exactly two rounds with a rotated reviewer, then would
  have gone to backlog rather than a third round. The failed run took six rounds on two tasks.
- **Risk got the strongest treatment** — an executable check enforced at planning time, plus
  human approval. In the failed run these two tasks were checked with `bash -n` and absorbed
  46% of all attempts.
- **Commits happened once**, at the gate, on merged state.

What this trace does *not* show is workers running during review; that is Phase B. Note where
the cost actually falls: with wide waves, one barrier serves four tasks at once. A plan with a
high width-1 share pays a barrier per task instead — which is why the parallelism metrics are
reviewed at planning time. Plan shape, not the scheduler, dominates.

---

## 5. Known limits and Phase B

**Phase A (this model) does not overlap review with execution.** Workers idle during review at
each wave boundary. The measured ceiling for perfect scheduling was 1.8× (205 → 115 minutes)
against an observed ~13h run, so this is the minor term; the dominant costs — plan shape,
unbounded review, and weak checks — are addressed here.

**Phase B** would overlap review with the next wave, holding only where a dependent of a task
under review is immediately ready. Five review passes established that it needs substrate
primitives that do not exist today:

| Missing primitive | Why it is needed |
|---|---|
| Review-state-aware readiness | Crew releases dependents on worker-declared `done`; it cannot wait on an external verdict |
| Full dispatched-cohort barrier | `work` awaits only `spawnAgents`; lobby assignments are fire-and-forget and can still be writing |
| Event-driven completion wake | Lobby `task.done` produces no lead wake; polling the board is prohibited by NFR-003 |
| Authenticated evidence producer | Worker agent names are randomly generated and `task.progress` is unauthenticated |
| Structured per-task check evidence | `TaskEvidence` carries only `commits`/`tests`/`prs` |
| Durable plan-ID ↔ Crew-ID map | Crew task IDs are `task-N` and carry no plan ID |

These are recorded in ADR 0005 as upstream asks beside `TASK-0005` (slot-refill dispatch) and
`TASK-0006` (infra-vs-genuine attempt accounting). Do not reintroduce Phase B mechanics locally
without them.

**Other limits.** Skills are prose: the tooling refuses inadmissible plans and the config is
spec-pinned, but runtime obedience to the review protocol is proven by the run's telemetry, not
by a repo test. Treat the first run under this model as a controlled calibration exercise.
