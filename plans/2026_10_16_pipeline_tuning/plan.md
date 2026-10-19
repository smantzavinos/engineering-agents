# Pipeline tuning from the process retrospective

**Status:** approved (plan pass 5; owner confirmed P-a…P-h on 2026-10-16) · **Date:** 2026-10-16 · **Evidence:** `plans/2026_10_15_process_retro/retro.md` (findings F1–F13, owner decisions of 2026-10-16) · **Changes:** `skills/scope`, `orchestrate` (+ `references/lanes.md`, `references/checkpoint-failures.md`), `plan` (+ new `references/plan-questions.md`), `implement`, `review`, `assess-repo`

## 1. Why

The fast-verification era was the most efficient: build fell to a median of 35 min per child. What remained on the critical path was overhead the process itself added (integration, refresh, review loops), about 53 min per child; in the next era it grew to about 78 min against 48 of build. The retrospective's adopted changes remove that overhead without weakening the reviews that caught real defects.

**Target:** per-child fixed overhead on the critical path of a serial chain back to about 40–50 min (from ~78), with no loss of code-review pass 1 or plan-review pass 1. Estimated saving 5–10 h per epic of the pilot's size (retro §3, not additive).

Skill text stays generic and concise: rules only, no pilot statistics. Evidence stays in this plan and the retro.

## 2. Execution model after the change

One model replaces "serial children in the work-branch worktree, lanes for groups":

- **With a worktree pool, every child runs as a lane:** in its own pool worktree, on a lane branch cut from the work-branch tip, and integrated through `lanes.md` → Integrating. A child that is in no group is a group of one. The work-branch worktree holds only the orchestrator's files, plan merges and integration merges.
- **A unit starts** — a group, or a child in no group (a group of one) — when every child its members depend on is integrated and a pool worktree is free for each member. Members start together and integrate together (D1). A group may have at most `maxLanes` members, and `maxLanes` is at most the pool size (`scope`). A lane counts as running until it is integrated. If no lane is running and the lowest-numbered ready unit still can't start (memory check, a rate-limit lane drop), stop for a re-scope of that group under Decisions.
- **Order:** ready units start in child-number order. While the lowest-numbered ready unit waits for worktrees, no later unit starts, so a group can't be starved.
- **Claims:** two units whose claims overlap are never running at once (one waits until the other integrates). Within a group, claims don't overlap (as today).
- **A group of one integrates by a plain merge** when the work branch has changed since the lane's base only in the orchestrator's files and plan directories: merge the lane branch into the work branch, with no integration worktree, integration branch or T1. This is the serial case today, with the lane's own T1 as the proof. Otherwise, the full `lanes.md` → Integrating procedure applies.
- **Without a pool,** children run serially in the work-branch worktree, in child order, as today.
- Group membership keeps its meaning: members may build at once and integrate together. Every child now needs a claim when the epic has a pool (`scope`).

This makes "start when dependencies are met" (retro decision 3) a single rule, and removes the serial-child special cases instead of adding to them.

## 3. Changes

### C1. Refresh only when something the plan relies on changed (decision 2; F1)

**`orchestrate`:** replace Close step 6's planned-ahead branch and the refresh text with a **Start** step (new Per child step, before Implement):

1. Prepare the lane worktree at the work-branch tip; that commit is the child's base. Record it. (Without a pool: the work-branch worktree at its HEAD.)
2. **Scout.** A `helper` in the lane worktree compares the integrated range — from the commit the child's plan branch was cut from (recorded in `state.json` when the plan loop starts), to the base, excluding the child's own directory — with:
   - every section of the plan;
   - the child's `epic.md` entry, Decisions and Follow-ups;
   - the ledgers of the children it depends on (deviations, follow-ups);
   - any checkpoint merge in the range.

   It appends `## refresh scout` to the child's ledger: per plan section, what changed, with paths; then `relevant` or `nothing relevant`. When unsure, it says `relevant`. It commits the ledger on the lane branch.
