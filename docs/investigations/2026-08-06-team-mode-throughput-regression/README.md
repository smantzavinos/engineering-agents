# Team-mode throughput regression — Hermes instance-roots run

Post-mortem of the first non-bootstrap Pi-team production run. The run produced a correct,
gate-verified result and lost the throughput objective. This document records the measured
evidence; the resulting direction is `docs/adr/0004-continuous-crew-execution-and-per-task-review.md`.

**Run:** `dotfiles` repo, branch `hermes_instance_roots`, plan
`nix/plans/2026_08_05_hermes_instance_roots/plan.md`, 2026-08-05 to 2026-08-06.
**Evidence basis:** one production run. Directional findings are strong; numeric thresholds
require calibration before they become gates.

## Outcome summary

| Dimension | Result |
|---|---|
| Correctness | 10/12 tasks complete, 4 gate-verified commits, G1–G4 green |
| Safety | Two critical destructive-migration defects caught before any live host mutation |
| Isolation | 0 write-set violations, 0 worker commits, 0 file conflicts across 37 attempts |
| **Throughput** | **Failed.** ~13h elapsed against a 115-minute critical path |

## 1. Worker execution was not the bottleneck

Measured worker batch durations from Crew task progress timestamps:

| Wave | Tasks | Assigned → all done | Elapsed |
|---|---|---|---|
| 1 | T1, T2 | 00:37:29 → 00:40:45 | 3m16s |
| 2 | T3, T4 | 00:49:44 → 00:52:53 | 3m09s |
| 3 (recovery) | T5, T6 | 01:01:56 → 01:03:53 | 1m57s |

Two parallel workers completed 20-minute-estimated packets in about three minutes. Dispatch,
isolation, and reservation enforcement behaved as designed.

## 2. The plan DAG was serial by construction

`pi-team check` output for the executed plan:

```text
serial=205min  criticalPath=115min  ratio=0.56
wave 1: n=2   wave 2: n=2   wave 3: n=4   wave 4: n=1
wave 5: n=1   wave 6: n=1   wave 7: n=1
```

- Mean wave width 1.71 against a configured pool of 4.
- 4 of 7 waves (57%) have width 1 and admit no parallelism.
- Maximum width 4 occurred once.
- Maximum achievable speedup from perfect scheduling: **1.8×** (205 → 115 minutes).

The compiler reported `criticalPathRatio: 0.56` before execution and the lead proceeded. No
planning gate rejected the shape.

T11 and T12 are operator evidence records that cannot run until a human migrates a host. They
contributed two width-1 waves and two approval stops to a board that could not execute them.

## 3. Rework concentrated where checks were weakest

Attempts are from `tasks/<id>.json`; lobby crashes are counted separately because they consumed
budget without performing work.

| Task | Contracts | Minimal check as authored | Attempts | Lobby crashes | Real attempts |
|---|---|---|---|---|---|
| T1 | 6 | executable fixture suite | 1 | 0 | 1 |
| T2 | 6 | executable eval + greps | 1 | 0 | 1 |
| T3 | 4 | executable eval | 1 | 0 | 1 |
| T4 | 5 | executable eval + sops decrypt | 2 | 0 | 2 |
| T5 | 9 | executable spec suite | 4 | 1 | 3 |
| T6 | 5 | executable spec suite | 5 | 1 | 4 |
| **T7** | 10 | **`bash -n` only** | **8** | 0 | **8** |
| **T8** | 11 | **`bash -n` only** | **9** | 0 | **9** |
| T9 | 14 | `rg` presence assertions | 5 | 3 | 2 |
| T10 | 10 | `bash -n` only | 1 | 0 | 1 |

**T7 and T8 alone consumed 17 of 37 attempts (46%).** Both carry the `destructive` and
`migration` risk labels; both were verified by a syntax check.

Consequences observed directly:

- Workers truthfully reported "K7 passed" while the actual contract suite had 4 failing
  assertions, then 1 failing assertion, on separate attempts. The lead discovered this only by
  running `tests/hermes/specs/g3660-runner-contract.sh` manually.
- Verification burden moved from the worker to the lead, serially, after the fact.

Contract count alone does not explain rework: T10 carries 10 contracts and needed 1 attempt,
while T6 carries 5 and needed 4. The discriminating variables are **risk label plus weak
executable check plus large single-owner diff**, which co-occur only in T7 and T8.

