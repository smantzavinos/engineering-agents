# Fast verification and parallel children: cutting wall time per epic without losing quality

**Status:** draft, owner rulings of 2026-10-13 applied · **Date:** 2026-10-13 · **Extends:** `plans/2026_10_10_frontier_pipeline/plan.md` §6 (testing and quality gates)

## 1. Why

The frontier pipeline cut a child from about 10 h to about 3.5–6 h. Verification is still the largest addressable cost, and children still run one at a time. The measurements below are from the pilot repo (TypeScript monorepo, Vitest units, Playwright E2E against a local backend):

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
  - A sample audit put about 10–15% of new and existing test lines in low-value patterns. These concentrate in mock-heavy page tests. Backend authorization, visibility and persistence tests were almost all high-value.

**What drives the time:**
- repeated full-suite runs on the critical path;
- a serial E2E suite with a cold boot per invocation;
- more test code than the contracts need;
- strictly sequential children.

Deleting existing tests is a minor lever: the audit shows a modest low-value share, so the gain is signal and maintenance, not minutes.

## 2. Targets

| Measure | Now (children 01–03) | Target |
|---|---|---|
| Child wall time, M / L | 3.4 h / 3.7–5.7 h | ≤ 2 h / ≤ 3 h |
| Full-suite runs on a child's critical path | 2–3 | 0; 1 only for the escalation in §3.1 |
| Test time share of implementer wall time | ~46% | ≤ 20% |
| Epic wall time | sum of children | ≤ 0.7 × sum of children, once parallel lanes run (§8) |
| Regressions found at a checkpoint, epic close or PR that T1 missed | not tracked | tracked; each fixed before the next checkpoint |
| Escaped defects at epic close and PR review | baseline from pilot | no worse |

## 3. Avenue A: tiered verification and checkpoints

### 3.1 Tiers

| Tier | When | What runs | Who |
|---|---|---|---|
| **T0 inner loop** | while building | Tests related to what you just changed (`vitest related <files>`), single E2E specs by name against a warm harness (§4.2), incremental typecheck | implementer |
| **T1 child close** | once, at the end of implementation | Full typecheck and build for the touched packages; lint and format on changed files; unit tests selected against the child's base commit (`--changed <base>`; a change to config, setup or a shared module reruns the whole package); E2E: the specs citing this child's scenarios, the specs the test map (§4.3) links to the touched paths, and the smoke set | implementer, through a helper |
| **T2 checkpoint** | at each checkpoint the epic declares, in the background (§3.3) | Every gate, in full | orchestrator, through a helper, in the checkpoint worktree |
| **T3 epic close** | once | Every gate, in full, on the final tree; then the epic-diff review | orchestrator |

**Escalation.** A child that changes the test harness or test infrastructure runs the full gates at T1, on the critical path, because the selection itself can't be trusted then.

Children that touch the following get a *wider* T1 (the whole affected packages and every mapped spec) and are good places for a checkpoint:
- schema, migrations or seed data;
- authorization or visibility rules;
- the shared layout or navigation shell;
- dependency versions or build config.

**One green pass, not two.** T1 runs once. Fix what fails and rerun only what failed, plus anything related to the fix. There is no extra "final full green pass": checkpoints provide that, off the critical path. Review-fix passes run the T1 subset the fix touches.

**Selection must be honest.**
- `--changed` and `--only-changed` default to *uncommitted* changes, so they select nothing after a commit. Always pass the child's base commit.
- Playwright's `--only-changed` selects only changed spec files, never specs affected by a source change. E2E selection therefore comes from the test map and the scenario citations.
- The implementer lists the selected specs and the reason for each in the ledger, so the reviewer can check the selection, not just the result.

### 3.2 Where it is declared

- **The plan's Gates section** names:
  - the T1 commands, with the selection;
  - the scenario specs;
  - whether escalation or a wider T1 applies, and why.

  The reviewer checks this in plan review, like any other decision.
- **`epic.md` Gates** names:
  - the T2/T3 commands;
  - the smoke set;
  - the measured durations;
  - the **checkpoints** (§3.3).

### 3.3 Checkpoints

A **checkpoint** is a named point in the epic's child order where the full gates run in the background.

**Placement**, decided at scope time and adjustable by the orchestrator with a recorded decision:
- after the foundation children that most later children build on;
- before a fan-out of children that depend on the same base;
- after a child in the wider-T1 classes (§3.1);
- so that no stretch between checkpoints exceeds about a working day of children (roughly 3–4 children);
- epic close (T3) is always the last checkpoint.

**Running a checkpoint:**
1. When the last child before checkpoint C closes and is integrated, the orchestrator points the reusable checkpoint worktree (§8.3) at that commit.
2. A helper runs every gate there.
3. Work continues past C while it runs.