3. **Nothing relevant:** go to Implement. The implementer reads the note.
4. **Relevant:** a fresh `plan-author` refreshes the plan in the lane worktree (`plan` → Refresh), given the note. Any edit gets one fresh refresh review. Its majors are fixed by the plan-author and named in the implementer's task. A second refresh pass only if claims or scenarios changed. If the refreshed estimate passes the review-load signal, apply C3's separable-concerns check.

The old "only names and paths changed: no review" exemption and the ">20% estimate change" second-pass trigger are dropped: any edit is reviewed once (decision 2), and estimate changes no longer drive anything but the budget (C3).

**`plan` → Refresh:** rewrite for a fresh session in the lane worktree: read the scout note, the plan and the ledger; update what changed, including the estimate; commit one refresh commit; reply with the commit, old and new estimate, and whether claims or scenarios changed. No `self_compact` (refresh runs are short).

**`review` → Plan refresh:** add "Check that the edit itself is correct, not only that the plan still fits the integrated code."

**`implement` → Inputs and Build:** read `## refresh scout` if present. If it shows the plan is wrong in substance, stop and report (existing rule); the orchestrator sends the plan change to a fresh plan-author.

### C2. Start children when their dependencies are integrated (decision 3; F2)

**`orchestrate` and `lanes.md`:** apply §2.
- **Where work runs:** replace the "Serial children" bullet with §2's model; keep the no-pool fallback. "Merging into an unfinished child" applies to paused lanes only (with a pool).
- **`lanes.md` → Starting lanes:** "Run up to `maxLanes` children of one group at once" becomes "run up to `maxLanes` lanes at once, across groups, under §2's start rule". Memory, disk and E2E-worker checks stay; the E2E budget is split across all running lanes.
- **`lanes.md` → Integrating:** add the group-of-one plain merge from §2 before step 1.
- **Rules written in child order** become dependency or integration order:
  - **Checkpoints step 2:** remove "No child after C+1 in child order may start or be integrated until C is green and merged." Keep "The run for C+1 waits until C is green and merged" and the red-checkpoint handling: a red checkpoint pauses the children that build on the broken code (`checkpoint-failures.md` step 4). Checkpoints no longer gate starts or integration, so they can't deadlock with readiness order (P-g).
  - **Checkpoint placement** (`scope`): a checkpoint is named after a child and runs once that child, and every child it depends on, is integrated.
  - **Close step 1** (merge the next child's plan branch), **step 4** (last child before a checkpoint), **step 6** (plan the next child), **step 7** (next child's base): replaced by C1's Start step, the planning rule below, and the checkpoint rule above.
  - **Epic close** and **`checkpoint-failures.md` step 2:** "the last child in child order" → "the last child integrated".
