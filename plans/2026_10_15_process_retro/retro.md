# Process retrospective: legacy process and the frontier pipeline pilot

Status: findings and owner decisions, 2026-10-16. The method is in `plan.md`. The evidence (dataset, per-child and per-era dossiers, compiled tables, the full synthesis and its fresh review) stays in the product repository's plan directory and is not published. Figures here are measured unless marked *estimate*. "CP" is critical path; minutes unless stated.

## 1. What was compared

| Era | Process | Children |
|---|---|---|
| A | Legacy: per-task execution, full gates per task, tiered workers | 4 |
| B | Frontier v1: one implementer per child, fresh reviewers, gates at the end of each child, serial | 4 |
| S | Switch preparation for fast verification | — |
| C | Fast verification (targeted T1, full gates at checkpoints), fast implementer, parallel lanes, plan-ahead, RAM-backed E2E data | 14 |
| D | C plus group integration, contract-level plan review, a 7k size limit, single-pass refresh review, medium implementer thinking | 8 |

Children were re-sized between eras (B's four children became C/D's 22), so per-child figures compare shape, not identical work.

## 2. Where the time went

| Era | Median child elapsed | Median build | Production lines/h | Production+test lines/h | Concurrency |
|---|---|---|---|---|---|
| A | 630 | 571 | 0.26k | 0.78k | — |
| B | 285 | 207 | 0.59k | 1.64k | 1.3 |
| C | 167 | 35 | **1.15k** | **2.44k** | 2.2 |
| D | 340* | 48 | 0.63k | 1.37k | 1.5 |

\* Inflated by children planned ahead that waited by design.

- **A:** build was 90% of child time, and gates and tests were 51–72% of build. One disk-full stall cost 472 min (18.5% of the era) while the orchestrator sat inside a blocking 10-hour call.
- **B:** still serial; build 77% of the implement window, full-gate cycles of about 88 min.
- **C was the most efficient era.** Build fell to a median of 35 min. What remained per child on the CP was overhead the new process added: integration 18.5, code review 15, plan review 11, refresh 7.5 (about 53 against about 30 of build). A model-quota stop took 22% of the era.
- **D fell back to B's throughput.** Fixed overhead grew to about 78 min per child against 48 of build: code review about 41, refresh about 23, integration about 14. Causes: a strict dependency chain (concurrency 1.5), the refresh rule, serial splits, longer fix rounds on larger children. D's own changes showed no measured gain: group integration was never applied as written, no serial slices were merged, and medium thinking was not faster (n=7, confounded).
- **The switch to fast verification** gave ×1.5–2 depending on the metric, partly by writing fewer tests per production line (test:prod 1.76 → 1.12). On production+test lines it did not quite repay its ≈11 h cost within era C.

## 3. Findings

Savings below are per epic of this size, *estimates*, and **not additive**: several draw on the same refresh minutes and per-child overhead, and per-child savings shrink when lanes run in parallel. Combined, with overlaps removed: **about 5–10 h per epic**, against about 34.5 h of C+D elapsed. Confidence low to medium.

