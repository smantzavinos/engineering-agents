# Fast verification: cutting test time per child without losing quality

**Status:** draft for owner review · **Date:** 2026-10-13 · **Extends:** `plans/2026_10_10_frontier_pipeline/plan.md` §6 (testing and quality gates)

## 1. Why

The frontier pipeline cut a child from about 10 h to about 3.5–6 h. Verification is still the largest addressable cost. The measurements below are from the pilot repo (TypeScript monorepo, Vitest units, Playwright E2E against a local backend):

| Child | Size | Wall time | Note |
|---|---|---|---|
| 01 | M | 3h25m | 3 full gate runs |
| 02 | L | 3h45m | |
| 03 | L | 5h45m | |

Child 01 in detail (205 min):

- **Phases:** plan loop 30 min, implement 126 min, code review 8 min, review fixes 38 min.
- **Implementer (173 min over both rounds):**
  - model turns about 100 min (376 turns, median 10 s);
  - waiting for helper gate runs 27 min;
  - its own E2E runs 18.5 min (29 runs, about 38 s each, mostly fixed boot and build cost);
  - unit runs 5.5 min.
- **Test-related share of the implementer's time: about 46%.**
  - model time spent writing tests and deciding what to run: 28 min;
  - running tests directly: 24 min;
  - waiting for gate runs: 27 min.
- **Coordinating helpers took 28% of the implementer's model time.** That is 42 subagent calls, with long task prompts.
- **Gates:**
  - A full run takes about 11–13 min: E2E 440 s, plus about 210 s for the other nine gates.
  - E2E runs strictly serially (1 worker, one shared backend). About 76 s of each run is fixed overhead (backend boot, schema, seed, app build).
  - The E2E suite grows with every child: 158 → 171 → 180 → 199 tests.
- **Tests written:**
  - Child 01 added about 3,900 test lines for about 1,700 production lines.
  - A sample audit put about 10–15% of new and existing test lines in low-value patterns. These concentrate in mock-heavy page tests (ordered `mockReturnValueOnce` queues, class and computed-style assertions, re-export identity checks). Backend authorization, visibility and persistence tests were almost all high-value.

**What drives the time:** repeated full-suite runs on the critical path, a serial E2E suite with a cold boot per invocation, and more test code than the contracts need. Deleting existing tests is a minor lever: the audit shows a modest low-value share, so the gain is signal and maintenance, not minutes.

Research inputs are summarized in §10; the external reports are in `research/`. The pilot repo's inventory and audit stay with that repo.

## 2. Targets

| Measure | Now (children 01–03) | Target |
|---|---|---|
| Child wall time, M / L | 3.4 h / 3.7–5.7 h | ≤ 2 h / ≤ 3 h |
| Full-suite runs on a child's critical path | 2–3 | 0, or 1 when escalated (§3.2) |
| Test time share of implementer wall time | ~46% | ≤ 20% |
| Test lines per production line, new code | ~2.3 | report only; no quota |
| Regressions found after a child closed (by background, epic-close or PR gates) | not tracked | tracked; ≤ 1 per 3 children, each fixed within the next child |
| Escaped defects at epic close and PR review | baseline from pilot | no worse |

## 3. Avenue A: tiered verification (on the critical path, run only what the change can break)

### 3.1 Tiers

| Tier | When | What runs | Who |
|---|---|---|---|
| **T0 inner loop** | while building | Tests related to what you just changed (`vitest related <files>`), single E2E specs by name against a warm harness (§4), and incremental typecheck | implementer |
| **T1 child close** | once, at the end of implementation | Full typecheck and build for the touched packages; lint and format on changed files; unit tests selected against the child's base commit (`--changed <base>`; a change to config, setup or a shared module reruns the whole package); E2E: the specs citing this child's scenarios, the specs the repo's test map links to the touched paths, and the repo's smoke set | implementer, through a helper |
| **T2 full gates** | on every closed child, in the background (§3.3) | Every gate, in full | orchestrator, through a helper, in a separate worktree |
| **T3 epic close** | once | Every gate, in full, on the final tree; then the epic-diff review | orchestrator |

**Escalation.** T1 becomes a full run on the critical path when the child touches:
- schema, migrations or seed data;
- authorization or visibility rules;
- the test harness or test infrastructure;
- the shared layout or navigation shell;
- dependency versions or build config.

The plan says so in its Gates section. These are the changes a selection is most likely to miss.

**One green pass, not two.** T1 runs once. Fix what fails and rerun only what failed, plus anything related to the fix. There is no extra "final full green pass": T2 provides that, off the critical path. Review-fix passes run the T1 subset the fix touches.