**The bound:** work may not pass checkpoint C+1 until C is green. At most one checkpoint is unverified at any time.

**When a checkpoint fails** (a failure not in the baseline and not a known flake):
1. **Triage, by a helper:**
   - rerun the failing tests alone once;
   - if they still fail, find the culprit with `git bisect run` over the commits since the last green checkpoint, running only the failing tests, which is cheap;
   - digest the failure.
2. **Route it:**
   - **Pause and fix in the culprit child** when the failure sits in code that the running child builds on. Pause the running child, resume the culprit's implementer (its session is kept) to fix on top of the branch tip, run T1 for the fix plus the failing tests, then resume.
   - **Fix forward** otherwise. The failure goes into the running child's ledger as a blocker finding carried over from the culprit. That child cannot close until it is fixed.
3. **Record:** the regression goes in `state.json` (culprit child, test, which tier caught it, what T1 missed), and the test map widens so the same miss can't recur.

### 3.4 Flakes

- A failure that passes alone and lies outside the change is recorded and does not block.
- A flake seen twice becomes a tracker item with an owner, and is quarantined from gating until it is fixed: it moves to a non-gating list in `epic.md`, with an expiry.
- Gates run with retries off. A retry is allowed only in checkpoint triage.

## 4. Avenue B: make each run cheaper (repo-side work)

These are changes to the repo's test setup, not to the pipeline. In the pilot they are built together, in the prep plan (§11), not as separate tracker items.

1. **Parallel E2E.** Give each worker its own backend, data directory and app server, keyed by worker index. The pilot repo already has per-worker ports wired but unused. Serial-only specs (those that reset shared data) either move to per-worker data or keep a named lock. The measured test time is 364 s; with 4 workers that is roughly 100 s plus the fixed cost.
2. **Warm harness for T0/T1.**
   - Keep one backend and one app server running across targeted runs, resetting data between runs instead of rebooting.
   - Rebuild the app only when source changed, or use the dev server for targeted runs.
   - This removes most of the per-invocation overhead (about 38 s each, 29 times in child 01).
   - Never reuse a server across commits without a rebuild check, since stale code passes tests.
3. **Test map.** Keep a checked-in map from source paths to E2E specs (or spec tags), plus a small smoke set of critical flows (about 1 min). T1 selection reads it, and every regression T1 missed adds an entry.
4. **Changed-file lint.** Run lint and format on changed files at T1 and the full lint at checkpoints. The full lint takes 70–90 s of the non-E2E gates.
5. **Failure-only reporters** (Vitest `minimal`, Playwright list with `--quiet`), so digests stay short.
6. **Worktree pool support** (§8.3): the repo's worktree script gains a non-interactive mode, a test-port allocation alongside the dev ports, and a `reuse` path that re-points an existing worktree instead of creating one.

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
- A page or component test is for interaction logic that E2E can't reach cheaply: keyboard handling, validation states, URL state, focus.

**Mocked-data page tests.** The pilot's page tests often look like this:
1. Mock the data hook to return six canned results in the exact order the page calls it.
2. Render the page.
3. Assert that the canned data appears.

This proves little. The mock supplies the behavior being asserted, so the test is nearly tautological. And reordering the page's queries breaks it with no change in behavior, so it is a change detector. Whether the page shows real data from the real queries is a wiring question that E2E answers properly.

**The rule (banned):** new page or component tests whose purpose is "the page renders what the mocked queries return" are not written.
- Code review flags them as *major*.
- Prove the wiring in E2E instead, and keep page tests for interaction logic.
- Existing ones are removed through the audit (§6), not ad hoc inside feature children.

Once parallel E2E lands (§4.1), E2E stops being the expensive layer.

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

## 6. Avenue D: audit the existing suite (separate backlog item, later)

