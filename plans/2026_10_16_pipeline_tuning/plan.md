# Pipeline tuning from the process retrospective

**Status:** draft for owner review · **Date:** 2026-10-16 · **Evidence:** `plans/2026_10_15_process_retro/retro.md` (findings F1–F13, owner decisions of 2026-10-16) · **Changes:** `skills/scope`, `orchestrate` (+ `references/lanes.md`), `plan`, `implement`, `review`, `assess-repo`

## 1. Why

The fast-verification era was the most efficient: build fell to a median of 35 min per child. What remained on the critical path was overhead the process itself added (integration, refresh, review loops), about 53 min per child; in the next era it grew to about 78 min against 48 of build. The retrospective's adopted changes remove that overhead without weakening the reviews that caught real defects.

**Target:** per-child fixed overhead on the critical path of a serial chain back to about 40–50 min (from ~78), with no loss of code-review pass 1 or plan-review pass 1. Estimated saving 5–10 h per epic of the pilot's size (retro §3, not additive).

## 2. Changes

Each change names the retro finding it answers. Skill text stays concise; detail goes to `references/` where needed.

### C1. Refresh only when a dependency changed something the plan relies on (F1)

- **`orchestrate` → Close step 6, planned-ahead branch:** replace "resume its plan-author to refresh" with:
  1. A `helper` compares the integrated range (the plan's approval commit to the merge) with the plan's Context, Changes, Tests and Claims, and writes a short note: what changed that the plan names or relies on, or "nothing relevant". It writes the note to the child's ledger under `## refresh scout`.
  2. **Nothing relevant:** no refresh, no review. The implementer gets the note.
  3. **Something relevant:** resume the plan-author to refresh, with the note. Any edit to the plan gets one fresh review pass (unchanged rule). A second refresh pass only if claims or scenarios changed.
- **`plan` → Refresh:** start from the scout note; reply without `self_compact` (refresh runs are short, and end-of-run compaction cost ~40–45 min on the critical path across the pilot).
- **`review` → Plan refresh:** unchanged, but note that refresh edits are where two of four refresh majors came from: review the edit, not only the fit.

### C2. Start lanes when dependencies are met (F2)

- **`orchestrate` → Per child / Plan ahead, and `references/lanes.md` → Starting lanes:** a child starts when every child it depends on (per `epic.md`) is integrated and a pool worktree is free, regardless of child number or group order. Group membership only says which children may run at once (claims don't overlap).
- **Integration stays once per group** (§16 of the fast-verification plan; owner decision D1). For the ready-set rule, a group's members count as integrated when the group is. In the pilot an approved member waited 102 min for its sibling, but the next child depended on both, so it cost nothing on the critical path; the earlier integration queues came from integrating each child in child order, which §16 already replaced.
- **Planning worktrees:** two, not one; each plans the next ready child. Plan-ahead lead stays short: start a child's plan when its last dependency starts implementing (plans approved 2–10 h early were refreshed anyway).
- **`state.json`:** record `readyAt` per child (when its last dependency integrated) and lane start, so ready-to-start waits are measured directly.
- **`epic.md`:** each child's dependencies are the real dependency record. The scope review checks that they are declared (one undeclared dependency in the pilot changed the plan of record).

### C3. Group children by content, not size (F3)

- **`scope` → epic.md Children and Size limit; `Do`:** children are cohesive vertical slices: a piece of behaviour with its data, logic, UI and tests that ends in a testable scenario. Never split serial or inherently related work to meet a number. The ≈7k changed-line figure stays only as a **review-load signal**: a child above it is checked for separable concerns; it is split only if the concerns are separable *and* the pieces can run in parallel lanes. Remove "split below it only for parallel lanes" and "serial children that together fit the limit are one child" as size rules; keep "consecutive serial children with related content may merge".
- **`plan` → Sizing:** estimate first; over the signal, report whether the child mixes separable concerns and propose a parallel split only if it does. Drop the size-driven merge-the-next-child rule; propose a merge only when the next child's content belongs to this one.
- **`orchestrate` → Sizing and scope:** same rule for executing splits and merges. Budget per child is set from its own estimate plus the fixed cost, not from the limit.
- **`review` (epic and plan modes):** check cohesion and dependencies, not "within the limit and split below it only for lanes".
- **Estimates:** calibrated from the first children's actuals on the implementer model in use (half of the pilot's last estimates overshot by 1.6–2.7×).

### C4. Code-review pass 2 checks only the fixes (F6)

- **`orchestrate` → Per child step 2:** a pass after pass 1 gets the fix range (the commit pass 1 reviewed, to the implementer's fix commit) and the ledger.
- **`review` → Earlier passes:** for code mode after pass 1, review only the fix range and verify each open finding there; same model. New findings only if a fix caused them or they are blockers. Don't reread the unchanged diff.
- **`implement` → Review findings:** unchanged ("rerun only the gates the fix affects"); the ledger names which gates were rerun and why.

### C5. Plan-review pass 2 only when needed (F7)

- **`orchestrate` → Per child step 1:** after pass 1, if every open major is about tests, T1 or wording (not design, boundaries, claims, scope or size), the plan-author fixes them and the plan is approved without another pass; the code reviewer sees the fixes in the plan. Another pass runs when pass 1 had a design or boundary major, or the plan-author reports that a fix changed a contract (an interface, data shape, access rule or scenario).
- **`plan` → Revising:** reply states whether any fix changed a contract. (In the pilot, one later-pass security defect was introduced by a pass-1 fix.)

### C6. Questions every plan answers where they apply (F5, F13)

- **`plan` → plan.md:** add a short list, answered inside the existing sections (Design, Tests, Risks), each in a line or "n/a":
  1. **Access and visibility:** who can see and do what, including hidden or locked items; for each guard, the test that fails if the guard is removed.
  2. **Deliverables:** the scenarios, specs, UI behaviours and tests the build must contain (the implementer's handoff checklist, C7).
  3. **Test ownership:** each contract has one owning test at the lowest layer that proves it; contracts owned elsewhere are not re-proved. (Already in Tests; restate it as a question.)
  4. **Failure and concurrency:** errors, retry, two users at once, live updates.
  5. **Assumptions checked against the code:** components, seeds and helpers the plan relies on exist; specs and files outside the edit list that the change will affect.
  6. **Limits and load:** for read-heavy features, platform limits and fan-out.
  7. **Deviations** from the prototype or earlier decisions, with a reason.

  Keep "Aim for under 150 lines". Detail and examples go to `skills/plan/references/plan-questions.md`.
- **`review` → plan mode:** a missing answer to 1, 2 or 4 where it applies is a major (these were the escaped-defect classes); to 5–7 a minor.

### C7. Implementer handoff maps deliverables to evidence (F5)

- **`implement` → Handoff, ledger entry:** add "the plan's deliverables, each with the file or test that delivers it, or *not done* with the reason". No extra test runs.
- **`review` → code mode:** check the map against the diff; an item marked done that isn't is a major.
- **Not added:** an implementer break-it check (removing guards to see tests fail). The reviewer already does this in pass 1, and in the legacy process the implementer-side check never caught an issue.

### C8. Reconcile in-flight runs after a restart (F11)

- **`orchestrate` → Recovery:** after a restart or crash, before launching anything, check the status of every run recorded as in flight in `state.json` and the stop record. Consume results of runs that finished while their completion notice was lost; resume or replace the others.

### C9. Environment checks (F4, F10)

- **`assess-repo`:** check that
  - test-service port ranges are outside the OS ephemeral port range or reserved from it, and that the harness refuses a base that isn't;
  - agent sessions set `GIT_OPTIONAL_LOCKS=0` (background status calls left stale index locks);
  - files that every child edits (requirement tables, test maps, indexes) are merge-friendly: one row or file per entry, or generated.
- **`references/lanes.md` → The pool:** same three points as preconditions for lanes.
- **`implement` → Gates and `orchestrate` → Don't:** don't rerun a gate on a tree identical to one where it passed (compare tree hashes in the ledger).

## 3. Pilot-repo work (tracked in that repository, not here)

- Reserve the E2E port range at the OS level (host configuration; the owner applies it) and cap the pool allocator inside the reserved range; the harness fails loudly if its base isn't reserved.
- `GIT_OPTIONAL_LOCKS=0` in the repo's environment file.
- Make the hot shared files merge-friendly (the requirements rows table and the E2E test map).

Tracker items in the pilot repo (owner OK, D1–D2 date).

## 4. Not changed

Plan-review pass 1 and code-review pass 1 (full, fresh, Opus); test and proof volume rules; minors non-blocking; group integration (D1); models, apart from D2. Not adopted: an external watchdog or automatic quota retry, orchestrator bookkeeping reduction (needs its own design), direct mode, an implementer break-it check. Paused: task-graph and layer-first decomposition.

## 5. Owner decisions (2026-10-16)

- **D1. Integration stays once per group.** Per-member integration only helps when a later child depends on a subset of a group, and the pilot has no case where that cost critical-path time. One T1 per group is cheaper.
- **D2. Implementer thinking back to high.** Medium showed no speed gain and more code majors per child (confounded by larger children). The pilot repo's agent settings are reverted; the skills don't name a thinking level.
- **Pilot-repo tracker items** (§3) may be filed.

## 6. Measure (next epic vs pilot era D)

Per child on the critical path: refresh (and how many refreshes the scout skipped), plan-review passes, code-review pass-2 minutes, integration minutes, and ready-to-start wait (from `readyAt`). Per epic: hot-file conflicts, port failures, stale-lock failures, code majors by kind (especially planned-not-built and untested guards), and children per epic vs content grouping.

## 7. Rollout

1. Edit the skills on a branch; `./tests/run-tests.sh fast`; check the text is generic (`grep -iE` for product names).
2. Fresh review of this plan, then of the skill diff (pass cap 4).
3. Push with the owner's OK; flake bump and session restart. Applies from the next epic, or from a clean point in a running one.