**Selection must be honest.**
- `--changed` and `--only-changed` default to *uncommitted* changes, so they select nothing after a commit. Always pass the child's base commit.
- Playwright's `--only-changed` selects only changed spec files, never specs affected by a source change. E2E selection therefore comes from the repo's test map (§4.3) and the scenario citations.
- The implementer lists the selected specs and the reason for each in the ledger, so the reviewer can check the selection, not just the result.

### 3.2 Where the plan declares it

The plan's **Gates** section names:
- the T1 commands, with the selection;
- the scenario specs;
- whether escalation applies and why.

The reviewer checks this in plan review, like any other decision. `epic.md` **Gates** names the T2 and T3 commands, the smoke set, and the measured durations.

### 3.3 Background full gates with a WIP limit of one

When child N closes, the orchestrator does the following:
1. It creates a detached worktree at N's end commit, with its own E2E port, and starts a helper there running every gate (T2).
2. Meanwhile it plans and builds child N+1 as usual.

The rule that bounds the risk: **child N+2 does not start until T2(N) is green.** At most one closed child is unverified at any time.

When T2(N) reports a failure that is not in the baseline and not a known flake:
1. **Triage, by a helper:**
   - rerun the failing tests alone once;
   - if they still fail, find the culprit (N's diff, or `git bisect run` over N's commits);
   - digest the failure.
2. **Route it:**
   - **Pause and fix in N** when N+1 is still being planned, or when the failure sits in code N+1 builds on. Pause N+1, resume N's implementer (its session is kept) to fix on top of the branch tip, run T1 for the fix plus the failing tests, then resume N+1.
   - **Fix forward in N+1** otherwise. The failure goes into N+1's ledger as a blocker finding carried over from N. N+1 cannot close until it is fixed and T2(N) is green on the fix.
3. **Record:** the regression goes in `state.json` (child, test, which tier caught it, what T1 missed) and widens the test map so the same miss can't recur.

**Alternative, when the machine can't run two stacks:** run T2 after every K children (a *tranche*, K = 3 by default) and at epic close. A failure is bisected across the tranche. This trades a bigger fix radius for no parallel load. The epic's Gates section picks one mode.

**Resource rules for T2:**
- separate worktree, port and data directory;
- a dependency install from the shared store;
- logs go outside git;
- the worktree is removed with `git worktree remove` when it's green;
- disk headroom is checked before each start, and T2 is skipped and the orchestrator stops when headroom is below the repo's floor.

### 3.4 Flakes

- A failure that passes alone and lies outside the change is recorded and does not block.
- A flake seen twice becomes a tracker item with an owner, and is quarantined from gating until it is fixed: it moves to a non-gating list in `epic.md`, with an expiry.
- Gates run with retries off. A retry is allowed only in T2 triage.

## 4. Avenue B: make each run cheaper (repo-side work)

These are changes to the repo's test setup, not to the pipeline. Each is a separate tracker item in that repo, sequenced before the next epic or between children with the owner's consent.

1. **Parallel E2E.** Give each worker its own backend, data directory and app server, keyed by worker index. The pilot repo already has per-worker ports wired but unused. Serial-only specs (those that reset shared data) either move to per-worker data or keep a named lock. The measured test time is 364 s; with 4 workers that is roughly 100 s plus the fixed cost.
2. **Warm harness for T0/T1.**
   - Keep one backend and one app server running across targeted runs, resetting data between runs instead of rebooting.
   - Rebuild the app only when source changed, or use the dev server for targeted runs.
   - This removes most of the per-invocation overhead (about 38 s each, 29 times in child 01).
   - Never reuse a server across commits without a rebuild check, since stale code passes tests.