- **Planning (Plan ahead):**
  - Up to two planning worktrees, each switched to a new plan branch at the work-branch tip per child.
  - A child's plan loop starts when every child it depends on has started implementing (or at once, if it has none). When more children qualify than worktrees are free, take the lowest-numbered.
  - Every child plans in a planning worktree, group members included (they no longer hold a pool worktree while planning). Remove the lines that say otherwise: `lanes.md` → Starting lanes ("Its plan-author … launch with their cwd in that worktree"; "group members plan in their own lane worktrees") and `orchestrate` → Sizing ("Each slice runs its own plan loop in its lane worktree").
  - Record the commit each plan branch is cut from (C1's scout range starts there).
  - When the loop is approved, merge the plan branch into the work branch (it touches only the child's directory) unless a group integration is in progress; then the planning worktree is free.
  - Plans written before a dependency is built use that dependency's approved plan in place of its code (as today).
- **`plan` → Inputs:** "the previous child's directory" → "the plans and ledgers of the children it depends on".
- **`scope` → epic.md:** each child lists its dependencies (the real dependency record) and, with a pool, a claim. Claims must not overlap within a group; across groups they may, and the start rule keeps overlapping children from running at once. A group has at most `maxLanes` members, and `maxLanes` is at most the pool size. The epic review checks both. `scope` → Steps 3 points to the review-load signal (C3) instead of "Size limit".
- **Claims for every child** (with a pool):
  - `plan` → Claims: "every child, when the epic has a pool" (not only group members);
  - `review` → plan mode: "claims stay inside the `epic.md` claim; for a group member, they don't overlap its siblings'";
  - `lanes.md` → Claims, replacing "runs serially after the group": a child (A) that needs files outside its claim reports it. If no unintegrated child that is not ordered with it (neither depends on the other) claims those files, the orchestrator widens the claim in `epic.md` under Decisions and the child continues. Otherwise, under Decisions, with B the overlapping child:
    - **B has not started:** B gets a dependency on A and leaves its group if it has one; A's claim is widened and A continues.
    - **B is running or finished:** A gets a dependency on B and leaves its group if it has one. A keeps its lane branch and worktree and waits; once B integrates, A merges the work branch into its lane (`orchestrate` → Merging into an unfinished child) and continues. B already holds its worktrees, so this can't hang.

    Adding a dependency between two unordered children can't create a cycle.
  - `lanes.md` → Starting lanes: the rate-limit rule drops one lane "until the next unit starts" (not "until the next group").
  - `lanes.md` → Integrating: remove the two clauses that refer to the removed checkpoint gate ("Checkpoints step 2 allows every member to integrate"; "for Checkpoints step 2 the group counts as one child").
- **`state.json`:** see C10.

### C3. Group children by content, not size (decision 4; F3)

Replacement text, by location:
- **`scope` → epic.md Children:** "with a rough estimate in changed lines, each within the size limit, and split below it only for parallel lanes" → "with a rough estimate in changed lines. A child is a cohesive vertical slice: a piece of behaviour with its data, logic, UI and tests, ending in a testable scenario."
- **`scope` → Size limit** becomes **Review-load signal:** "The changed lines a reviewer can judge in one pass (default about 7k, not counting generated files). A child above it is checked for separable concerns; it is split only if its concerns are separable and the pieces can run as parallel lanes. Never split serial or inherently related work to meet the number. Calibrate estimates, in lines and implementer hours, from the first children's actuals on the implementer model in use." Remove "Children over the limit are split before execution" and the paragraph on splitting under the limit.
- **`scope` → Budget:** "per child: the implementer hours for the plan's estimate × 1.5, plus the per-child fixed cost. Set provisionally from the `epic.md` estimate when the plan loop starts, replaced at plan approval, updated at refresh or resize, and recorded in `state.json`." `orchestrate` → Bounds reads the budget from `state.json`.
- **`scope` → Do:** keep "size children as vertical slices…"; add "group by content, not by size".
- **`plan` → Sizing:** "Estimate first. If the estimate is above the review-load signal, say whether the child mixes separable concerns. If it does and the pieces could run in parallel, stop before writing the full plan and propose the split, each piece with its scenarios, estimate and claim. Otherwise plan it whole. Propose merging this child with one it depends on only when their content belongs together." Remove the size-driven merge-with-the-next-child rule and "If it is trivially small, propose a merge".
- **`orchestrate` → Sizing and scope:** "reports the child over the epic's size limit, proposes a parallel split, or proposes a merge" → "proposes a split or a merge". Splits only into parallel lanes; a merge joins a child into the one it depends on when their content belongs together (not "consecutive serial children"). Record the new budget (C3) with the resize.
- **`review` → epic mode:** "each is within the size limit and split below it only for parallel lanes" → "each is a cohesive slice with declared dependencies; any child above the review-load signal has a reason not to be split".
- **`review` → plan mode:** "has an estimate within the size limit" → "states its estimate; above the review-load signal, says whether its concerns are separable".
- **`review` → Earlier passes:** in the plan-mode list of allowed later majors, "size" → "cohesion".

### C4. Code-review pass 2 checks only the fixes (decision 5; F6)

- **`orchestrate` → Per child, Implement loop:** each pass after pass 1 gets the range from the commit the previous pass reviewed to the implementer's tip (C10 records the reviewed commit per pass). If a merge into the child lies in that range, the task also names it.
- **`review` → Earlier passes, code mode:** "After pass 1, review only the range you were given, and verify each open finding there. For a merge in the range, review only its conflict resolution (`git show --remerge-diff <merge>`), not the incoming changes." The existing rule on new findings after pass 1 (blockers, majors, or caused by a fix) stays.
- **Same model** for every pass; no change to `implement` ("rerun only the gates the fix affects"); the ledger names the gates rerun and why.

### C5. Plan-review pass 2 only when needed (decision 6; F7)

- **`review` → plan mode, Findings and Reply:** tag every major with a kind: `design`, `boundary`, `claims`, `scope`, `cohesion` (these need a re-check) or `tests`, `T1`, `wording` (these don't). End the reply with `pass 2 needed: yes|no` — `yes` if any blocker or any major of the first group.
- **`plan` → Revising:** reply states whether any fix changed a contract (an interface, data shape, access rule or scenario), and lists rejected findings.
- **`orchestrate` → Per child, Plan loop:** skip pass 2 only when the reviewer said `no`, the plan-author fixed every major and rejected none, and no fix changed a contract. Then append `approved after fixes, no pass 2` to the ledger and record it in `state.json`. Otherwise run pass 2 as today.

### C6. Questions every plan answers where they apply (decision 7; F5, F13)

**`plan` → plan.md:** each question is answered in the section named, in a line or "n/a". Keep "aim for under 150 lines".

| Question | Section |
|---|---|
| Access and visibility: who can see and do what, including hidden or locked items; for each guard, its owning test | Design (rules), Tests (owning test per guard) |
| Failure and concurrency: errors, retry, two users at once, live updates | Design, Tests |
| Assumptions checked against the code: what the plan relies on exists; specs and files outside the edit list that the change affects | Context, Gates (T1) |
| Limits and load, for read-heavy features: platform limits and fan-out | Design, Risks |
| Deviations from the prototype or earlier decisions, with a reason | Design |
| Deliverables: the outcomes the build must contain — scenarios, specs, UI behaviours (not tasks) | Done when |

Test ownership stays as it is: one owning test per contract, at the boundary `test-quality` prescribes. The Don't rule becomes "Write task tables, execution tiers or step-by-step checklists (the Deliverables list of outcomes is not one)".

**`skills/plan/references/plan-questions.md` (new):** per question, one or two lines on what a good answer looks like and when "n/a" is right.

**`review` → plan mode:** a missing answer on access and visibility, failure and concurrency, or deliverables, where the child has that concern, is a major; on the others, a minor. Whether a planned guard test can fail stays a code-review check.

### C7. Implementer handoff maps deliverables to evidence (decision 8; F5)

- **`implement` → Handoff, ledger entry:** add "each Deliverable from the plan's Done when, with the file or test that delivers it, or *not done* with the reason". No extra test runs.
- **`review` → code mode:** a Deliverable that is missing from the map, marked done but not delivered, or not done without an accepted deviation is a major.
- **Not added:** an implementer break-it check (retro §4).

### C8. Reconcile in-flight runs after a restart (decision 9; F11)

- **`orchestrate` → State:** record every launch at launch time — run id, agent, child, phase, worktree, start — and mark it consumed when its result is read (C10).
- Replace "On start, after compaction, or after a crash … resume whatever was in flight" with: read `state.json`, `git status` in every worktree in use and `git log`; then, for every launch not yet consumed, check its status:
  - **finished:** consume the result (its completion notice may have been lost);
  - **still running:** wait for it;
  - **dead:** resume a plan-author or implementer per Recovery. For a reviewer, scout or helper, discard its uncommitted ledger edit, then relaunch it fresh. Only plan-authors and implementers are resumed.

  Never start a writer in a worktree whose last writer isn't confirmed stopped. Record each restart in `stops`.

### C9. Environment (decision 1; F4, F10)

- **`assess-repo` → Scan, Important** (when the repo uses a worktree pool or parallel E2E):
  - test-service port ranges are outside the OS ephemeral range or reserved from it, and the harness refuses a base that isn't;
  - the dev environment sets `GIT_OPTIONAL_LOCKS=0` (background git reads otherwise leave stale index locks);
  - files every child edits (requirement tables, test maps, registries) are merge-friendly: one row or file per entry, or generated. `epic.md` names them.
- **`lanes.md` → The pool:** the same three as preconditions for lanes.
- **Identical-tree reruns:** `implement` → Handoff records, per gate, `HEAD^{tree}` and the exact command line including selection. `implement` → Gates and `orchestrate` → Don't: don't rerun a gate whose tree and command line both match a passing run in the ledger. Trees are compared ignoring the orchestrator's files and plan directories.

### C10. State fields (measurement, retro §6)

`orchestrate` → State, per child: dependencies, plan-branch cut commit, `readyAt` (when the last dependency integrated), lane start, budget, scout outcome, per review pass its start, end, reviewed commit and majors by kind, `planPass2Skipped`; at the root: the launch list (C8). These feed §7 and replace ad-hoc state edits.

## 4. Pilot-repo work (tracked there)

Tracked in the pilot repo as #139 (ports), #140 (optional locks) and #141 (merge-friendly files).

## 5. Owner decisions (2026-10-16)

- **D1. Integration stays once per group.** Per-member integration only helps when a later child depends on part of a group, and the pilot has no case where that cost critical-path time. One T1 per group is cheaper.
- **D2. Implementer thinking back to high.** Medium showed no speed gain and more code majors per child (confounded by larger children). The pilot repo's agent settings are reverted; the skills don't name a thinking level.
- **Pilot-repo tracker items** (§4) filed.

**Proposed here and confirmed by the owner on 2026-10-16:**
- **P-a. Every child is a lane when there is a pool** (§2). Needed for "start when dependencies are met" without special cases; every child then needs a claim.
- **P-b. Plans merge into the work branch at approval; a needed refresh is done by a fresh plan-author in the lane worktree** (C1, C2). Frees planning worktrees early; the plan-author's state is on disk.
- **P-c. Refresh runs end without `self_compact`** (C1). Their end-of-run compaction sat on the critical path.
- **P-d. Drop the >20% estimate trigger for a second refresh pass** (C1). Estimates no longer drive splits.
- **P-e. Budget = plan estimate's implementer hours × 1.5 plus fixed cost, set at plan approval** (C3). Estimates were off by up to 2.7×; a tight budget would stop mis-estimated children.
- **P-f. Code pass 2 reads only the fix range** (C4), and plan pass 2 is skipped only under all of C5's conditions.
- **P-g. Checkpoints no longer gate starts or integration** (C2). Only the next checkpoint's run waits for the previous one to be green; a red checkpoint still pauses the children building on the broken code. Today a fan-out child can't even start past an unverified foundation, which costs time when the checkpoint is green (the usual case), and an integration gate deadlocks under readiness order.
- **P-h. A group of one integrates by a plain merge** when nothing but orchestrator and plan files moved on the work branch (§2), so a serial chain pays no extra integration T1.

## 6. Not changed

Plan-review pass 1 and code-review pass 1 (full, fresh, same model); test and proof volume rules and `test-quality`; minors non-blocking; group integration (D1); models, apart from D2. Not adopted: an external watchdog or automatic quota retry, orchestrator bookkeeping reduction (beyond C10's fixed fields), direct mode, an implementer break-it check. Paused: task-graph and layer-first decomposition.

## 7. Measure (next epic vs pilot era D)

From `state.json` (C10): per child on the critical path — ready-to-start wait, refresh (and scouts that skipped it), plan-review passes and pass-2 skips, code-review pass-2 minutes, integration minutes; per epic — children vs content grouping, hot-file conflicts, port and stale-lock failures, code majors by kind (especially missing deliverables and untested guards).

## 8. Rollout

1. Edit the skills on this branch, then `node tools/render-skills.mjs --write` and commit `dist/`.
2. `./tests/run-tests.sh fast`; `grep -iE` for product names.
3. Fresh review of the skill diff against this plan (pass cap 4).
4. Push with the owner's OK; flake bump and session restart. Applies from the next epic.