The audit is tracked as its own repo backlog item (pilot repo #133). It is not part of any feature epic.

- **Scope:** run by subsystem, in coherent batches owned by one owner each, never against a deletion count.
- **Start where the audit found the density:**
  - mocked-data page tests (§5);
  - class and style assertions;
  - re-export identity and inventory tests;
  - near-duplicate validator cases.
- **Method for each candidate:**
  - read its history, callers and owners;
  - record the proof that remains, and where;
  - delete it, or consolidate it into a table, or move it to the real boundary;
  - delete any production seam that only the test used;
  - run the owner's and siblings' tests and the changed checks;
  - get a fresh review.
- **Value signal:** run mutation testing (Stryker with the Vitest runner, incremental, scoped to one module) before and after a batch. Tests that kill no mutants are candidates. A batch must not reduce the mutation score.
- **Expected gain:** cleaner signal and less churn when agents refactor, and maybe 5–10% off unit-test time.

## 7. Avenue E: implementer turn efficiency

Model turns are the other half of implementer time.

- **Fewer, larger errands.** Delegation coordination took 28% of model time: 42 calls, with long prompts and follow-up messages. Delegate only errands worth at least about 5 min of the implementer's own time. Batch sweeps per pattern, and keep task prompts short, naming the plan and the example rather than restating them.
- **No bookkeeping turns.** Task-list tools and diagnostic-mark calls cost about 7 min. They are not needed: the ledger is the record.
- **Don't wait idle.** While a helper runs T1, the implementer writes the ledger entry and reviews the helper diffs.

## 8. Avenue F: parallel lanes

This is separate from checkpoints. Checkpoints decide *when to verify everything*. Lanes decide *which children build at the same time*. The two often fall at different points.

### 8.1 Declaring lanes

At scope time, `epic.md` marks **parallel groups**: sets of children that can be built at the same time. A child may join a group only if:
- it doesn't depend on another child in the group;
- each child's **claims** (the directories, routes, tables and shared components it expects to change) don't overlap another's, except for files the epic names as merge-friendly, such as route doc indexes or a changelog;
- none of them is in the escalation class (test infrastructure) or changes the schema in a way a sibling reads.

Plan review checks each child's claims against its siblings'. A plan that needs to break its claims stops for the orchestrator, which either serializes that child or re-scopes it.

### 8.2 Running and merging

1. Each child in a group gets a lane: a worktree from the pool (§8.3), a branch off the same base, and its own plan, implement and review loop.
2. The orchestrator runs the loops concurrently. One writer per worktree, always.
3. Lanes integrate in the epic's child order as they close:
   - The orchestrator merges each lane branch into the epic branch.
   - A clean merge runs T1 for that child on the merged tree. It is short, and it catches semantic conflicts that text merges miss.
   - A conflict, or a red T1 after a merge, goes to an **integrator**: a fresh implementer session given both children's plans and ledgers. It resolves the conflict, runs T1 for both children, and records what it changed. Its diff gets a code review.
4. Checkpoints (§3.3) apply to the integrated epic branch, not to lane branches.

**Width.** `epic.md` sets `maxLanes` (default 4). The lanes actually running are the smallest of:
- `maxLanes`;
- the number of ready children in the current parallel group;
- what the resource gate allows.

The resource gate, checked before each lane starts:
- **Memory:** at least about 6 GB free per new lane.
- **Disk:** headroom above the repo's floor.
- **E2E workers:** a machine-wide budget, default cores ÷ 4, shared across lanes and the checkpoint run. With 4 lanes, each lane's E2E gets about 2 workers, not 4.
- **Rate limits:** after model rate-limit errors (HTTP 429), drop one lane until the next group.

Concurrent E2E in lanes needs per-lane ports (§8.3).

The pilot machine has 32 cores and 62 GB, with about 28 GB typically free, and each worktree takes about 2 GB of disk. So 4 lanes plus the checkpoint worktree fit, with the E2E worker budget as the binding limit.

### 8.3 Reusable worktree pool

Creating a worktree is expensive in the pilot repo: dependency install, build, dev backend and auth setup. So the pool is created once and reused.

- **Setup:** the repo's worktree script creates N lane worktrees plus one checkpoint worktree. Each gets its own dev, test-backend and app ports, recorded in the worktree's env files.
- **Reuse:** to start a new child, the orchestrator switches the lane worktree to a new branch at the child's base and keeps:
  - `node_modules` and build caches;
  - the dev backend;
  - the env files.

  It reinstalls dependencies only if the lockfile changed, and rebuilds only the packages that changed. The checkpoint worktree is re-pointed to the checkpoint commit in the same way.
- **Hygiene:**
  - before reuse, the worktree must be clean, with everything committed;
  - test data directories are reset, not deleted;
  - a lane never kills processes outside its own ports.
- **Disk:** check headroom before starting a lane or a checkpoint run, and stop below the repo's floor.

### 8.4 Expected effect

Per-child time doesn't change. Epic wall time drops by roughly the share of children that can run in pairs, minus the integration cost. For a 12-child epic with 4 pairable pairs, that is about 25–30%.

## 9. Expected effect per child (child 01 profile, 205 min)

| Change | Saving (min) |
|---|---|
| No repeated full runs on the critical path; T1 selection instead (§3.1) | 30–35 |
| Review-fix pass reruns only its T1 subset | 10–15 |
| Warm harness for T0/T1 E2E (§4.2) | 10–15 |
| Parallel E2E (§4.1) | about 5 on the critical path; checkpoint runs drop from about 12 min to about 5 |
| Fewer, better tests written (§5) | 10–15 |
| Turn efficiency (§7) | 10–15 |
| **Total per child** | **≈ 75–100, so 205 → ~110–130 min** |

Together with lanes (§8.4), a 12-child epic of about 50 h would drop to about 20–25 h.

## 10. Changes to make

**Pipeline (this repo):**

| File | Change |
|---|---|
| `skills/test-quality/SKILL.md` (new, ≤ 60 lines) | §5 rules; audit method from §6 |
| `skills/implement/SKILL.md` | Gates: the T0/T1 rules, no final full pass, selection reasons in the ledger, test-to-production line ratio; Offload: the errand threshold and no idle waits |
| `skills/orchestrate/SKILL.md` | Checkpoints with the one-unverified bound; failure triage and routing; lanes, the worktree pool and the integrator; regressions in `state.json`; disk check |
| `skills/plan/SKILL.md` | Gates declare T1 selection and escalation; contracts and their owning layer per scenario; claims for children in a parallel group |
| `skills/review/SKILL.md` | Check the T1 selection and sibling claims; apply `test-quality` to new tests with the severities above |
| `skills/scope/SKILL.md` | `epic.md` Gates names checkpoints, smoke set and test map; parallel groups with claims |
| `agents/` | No new agent; the integrator is an `implementer` session with an integration task |
| `plans/2026_10_10_frontier_pipeline/plan.md` §6 | Replace the gate table with §3; link here |
| `plans/2026_10_10_frontier_pipeline/evaluation.md` | Add the §2 measures, the regression log, lane overlap and integration cost, and cost read from session logs (dedupe the transcript copies) |

The skills budget stays within about 450 lines in total; the new skill is the only addition.

**Pilot repo: the prep plan scope (§11), built now, no tracker items:**
1. Parallel E2E with per-worker backends (§4.1).
2. Warm harness mode (§4.2).
3. Test map and smoke set (§4.3).
4. Changed-file lint script (§4.4).
5. Worktree pool support in the worktree script (§4.6, §8.3).
6. Test-architecture doc and agent rules: tiers, checkpoints, lanes, the authoring gate, layer choice, and the mocked-data page-test ban.

**Pilot repo backlog:** the test audit campaign (§6), created as #133.

## 11. Rollout in the pilot

The current epic continues to child 04's close, then pauses as the owner instructed. After that:

1. **Prep branch.** In the pilot repo, branch off the pilot branch and build the repo-side items 1–6 there as one prep plan.
   - Run it through the pipeline itself as a single plan, so it is dogfooded and reviewed.
   - It can start before child 04 closes, in its own worktree with its own test port, and merge child 04 in when that closes. The prep work touches the test harness and scripts; child 04 touches features.
   - Items 1 (parallel E2E) and 5 (worktree pool) are the largest. If prep runs long, the order is 3, 4, 2, 6, then 5, then 1. Lanes need 5; checkpoints and T1 don't need 1.
2. **Pipeline changes.** Make the §10 skill changes on the pipeline branch, rebuild and verify them with a smoke run.
3. **Demarcation.** Start a new branch for children 05–12 from the prep branch's tip, and update `epic.md`:
   - Gates: tiers and checkpoints;
   - parallel groups with claims;
   - a decision entry recording the switch.
4. **Comparison.** `evaluation.md` reads children 01–04 as "before" and 05+ as "after", on the §2 measures.

## 12. Evidence (summarized)

The external reports are in `research/`. The pilot repo's inventory and audit stay with that repo.

- **Selection:**
  - Vitest `--changed`/`related` follow the import graph. Their blind spots are dynamic imports, file-system fixtures and the uncommitted-only default.
  - Playwright `--only-changed` works at file level only.
  - Meta's predictive selection caught more than 99.9% of faulty changes at about half the cost, but per-test recall is below 100%. So selection belongs on per-change gates, with full runs behind it.
- **Tiering:**
  - Google runs only fast, reliable tests presubmit and the rest post-submit, and accepts rollbacks.
  - Merge queues (GitHub, Uber SubmitQueue) test on top of the queue and drop the culprit rather than halting.
  - Uber's speculative builds aborted 40–65% of runs before tuning, which is why only one checkpoint may be unverified at a time.
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

## 13. Owner rulings and open questions

**Rulings (2026-10-13):**
- Full gates run in the background at epic-declared **checkpoints**, not after every child or a fixed count.
- Checkpoints and parallel groups are separate concepts.
- Parallel children run in **reused** worktrees from a pool built with the repo's worktree script.
- Tiered verification is adopted.
- The test audit is a separate backlog item. It is tracked, but it is not the main lever.
- The pilot adopts this after child 04, on a prep branch first and then a new branch for the rest of the epic.
- The repo-side items are built now, in the prep plan, not tracked as separate backlog items.
- New mocked-data page tests are banned (§5).
- Lane width is configurable: `maxLanes`, default 4, capped by the resource gate (§8.2).
- The test audit backlog item is created (pilot repo #133).
- Prep runs through the pipeline as a single plan, starting now in its own worktree, in parallel with child 04.