3. **Test map.** Keep a checked-in map from source paths to E2E specs (or spec tags), plus a small smoke set of critical flows (about 1 min). T1 selection reads it, and every regression T1 missed adds an entry.
4. **Changed-file lint.** Run lint and format on changed files at T1 and the full lint at T2 and T3. The full lint takes 70–90 s of the non-E2E gates.
5. **Agent-friendly reporters.** Use failure-only output (Vitest's `minimal` reporter, the Playwright list reporter with `--quiet`) so digests stay short.

## 5. Avenue C: write fewer, better tests (going forward)

A new short skill, `test-quality`, carries these rules. `plan`, `implement` and `review` refer to it.

**Authoring gate.** Before adding or changing a test, answer:
1. What observable behavior, invariant or independent contract does it protect?
2. What credible regression would make it fail?
3. Why doesn't existing proof catch that? Each contract has one primary owner at the strongest boundary that can see it. A second layer needs a distinct risk, such as transport, lifecycle or rendering. Extend table-driven cases and shared fixtures instead of adding near-copies.
4. Does it need an export, flag, wrapper or injection hook that production doesn't use? Then prove it at the real boundary instead.

**Choosing the layer.**
- Pure logic, invariants, parsers, security normalization and data rules are unit tests.
- Authorization, visibility, persistence and API contracts are backend tests through the real mutation and query path.
- User flows and acceptance scenarios are E2E.
- A page or component test is for interaction logic the E2E can't reach cheaply. Never use one to re-check data wiring through mocked query queues.
- Agents make most of their mistakes at boundaries (schema drift, wiring, orchestration), so put new proof there. Once parallel E2E lands (§4.1), E2E stops being the expensive layer.

**Considered harmful (review findings, not style notes):**
- *Tautological tests:* the expected value comes from the code under test, a mock supplies the behavior being asserted, or the test asserts what it set up itself.
- *Change-detector tests:* assertions on implementation and call shape, ordered mock queues tied to call order, exact class names or computed styles, copied inventories, source greps, re-export identity. A behavior-preserving refactor must not break a test.
- Duplicate contracts at several layers, test-only seams, fixtures that fabricate state the real path never writes, negative controls that don't fail at the intended guard, names that don't match the behavior.

**Retention bar:**
- Keep independent API, protocol, config, migration, storage, security, default-value, generated-output, package, release, architecture and observable-ordering contracts.
- Being slow or static doesn't make a test disposable.
- A baseline failure may be a bug to fix, not a test to delete.

**Regression tests:**
- A regression test must fail before the fix, for the intended reason, and pass after it. Report when that proof is unavailable.
- One test at the owning layer covers a bug. Don't replay it at every layer it crosses.

**Integrity:**
- Never edit an existing assertion or fixture to get green unless the plan changes that contract, and say so in the ledger.
- Never delete a test without naming the behavior it protected and where that proof now lives.

**Why rules and not procedure:** published agent evidence shows that procedural "always do TDD" prompts *raised* regressions (6.1% → 9.9%). Giving the agent a map of which tests cover what cut them to 1.8%. The pipeline already dropped per-task TDD. This avenue adds the map (§4.3) and the value rules.

**Plan and review hooks:**
- The plan names the contracts each scenario needs proven and the owning layer for each, not a test checklist.
- Code review applies the authoring gate to every new or changed test. Severity is *major* for tautological tests, change detectors or a duplicate contract, and *minor* for naming or fixture issues.
- The implementer's ledger reports test lines against production lines, and the tests removed or consolidated.

## 6. Avenue D: audit the existing suite (separate campaign, not in an epic)

- **Scope:** run by subsystem, in coherent batches owned by one owner each, never against a deletion count.
- **Start where the audit found the density:**
  - mock-heavy page and route tests (ordered query-mock queues, class and style assertions);
  - re-export identity and inventory tests;
  - near-duplicate validator cases.
- **Method for each candidate:**
  - read its history, callers and owners;
  - record the proof that remains, and where;
  - delete it, or consolidate it into a table, or move it to the real boundary;
  - delete any production seam that only the test used;
  - run the owner's and siblings' tests and the changed checks;
  - get a fresh review.
- **Report:** causes, contracts retained, proof and cost, production vs test lines removed, follow-ups.
- **Value signal:** run mutation testing (Stryker with the Vitest runner, incremental, scoped to one module) on two or three modules before and after a batch. Tests that kill no mutants are candidates. A batch must not reduce the mutation score.
- **Authority:** each batch is its own tracker item and PR. It is never mixed into feature children.

Expected gain: a cleaner signal, less churn when agents refactor, and maybe 5–10% off unit-test time. It is not the main time lever.

## 7. Avenue E: implementer turn efficiency (not test-related, measured alongside)

Model turns are the other half of implementer time.

- **Fewer, larger errands.** Delegation coordination took 28% of model time: 42 calls, with long prompts and follow-up messages. Delegate only errands worth at least about 5 min of the implementer's own time. Batch sweeps per pattern, and keep task prompts short, naming the plan and the example rather than restating them.
- **No bookkeeping turns.** Task-list tools and diagnostic-mark calls cost about 7 min. They are not needed: the ledger is the record.
- **Don't wait idle.** When a helper runs T1, the implementer writes the ledger entry and reviews the helper diffs meanwhile. It doesn't block on the wait.

## 8. Expected effect (child 01 profile, 205 min)

| Change | Saving (min) |
|---|---|
| No repeated full runs on the critical path; T1 selection instead (§3.1) | 30–35 |
| Review-fix pass reruns only its T1 subset | 10–15 |
| Warm harness for T0/T1 E2E (§4.2) | 10–15 |
| Parallel E2E, when T1 escalates or T2 runs (§4.1) | 5 on the critical path, 5 min per T2 off it |
| Fewer, better tests written (§5) | 10–15 |
| Turn efficiency (§7) | 10–15 |
| **Total** | **≈ 75–100, so 205 → ~110–130 min** |

That is about a 40–50% cut. A further step change needs throughput work rather than per-child work: smaller children, with two implementers building independent children in separate worktrees under the same WIP-limited T2. That is out of scope here and noted as the next lever.

## 9. Changes to make

**Pipeline (this repo):**

| File | Change |
|---|---|
| `skills/test-quality/SKILL.md` (new, ≤ 60 lines) | §5 rules; audit method from §6 |
| `skills/implement/SKILL.md` | Gates: the T0/T1 rules, no final full pass, selection reasons in the ledger, test-to-production line ratio in the ledger; Offload: the errand threshold and no idle waits |
| `skills/orchestrate/SKILL.md` | T2 background runs with a WIP limit of 1, or the tranche mode; failure routing; regressions in `state.json`; disk check |
| `skills/plan/SKILL.md` | Gates section declares T1 selection and escalation; contracts and their owning layer per scenario |
| `skills/review/SKILL.md` | Check the T1 selection; apply `test-quality` to new tests with the severities above |
| `skills/scope/SKILL.md` | `epic.md` Gates names T2 mode, smoke set and test map |
| `plans/2026_10_10_frontier_pipeline/plan.md` §6 | Replace the gate table with §3; link here |
| `plans/2026_10_10_frontier_pipeline/evaluation.md` | Add the §2 measures, the regression log, and cost read from session logs (dedupe the transcript copies) |

The skills budget stays within about 440 lines in total; the new skill is the only addition.

**Pilot repo (tracker items, owner approval first):**
1. Parallel E2E with per-worker backends (§4.1).
2. Warm harness mode (§4.2).
3. Test map and smoke set (§4.3).
4. Changed-file lint script (§4.4).
5. Test-architecture doc: tiers, the authoring gate and layer choice, the slow-suite policy.
6. First audit batch (§6): page and route tests with ordered mock queues.

## 10. Evidence (summarized)

- **Selection:**
  - Vitest `--changed`/`related` follow the import graph. Their blind spots are dynamic imports, file-system fixtures and the uncommitted-only default.
  - Playwright `--only-changed` works at file level only.
  - Meta's predictive selection caught more than 99.9% of faulty changes at about half the cost, but per-test recall is below 100%. So selection belongs on per-change gates, with full runs behind it.
- **Tiering:**
  - Google runs only fast, reliable tests presubmit and the rest post-submit, and accepts rollbacks.
  - Merge queues (GitHub, Uber SubmitQueue) test on top of the queue and drop the culprit rather than halting.
  - Uber's speculative builds aborted 40–65% of runs before tuning, so the WIP limit keeps speculation to one child.
- **Playwright:**
  - workers and `fullyParallel` run tests in parallel; sharding is by file unless `fullyParallel` is set;
  - worker-scoped fixtures are the hook for per-worker services;
  - a worker restarts after any failure;
  - `reuseExistingServer` can serve stale code.
- **Value:**
  - "change-detector tests considered harmful" (Google Testing Blog);
  - test state, not interactions, and test through public APIs (*Software Engineering at Google*, ch. 12).
  - Agents game tests (METR 2025), and weak tests inflate agent pass rates (SWE-bench audits).
  - A dependency map of tests cut agent regressions; TDD procedure prompts raised them (TDAD, arXiv 2603.17973).
  - Mutation testing is the most objective per-test value signal.
- **Pilot inventory:**
  - about 2,100 web unit tests, 866 backend, 416 CLI and 158–199 E2E;
  - E2E is serial, by design in v1;
  - the slowest E2E files are access-management and list or detail flows;
  - the slowest unit files are browser-backed component tests.

## 11. Owner decisions needed

1. **T2 mode:** background with a WIP limit of 1 (recommended), or a tranche of K = 3.
2. **Escalation list (§3.1):** accept as written, or add to it.
3. **Repo-side items 1–4:** approve creating the tracker items, and say whether to land any before the pilot's child 05. Child 04 pauses for confirmation anyway.
4. **New page tests that re-check data wiring through mocked query queues:** stop writing them (recommended), or only discourage them.
5. **Audit campaign (§6):** start after the pilot epic, or run the first batch in parallel in another worktree.
6. **Adopting this in the running pilot:** apply it from child 05. The orchestrator would then update `epic.md` Gates and record a decision.