## 4. Review was unbounded

- 14 review bundle directories, ~20 fresh reviewer invocations, 1.6 MB of artifacts.
- T7/T8 required 6 review rounds each.
- Bundle size grew every round (T7: 61 KB → 72 KB → 79 KB). Review cost rose as quality rose.

Three distinct reviewer failure modes were recorded:

| Mode | Instance | Cost |
|---|---|---|
| Out-of-scope demand | Required `ssh -F` in `autocommit-brain.sh`, outside the T8 write set and contrary to the plan's unchanged-boundary contract | Task self-blocked; lead escalation and ruling required |
| Structurally impossible evidence | Demanded staged-file proof and recorded check output that the review bundle format does not carry | 3 `NEEDS_WORK` verdicts containing no code defect |
| Genuine critical defect | Rollback reversing homes while writers could still be active; mixed-host normalization mutating before backup and preflight | Justified the loop |

All reviewers used one model with one prompt shape and no stopping rule, no severity budget, and
no scope contract. Each round produced new high-severity findings on already-reviewed code.

## 5. Configuration forced the most serial mode available

| Setting | Package default | Used in this run | Effect |
|---|---|---|---|
| `work.maxWaves` | 50 | **1** | Disabled autonomous chaining |
| `work.stopOnBlock` | false | **true** | Any block halted the run |
| `work.maxAttemptsPerTask` | 5 | **2** | Auto-blocked on infra crashes |
| `review.enabled` | — | false | Built-in bounded review replaced by an unbounded hand-rolled loop |
| `concurrency.workers` | 2 | 4 | Adequate |

`work` was additionally invoked with `autonomous: false` about 15 times.

Because `maxAttemptsPerTask: 2` collided with 5 lobby-worker crashes, the lead mutated
`config/pi-team/crew-config.json` and re-activated the profile **15 times** during execution
(2→3→2→4→2→5→2→6→7→2→8→2→9→2→5→2). None of that churn produced product value.

## 6. Substrate behaviour (confirmed in source)

`crew/handlers/work.ts` dispatches every ready task and awaits the whole batch:

```ts
const workerResults = await spawnAgents(workerTasks, cwd, {...});
```

There is no slot refill. A worker that finishes early idles until the slowest member of its batch
returns. Autonomous mode then recomputes `getReadyTasks()` and starts the next batch, so the model
is **chained barrier waves**, not a continuous pool. This is consistent with, and extends,
`../2026-07-31-plan-execution-efficiency/notes/crew-execution-model.md` §3.

`crew/lobby.ts` provides persistent warm workers that receive assignments by steer message, and
`work.ts` prefers them before spawning fresh agents. The persistent-agent mechanism therefore
already exists; only the dispatch policy is batch-synchronous.

## 7. Root causes, ranked by measured cost

1. **Serial plan shape.** Mean wave width 1.71; the 0.56 critical-path ratio was reported and
   ignored. Caps any scheduling improvement at 1.8×.
2. **Unbounded review protocol.** 14 rounds, no convergence rule, no scope contract, no reviewer
   diversity.
3. **Check strength decoupled from risk.** `bash -n` on the two destructive tasks moved real
   verification onto the lead and caused ~4 avoidable T7 rounds.
4. **Monolithic high-risk tasks.** T7 (3 files) and T8 (2 files) were unsplittable 60–80 KB
   deliverables re-reviewed in full every round.
5. **Barrier coupling.** Per-wave diff review plus per-wave lead commit requires a frozen HEAD,
   which requires a barrier. The barrier served review and Git, not scheduling.
6. **Attempt budget conflated with infra failures.** 5 lobby crashes auto-blocked 3 tasks.

## 8. Quantified conclusion

Perfect continuous scheduling would have moved this run from 205 to 115 minutes of worker time.
Observed elapsed time was roughly 13 hours. **Scheduling was a minor term; the review and
verification loop dominated.** Continuous execution remains the correct architecture, but it is
not by itself the remedy for what failed here.

## 9. What the run proves works

Retain without change:

- Disjoint write-set ownership and reservation enforcement.
- Lead-owned Git with per-write-set staging.
- Integration gates as the commit precondition.
- Fresh independent review for destructive work — it found the two defects that mattered.
- Human approval gates on `destructive`, `migration`, `auth`, and `api-contract` labels.