1. **Refresh is a fixed cost on every lane start (1.5–2.5 h).** It was on the CP in 18 of 22 children (C 105 min, D 183). Half of D's refresh reviews found a major, but two of those four were defects the refresh edit itself introduced. Plan-author compaction at the end of refresh runs added about 40–45 min on the CP.
2. **Lanes start in child or group order, and plan-ahead runs through one planning worktree (1–2 h).** Children waited for earlier children to integrate, and a single planning slot delayed lane starts (16, 13, 14 min observed). Plans approved 2–10 h ahead of need were refreshed anyway, so a long lead bought nothing.
3. **Serial slices multiply the per-child fixed cost (1–2 h).** Splits driven by a size number added children, each with its own review, refresh and integration. Half of D's estimates overshot actuals by 1.6–2.7×, so the limit fired on wrong numbers. The one real size signal: the largest child (about 7k lines) drew 16 of D's 32 code-review majors.
4. **Integration pays a predictable tax (0.75–1.25 h):** conflicts in the same few shared files, E2E port collisions (ports in the OS ephemeral range), gate reruns on identical trees, stale git index locks.
5. **Code-review pass 1 earns its cost.** In C+D it found 39 majors no later stage would have caught: 17 security or behaviour, 21 missing or non-isolating tests. Fix rounds were long when planned items were not built, guards had no test that fails without them, or real bugs were present (roughly 6 / 6 / 8 of D's 32).
6. **Code-review pass 2 is mostly confirmation.** C: 11 passes, no majors; D: 7 passes, 3 majors (two from one large child's half-done fixes, one regression introduced by a fix).
7. **Plan-review pass 1 is the best-value stage and is already off the CP.** Later passes mostly confirm, but they do catch defects introduced by pass-1 fixes (one security defect created by a fix).
8. **The orchestrator was rarely the bottleneck** (busy 3–14%). Its bookkeeping (ad-hoc state-file edits, a state commit every ~7.5 min) fills context and causes small collisions; measured elapsed impact ≤ 0.5 h.
9. **Parallel lanes earned their cost:** 33–94 min saved per group against 5–51 min of overhead. The overhead is the integration tax above.
10. **Flakes were an environment problem,** solved by moving E2E data to RAM; none after that change.
11. **Breakdowns:** infrastructure (disk, storage stalls) ≈880 min across eras, flakes ≈420, tooling ≈200, one quota stop 238 (part of it a deliberate wait for a fix). Era A's longest stall came from a blocking call, which async workflows have since removed.
12. **Subagents were mostly effective.** "Wasted" labels held up in the spot-check; "redundant/overkill" labels did not (0 of 7), so no saving is claimed from them.
13. **Review findings that a plan section would have prompted** — see §5.

## 4. Owner decisions (2026-10-16)

**Adopt:**

| # | Change | Addresses |
|---|---|---|
| 1 | **Cheap environment fixes:** reserve the E2E port range from the OS ephemeral range (and cap the pool allocator inside it; the harness fails loudly if the base is not reserved); disable optional git locks in agent sessions; make the hot shared files merge-friendly (one row or file per entry); skip gate reruns when the tree is identical to one that passed | F4, F10 |
| 2 | **Refresh only when a dependency changed** something the plan relies on. Otherwise the implementer reads a short scout note on what changed. Any edit to the plan gets one review pass | F1 |
| 3 | **Start a lane as soon as its dependencies are integrated;** integration stays once per group (a group counts as integrated when all its members are); keep plan-ahead lead short; add a second planning worktree | F2 |
| 4 | **Group children by content, not size.** Never split serial or inherently related work. Size is only a prompt to ask whether a child mixes separable concerns, never a split trigger | F3 |
| 5 | **Code-review pass 2 checks only the fixes,** on the same model; rerun only the gates the fixes touch | F6 |
| 6 | **Plan-review pass 2 only when** pass 1 found a design or boundary major, or a fix changed a contract | F7 |
| 7 | **Plan additions** (§5) | F5, F13 |
| 8 | **Implementer handoff lists each plan item and where it is built and tested** (no extra test runs) | F5 |
| 9 | **After any orchestrator restart, reconcile the runs that were in flight** (from the stop record) before launching new work | F11 |

On 8: planned-but-not-built items caused about 5 code-review majors, all missed by a green T1. Most of those children had other majors too, so the checklist usually shortens a fix round rather than removing one; in at least one child (08b) it was the only code major. It is worth it only because it costs minutes and runs nothing.

**Not adopted, with reasons:**

- **Implementer break-it check** (remove a guard, see the test fail). The reviewer already does this in pass 1 and found real gaps that way; in the legacy process the same check at the implementer never caught an issue. The guard question moves to plan time instead (§5).
- **External watchdog and automatic quota retry.** Quota errors need manual action anyway; the legacy era's long stall came from a blocking call that no longer exists; the remaining observed loss is about 30 min. Replaced by decision 9.
- **Orchestrator bookkeeping reduction.** Small measured impact; needs a concrete design before it is worth doing. Deferred.
- **Cutting review or test volume.** Reviews catch missing and non-isolating tests and security gaps that nothing later catches; the waste is late discovery and rework, not volume.
- **One code-review pass only.** Pass 2 caught half-done fixes and a fix regression; it is kept but narrowed (decision 5).
- **Direct mode** (plan and build in one session). Would lose fresh plan-review pass 1, the best-value stage. Not pursued now.

**Paused:** task-graph execution and layer-first decomposition at epic level (foundation pass for the data model and reader/writer contracts, then UI children in parallel). Revisit after the adopted changes are measured; first check how many dependencies in a chain-shaped epic are backend contracts rather than UI.

**Also decided:** implementer thinking back to high (medium showed no speed gain; confounded). Integration stays once per group: per-member integration helps only when a later child depends on part of a group, and no such case cost critical-path time in the pilot.

## 5. What a plan should answer

The `plan` skill already asks for goal, design, changes, test contracts with owning layers, gates, claims, risks and handoff. These gaps account for most review majors in eras C and D. Add them as short "answer if applicable" questions, not a heavy template. Counts are an approximate grouping of the 105 major and blocker findings in C and D.

| Plan question | Failures it targets | ≈ majors | Caught where |
|---|---|---|---|
| **Access and visibility:** who can see and do what, including hidden or redacted items? For each guard, which test fails if the guard is removed? | Hidden items leaking through related reads; guards with no isolating test; actions allowed on released or locked items | ~20 | Code review, otherwise escaped |
| **Deliverables checklist:** the scenarios, specs, UI behaviours and tests the build must contain, so the implementer can tick them off at handoff | Planned E2E not written; spec incomplete; planned behaviour missing from the page | ~5 | Code review only |
| **Test ownership:** one owning test per contract at the lowest layer that can prove it; contracts owned elsewhere are not re-proved | Duplicate and tautological tests | ~12 | Plan or code review, as rework |
| **Failure and concurrency paths:** errors, retry, two users at once, live updates | "Failure shown as empty success"; state lost on retry; remount on resume; stale view for a second user | ~5 | Code review; E2E covered only the success path |
| **Assumptions checked against the code:** what already exists, and which specs and files outside the edit list are affected | Plan relied on a component or seed that did not exist; specs outside the edit list broke | ~6 | Plan review, as extra rounds |
| **Limits and load:** platform limits, fan-out, per-request cost for read-heavy features | Unbudgeted fan-out and CPU; limits not derived from the platform's published ones; duplicate derivations | ~4 | Plan review, sometimes late |
| **Deviations** from the prototype or earlier decisions, recorded with a reason | Silent layout or interaction changes | ~2 | Review |

The first three matter most: they target escaped defects and the longest fix rounds.

## 6. Instrument next time

1. `readyAt` per child and phase in the state file when dependencies integrate.
2. Phase label and child key in every run record at launch, scouts included.
3. Orchestrator turn and tool durations, compaction trigger and token count.
4. A gate-run registry keyed by tree hash and command set.
5. Per finding: fix cost at the fix commit; later cost only when a later stage would have caught it.
6. Estimates and actuals in one unit (non-generated added + deleted lines).
7. A log of every stall alert, restart and in-flight run, with the provider error on any quota stop.
8. Model, thinking level and tokens for every run, so model changes can be compared on matched children.

## 7. Next

Process changes 1–9 and the plan additions go into a separate change plan, deployed the usual way (skill changes, flake bump, restart). Product-repository changes (port reservation, allocator cap, merge-friendly files) are tracked in that repository.
