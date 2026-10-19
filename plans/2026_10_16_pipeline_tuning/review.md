# Review ledger: pipeline tuning

## plan pass 1

Scope: `plan.md` (7fe3ce8) against `plans/2026_10_15_process_retro/retro.md` §3–§5, the current text of `skills/scope`, `orchestrate` (+ `references/lanes.md`, `checkpoint-failures.md`), `plan`, `implement`, `review`, `assess-repo`, and fast-verification plan §14–§17.

Coverage: every adopted retro decision (1–9, D1, D2) has a change (C9/§3, C1, C2, C3, C4, C5, C6, C7, C8). The gaps are in precision and in rules elsewhere that the changes leave contradicting them.

### P1-01 — major — C2 (ready-set start) doesn't say how serial children and children from different groups run
**Location:** §2 C2 bullet 1; `orchestrate` → Where work runs ("Serial children: run in the work branch's worktree", "Merging into the work branch … at any time in lane mode except during a group integration"); `lanes.md` → Starting lanes ("Run up to `maxLanes` children of one group at once").
**Problem:** "A child starts when every dependency is integrated and a pool worktree is free, regardless of child number or group order. Group membership only says which children may run at once." This leaves three things open:
- Serial children don't use pool worktrees. They run in the work-branch worktree, which must be free of writers for every group integration and checkpoint merge. If a ready serial child starts while a group is in flight, group integration can no longer merge into the work branch.
- If groups G1 and G2 are both ready, they may or may not run at the same time. Claims are only checked to be disjoint *within* a group, so two concurrent groups (or a group and a ready serial child) can edit the same files unchecked.
- With no pool, the rule is unclear: is the ready-set order still used, or child order?

**Fix:** pick one model and write it into `orchestrate` → Where work runs and `lanes.md` → Starting lanes:
- (a) Concurrency only within a group. The ready set just picks which group or serial child goes next, in dependency order.
- (b) Any ready child may run, each in its own pool worktree. A non-member counts as a group of one and integrates through `lanes.md` → Integrating. Children not in one group may overlap in time only if their `epic.md` claims are disjoint.

Either way, state the no-pool fallback.

### P1-02 — major — C2 leaves the child-order rules in place
**Location:** `orchestrate` → Checkpoints step 2 ("No child after C+1 in child order may start … or be integrated"), Close step 1 ("If the next child was planned ahead"), step 4 ("the last child before a checkpoint"), step 6 ("Plan the next child … the next child is a sibling"), step 7 ("the next child's base"), Plan ahead ("plan only one child ahead", "If child N and child N+1 are both serial"), Epic close ("last child in child order"); `lanes.md` → Integrating ("A checkpoint named after a group member runs after the group's last member"); `checkpoint-failures.md` step 2.
**Problem:**
- Once children start out of order, "next child" and "child after C+1 in child order" no longer describe what is running.
- Checkpoint gating can become wrong. A higher-numbered child that becomes ready early could start past an unmerged checkpoint, or be blocked for no reason.
- C2 lists none of these edits, so the editor has to invent the semantics.

**Fix:** in C2, list each rule above with its replacement in dependency or integration-order terms. For example:
- Checkpoints are positions in integration order.
- No child may integrate past checkpoint C+1, and no serial child may start past it, until C is green and merged.
- "Plan the next child" becomes "plan every child whose dependencies have all started implementing, up to the planning worktrees".
- Epic close uses the last child integrated.

### P1-03 — major — C2: two planning worktrees and their plan branches are underspecified
**Location:** §2 C2 "Planning worktrees"; `orchestrate` → Plan ahead → Where ("switch it to a new plan branch … only when it is clean and the previous plan branch has merged"), Per child step 1 and `plan` → Inputs ("the previous child's `plan.md` and ledger"); `lanes.md` "group members plan in their own lane worktrees".
**Problem:**
- "Previous plan branch has merged" is meaningless with two worktrees. It's also unsaid which plan branch Close step 1 merges, and when: at its child's start or at its dependency's close.
- The plan-author's inputs are still "the previous child", but under C2 the relevant input is the child's *dependencies'* plans and ledgers. `plan` isn't on C2's change list.
- "Start when its last dependency starts implementing" has no clear meaning for a child with dependencies in several chains. It should be "when all its dependencies have started implementing".
- There is no priority rule for when more than two children qualify.
- Group members plan in lane (pool) worktrees. If they plan ahead, a member holds a pool worktree from plan start, on a lane branch cut before its dependency integrates. That interacts with "a pool worktree is free" as the start condition and with the lane base.
- "Each plans the next ready child" contradicts planning *ahead* of readiness.

**Fix:**
- In `orchestrate` → Plan ahead, define:
  - the trigger (all dependencies implementing);
  - the slot rule (up to two planning worktrees, each on its own plan branch at the work-branch tip; the oldest-numbered or critical-path child first);
  - the merge point (a plan branch merges when its child starts, after the scout or refresh).
- Say whether group members may plan ahead and where. If they do, say how the lane base moves when the dependency integrates (merge the work branch at refresh time).
- Add a `plan` → Inputs edit: the plans and ledgers of the children it depends on.

### P1-04 — major — C1 refresh scout: wrong range, too narrow a comparison, and no owner for the judgment
**Location:** §2 C1 steps 1–2; `orchestrate` Close step 6 (current range "the plan's approval commit to the merge from Refresh step 1"); `plan` → Refresh step 2; `implement` → Inputs.
**Problem:**
- **Range:** "the plan's approval commit to the merge" points at the merge from `plan` Refresh step 1. When the scout runs first, that merge doesn't exist yet. `git diff <approval> <tip>` would also show the plan itself reversed.
- **Comparison:** the scout compares the range only with Context, Changes, Tests and Claims. `plan` → Refresh step 2 also checks changes to the child's `epic.md` entry, Decisions and Follow-ups (which Close step 5 may edit), the predecessors' ledgers (deviations), and any checkpoint merge (base-branch changes). An entry edit or a checkpoint merge can make the plan stale while touching none of the four sections. That is the "nothing relevant" case the scout would miss.
- **Timing:** a checkpoint may merge into the work branch after the scout ran but before step 7 records the base, so the implementer builds on code nobody compared.
- **Judgment:** a fast `helper` now makes the call that skips a refresh and a review. Nothing says what to do when it is unsure, or what the implementer does if the note is wrong. `implement` doesn't mention the note.
- **Commit point:** unstated. It could be the plan branch in the planning worktree, the lane worktree or the work branch.

**Fix:**
- Define the range as `git merge-base <plan branch> <work branch>`..`<work-branch tip at scout time>` (equivalently `<plan branch>...<work branch>`), stated to include `epic.md`, ledgers and checkpoint merges.
- Have the scout check the child's entry, Goal and scenarios, Decisions and Follow-ups as well as the four sections. It reports facts per plan section with paths, and "relevant" when unsure.
- Record the scouted tip as the child's base. If the work branch moved before the implementer starts, scout the delta.
- The scout commits the note on the plan branch before it merges.
- Add to `implement` → Inputs/Build: read `## refresh scout`. If the plan is wrong in substance because of it, stop and report. The orchestrator then sends it to a fresh plan-author (Plan ahead, "after a child's implementer starts").

### P1-05 — major — C1 says the review rule is "unchanged", but it changes, and the rest of Close step 6 now contradicts it
**Location:** §2 C1 step 3; `orchestrate` Close step 6, planned-ahead branch; `plan` → Refresh step 4.
**Problem:**
- Retro decision 2 says *any* edit to the plan gets one review pass. Current Close step 6 says "if only names and paths changed, no review". C1 calls the rule "unchanged" and doesn't say to remove that exemption.
- C1's second-pass trigger silently drops "or the line estimate moved by more than 20%".
- Close step 6 still says "If the plan is now over the size limit, resize", which conflicts with C3 (size is no longer a split trigger).
- `plan` Refresh step 4 still asks the plan-author to report "or only names and paths". The editor has to guess which of these survive.

**Fix:** write the full replacement text of Close step 6's planned-ahead branch:
- scout;
- if relevant, refresh;
- any edit gets one refresh review;
- a second pass only if claims or scenarios changed (state that the 20% trigger is dropped, and why);
- over the review-load signal, apply the C3 separable-concerns check.

Update `plan` → Refresh step 4 to match.

### P1-06 — major — C3: the budget rule is in the wrong skill and has no timing, yet it sets a stop condition
**Location:** §2 C3 orchestrate bullet ("Budget per child is set from its own estimate plus the fixed cost"); `scope` → Budget ("set for a child at the size limit"); `orchestrate` → Bounds (deadlines and budget stops read `epic.md`).
**Problem:**
- The budget is defined in `scope`/`epic.md`, not in `orchestrate` → Sizing. C3 doesn't edit `scope` → Budget.
- It doesn't say which estimate counts: the rough scope estimate, the plan estimate, or the refreshed one. Nor when the budget is written, or whether a refresh or resize re-budgets.
- The retro found estimates off by 1.6–2.7×. A budget tied to a single estimate with no margin will stop children that are merely mis-estimated, and a budget overrun is a stop for the human.

**Fix:**
- `scope` → Budget: per child, the implementer hours for its estimate times an explicit margin, plus the per-child fixed cost.
- Set it at plan approval from the plan's estimate, and update it at refresh or resize. Record it in `state.json`. Bounds reads it from there.

### P1-07 — major — C3 doesn't say what replaces each size rule
**Location:** §2 C3; `scope` line "Children over the limit are split before execution"; `plan` → Sizing ("If the child exceeds the epic's size limit, stop before writing the full plan"; "If it is trivially small, propose a merge"); `review` plan mode ("has an estimate within the size limit") and Earlier passes ("… claims, scope or size"); `orchestrate` → Sizing ("reports the child over the epic's size limit").
**Problem:**
- C3 says what to remove in `scope` but not what replaces the plan-mode review check. It also doesn't say whether a planner over the signal still stops before writing the plan, or plans it and reports.
- "Keep 'consecutive serial children with related content may merge'" quotes text that doesn't exist in `scope`. It is `orchestrate` → Sizing's "Merge: only consecutive serial children". Under C2, "consecutive" also needs a dependency meaning.
- The calibration bullet ("calibrated from the first children's actuals") names no skill or section.

**Fix:** give, for each location above, the sentence that replaces the old one. For example:
- `review` plan mode: "the estimate is stated; over the review-load signal, the plan says whether concerns are separable".
- `plan` → Sizing: over the signal, stop before writing only if proposing a parallel split.
- `review` → Earlier passes: replace "size" with "cohesion".
- Merges: "a child merges into its sole dependent when their content belongs together".
- Put the calibration rule in `scope` → Size limit (it is already half there) and in `orchestrate` → Sizing.

### P1-08 — major — C5: nobody is told how to classify majors or what happens to a rejected finding
**Location:** §2 C5; `orchestrate` Per child step 1, Do ("Keep what you take in small"), Don't ("Plan, implement or review yourself"); `plan` → Revising; `review` → Findings and Reply.
**Problem:**
- The skip depends on each major's *kind*, but the ledger records only severity. The orchestrator would have to read and judge the findings, which is review work and context it is told to avoid.
- The trigger sentence names only "design or boundary". The parenthesis also excludes claims, scope and size, so those cases are ambiguous.
- Blockers aren't mentioned.
- C6's new majors (missing deliverables, failure/concurrency answers) have no kind.
- `plan` → Revising lets the plan-author *reject* a finding. Adjudication relies on a later reviewer disputing it, so with no pass 2 a rejected major stands unchallenged.
- Nothing records in the ledger or `state.json` that the plan was approved without a pass 2.

**Fix:**
- `review` plan mode: tag each major with a kind (design, boundary, claims, scope or cohesion vs tests, T1 or wording). End the reply with "pass 2 needed: yes/no".
- `orchestrate`: skip pass 2 only when:
  - the reviewer says no;
  - there are no blockers;
  - the plan-author fixed every major and rejected none;
  - the plan-author reports that no fix changed a contract.

  Then append "approved after fixes, no pass 2" to the ledger and record it in `state.json`.

### P1-09 — major — C6 question 3 contradicts `test-quality` on which layer owns a test
**Location:** §2 C6 item 3 ("each contract has one owning test at the lowest layer that proves it"); `test-quality` → Before adding ("one primary owner, at the strongest boundary that can see it") and Choose the layer (authorization, visibility, persistence → backend through the real path).
**Problem:** "Lowest layer" invites unit-level proofs of authorization and visibility guards. That is the escaped-defect class C6 item 1 targets, and `test-quality` puts those guards at the real backend path. Plan-authors and reviewers would get opposite rules.
**Fix:** word item 3 as `test-quality` does ("one owning test, at the strongest boundary that can see it (`test-quality`)"), or just point to `test-quality`.

### P1-10 — major — C6's deliverables list conflicts with the plan skill's checklist bans, and the questions have no home section
**Location:** §2 C6 items 1–2 and "answered inside the existing sections (Design, Tests, Risks)"; `plan` → plan.md Tests ("This is not a test checklist"), Don't ("step-by-step checklists"); `scope` → Don't ("test checklists"); `review` plan mode ("whether a planned test can fail are for code review; here they are minors").
**Problem:**
- Item 2 requires "the scenarios, specs, UI behaviours and tests the build must contain" as the implementer's checklist, and review makes a missing one a major. The same skill forbids test checklists and step-by-step checklists, so a plan reviewer can flag the list either way.
- Deliverables fit none of Design, Tests or Risks, and nothing says where items 4–7 go.
- Item 1 asks for "the test that fails if the guard is removed", while plan review is told that whether a planned test can fail is a code-review minor.

**Fix:**
- Define Deliverables as a short list of *outcomes* (scenarios, specs, UI behaviours), not tasks, and place it in "Done when". Amend the checklist ban to exempt it.
- Map each question to a section.
- For item 1, require at plan time the owning test for each guard. Whether that test can fail stays a code-review check.

### P1-11 — major — C4: the fix range ignores merges into the child between passes
**Location:** §2 C4 ("the commit pass 1 reviewed, to the implementer's fix commit"); `orchestrate` → Where work runs ("Merging into an unfinished child"), Checkpoints step 2 ("The resolution is part of its own diff from the new base, so its normal T1 and code review cover it"); `lanes.md` → Checkpoints in lane mode.
**Problem:**
- A stopped serial child or a paused lane can merge the work branch or a green checkpoint between pass 1 and pass 2. A plain `<reviewed>..<tip>` diff then contains all the incoming base changes, while the conflict resolution — which Checkpoints step 2 relies on code review to cover — is buried in the merge. Pass 2, told not to reread anything else, either drowns in base changes or misses the resolution.
- For pass 3 and later, "the commit pass 1 reviewed" should be the commit the previous pass reviewed.
- Fixes may be several commits, not "the fix commit".

**Fix:**
- The range is from the commit the previous pass reviewed (record it per pass in `state.json`) to the implementer's tip.
- If a merge into the child lies in that range, the reviewer also gets `git show --remerge-diff <merge>` and ignores the incoming base changes.
- Phrase it once in `review` → Earlier passes (code mode) and once in `orchestrate` step 2.

### P1-12 — major — C8: recovery has no complete run record, and "replace" can create a second writer
**Location:** §2 C8; `orchestrate` → State (per child: "the latest planner and implementer run ids"; root: checkpoint, group runs), State line 18 ("On start, after compaction, or after a crash … resume whatever was in flight"), Where work runs ("One writer per worktree").
**Problem:**
- "Every run recorded as in flight in `state.json`" doesn't cover reviewers, refresh scouts, gate helpers or plan reviewers. Those runs aren't recorded today, and their lost completions are what decision 9 is about.
- "The stop record" is undefined.
- "Resume or replace the others" doesn't separate a run that is still running from one that died. Replacing a running implementer or plan-author puts two writers in one worktree.
- C8 adds a second recovery rule next to State line 18 instead of amending it.

**Fix:**
- In `orchestrate` → State, record every launch at launch time (run id, child, phase, worktree) and clear it when its result is consumed. This matches retro §6 item 2.
- Replace State line 18 with the reconcile procedure:
  - finished: consume the result;
  - still running: wait;
  - dead: resume writers; relaunch read-only runs.
- Never start a writer in a worktree whose last writer isn't confirmed stopped.
- Name the stops list in `state.json` as the "stop record".

### P1-13 — minor — C9: "identical tree" alone doesn't make a gate run identical
**Location:** §2 C9 last bullet; `implement` → Handoff ledger contents; `lanes.md` Integrating step 4.
**Problem:**
- The ledger records no tree hash today.
- T1 selection depends on the base as well as the tree: a member's T1 selects from its lane base, the group T1 from the group base. The same tree under a different selection or command set isn't the same gate.

**Fix:** record `HEAD^{tree}` and the exact command line (including selection) per gate in the ledger. Skip a rerun only when both match (retro §6 item 4).

### P1-14 — minor — C9: the assess-repo checks have no location, and the lock setting may belong here
**Location:** §2 C9 assess-repo bullet; `assess-repo` → 2. Scan (Essential/Important/Recommended).
**Problem:**
- The three checks have no tier or section, and they apply only when the repo runs parallel E2E or a worktree pool.
- `GIT_OPTIONAL_LOCKS=0` is an agent-session setting. This repo already configures Pi through Nix, so setting it there would cover every repo, not just those that remember it.

**Fix:**
- Put the three checks under Important, conditional on a worktree pool or parallel E2E.
- Consider setting the variable in the Pi module, alongside the per-repo check.

### P1-15 — minor — Some changes go beyond the owner decisions
**Location:** §2 C1 (refresh without `self_compact`; second-pass trigger without the 20% rule), C3 (budget from own estimate), C4 (code mode after pass 1: new findings only from fixes or blockers, dropping new majors), C2 (scope review checks declared dependencies).
**Problem:** retro §4 and plan §5 don't record these as decisions. They may be sound, but the plan is "draft for owner review", and the owner should see them as choices rather than read them as restatements.
**Fix:** list them under §5 as proposals for the owner to confirm, each with its one-line reason.

### P1-16 — minor — Pilot evidence would leak into skill text
**Location:** §2 C1 `review` bullet ("note that refresh edits are where two of four refresh majors came from"), C5 `plan` bullet ("In the pilot, …").
**Problem:** skills should stay generic and concise. Statistics from a pilot age quickly and add nothing to the rule.
**Fix:** give the exact rule text (e.g. `review` → Plan refresh: "Check that the edit itself is correct, not only that the plan fits the code"). Keep the evidence in this plan.

### P1-17 — minor — C7: review only catches items falsely marked done
**Location:** §2 C7 `review` bullet.
**Problem:** "an item marked done that isn't is a major" misses two cases:
- plan deliverables missing from the map;
- items marked *not done* without an accepted deviation.

These are the planned-not-built defects the change targets.
**Fix:** treat a deliverable that is missing from the map, falsely marked done, or not done without an accepted deviation (`implement` → "in substance: stop and report") as a major.

### P1-18 — minor — The §6 measures have no state fields to come from
**Location:** §6; C2 `state.json` bullet.
**Problem:** only `readyAt` and lane start are added. Nothing is recorded for:
- how many refreshes the scout skipped;
- pass-2 minutes and reviewed commits;
- plan pass 2 skipped;
- majors by kind.

The next epic can't be measured against era D without those.
**Fix:** add these fields to C2's `state.json` bullet: the scout outcome per child, start, end and reviewed commit per review pass, pass-2-skipped, and the major kinds from P1-08's tags.

### P1-19 — minor — Rollout skips rendering, and the new reference file is unspecified
**Location:** §7 step 1; §2 C6 ("`skills/plan/references/plan-questions.md`").
**Problem:**
- `AGENTS.md` requires `node tools/render-skills.mjs --write` and committing `dist/` after any skill change; `skill-render-spec.sh` in the fast suite fails on a stale `dist/`.
- The new reference file's contents ("detail and examples") are unspecified. `skills/AGENTS.md` wants references for durable templates and checklists.

**Fix:**
- Add the render step to §7.
- Say in one or two lines what `plan-questions.md` holds: per question, what a good answer and an n/a look like.

**Verdict:** changes needed — 0 blocker, 12 major, 7 minor.

## author response to pass 1

All findings addressed in the plan revision; section numbers refer to the revised plan.
- P1-01: §2 one execution model — with a pool every child is a lane (non-members are groups of one), start rule includes disjoint claims across running children, no-pool fallback is serial in child order.
- P1-02: C2 lists each child-order rule with its replacement (checkpoint gating in integration order, placement, Close steps 1/4/6/7, epic close, checkpoint-failures step 2).
- P1-03: C2 Planning — trigger, two worktrees, lowest-numbered first, every child plans in a planning worktree, plan branch merges at approval; `plan` → Inputs edit.
- P1-04: C1 Start step — range from the plan-merge commit to the recorded base (lane cut at the tip, so the base cannot move), scout checks every plan section plus entry, Decisions, Follow-ups, dependency ledgers and checkpoint merges, says `relevant` when unsure, commits on the lane branch; `implement` reads the note.
- P1-05: C1 gives the full replacement and states what is dropped and why; size check routed to C3.
- P1-06: C3 `scope` → Budget (×1.5 margin, set at plan approval, updated at refresh/resize, in `state.json`; Bounds reads it). Margin listed as P-e for the owner.
- P1-07: C3 gives replacement text per location.
- P1-08: C5 — reviewer tags major kinds and states `pass 2 needed`; skip conditions include no blockers, no rejections, no contract change; recorded.
- P1-09: C6 keeps `test-quality`'s boundary rule; the "lowest layer" wording is gone.
- P1-10: C6 — Deliverables are outcomes in Done when, checklist ban amended; each question mapped to a section; guard item asks for the owning test only.
- P1-11: C4 — range from the previous pass's reviewed commit; merges reviewed by remerge-diff only.
- P1-12: C8 — launch list in `state.json`, reconcile procedure replaces the State recovery line, no second writer, restarts recorded in `stops`.
- P1-13: C9 — tree hash and exact command line per gate; skip only when both match.
- P1-14: C9 — Important tier, conditional on pool or parallel E2E. Setting the variable in the Pi module is not taken up: it would change git behaviour for every shell on the machine; the per-repo check plus the pilot repo's item is enough.
- P1-15: §5 "Proposed here, for the owner to confirm" (P-a … P-f).
- P1-16: skill text carries rules only (§1 note); pilot evidence removed from C1 and C5.
- P1-17: C7 covers missing, falsely done and unexplained not-done deliverables.
- P1-18: C10 state fields.
- P1-19: §8 render step; C6 specifies `plan-questions.md`.

## plan pass 2

Scope: revised `plan.md` (376ccb0), checked against the current text of `orchestrate` (+ `lanes.md`, `checkpoint-failures.md`), `scope`, `plan`, `implement`, `review`, `assess-repo` and `test-quality`. Pass-1 findings were verified in the plan text, not the response. New findings are limited to blockers and majors, plus minors the revision caused.

### Pass-1 findings
- P1-01: resolved. §2 picks one model: with a pool, every child is a lane and a non-member is a group of one. The start rule includes disjoint claims across running children, and the no-pool fallback is stated. The model introduces new problems (P2-01–P2-04).
- P1-02: resolved. Each child-order rule has a replacement. The new checkpoint rule can deadlock (P2-01).
- P1-03: resolved. The trigger, the two planning worktrees, priority, group members, the merge at approval and the `plan` → Inputs edit are all specified.
- P1-04: **open.** The scout's judgment, inputs, timing (the base can't move) and commit point are fixed, and `implement` reads the note. The range is still wrong. C1 step 2 starts it at "the commit that merged the child's approved plan into the work branch". The plan was written against the work-branch tip at which its plan branch was cut (C2: "a new plan branch at the work-branch tip"). Everything integrated between that cut and the plan merge falls outside the range. That includes a dependency's code: the planning trigger is "every child it depends on has started implementing", so a dependency often integrates while the plan loop is still running, or while the merge waits out a group integration. That dependency's code is exactly what the refresh exists for. Reading the dependency's ledger doesn't make up for the missing code diff. **Fix:** start the range at the plan branch's fork point: `git merge-base <plan-merge>^1 <plan-merge>^2`, or the plan-branch start commit recorded in `state.json`.
- P1-05: resolved. C1 step 4 and the following paragraph give the full replacement and say what is dropped and why. `plan` → Refresh step 4 matches.
- P1-06: resolved. One gap follows from the fix (P2-05).
- P1-07: resolved. There is replacement text for each location, and the calibration rule is in `scope`. A leftover reference is recorded under P2-06.
- P1-08: resolved. Majors are tagged by kind, the reply says `pass 2 needed`, blockers force pass 2, the skip conditions include no rejections and no contract change, and the skip is recorded.
- P1-09: resolved. The "lowest layer" wording is gone, and ownership defers to `test-quality`.
- P1-10: resolved. Deliverables are outcomes under Done when, the Don't rule exempts them, every question has a section, and "can the guard test fail" stays in code review.
- P1-11: resolved. The range runs from the previous pass's reviewed commit, and merges in it are reviewed via remerge-diff.
- P1-12: resolved. There is a launch list, a reconcile procedure that replaces the State line, and a no-second-writer rule. A small classification issue is under P2-07.
- P1-13: resolved. Each gate records its tree hash and exact command line.
- P1-14: resolved. The checks are in the Important tier, conditional on a pool or parallel E2E. The author's rejection of the Pi-module setting is accepted (minor).
- P1-15: resolved. §5 lists P-a…P-f. One new design choice is missing from that list (see P2-01).
- P1-16: resolved.
- P1-17: resolved.
- P1-18: resolved (C10).
- P1-19: resolved (§8 step 1, C6 reference file).

### P2-01 — major — The new checkpoint gating deadlocks when checkpoint C+1's child integrates before checkpoint C's child
**Location:** §3 C2 "Checkpoints step 2" and "Checkpoint placement"; `orchestrate` → Checkpoints step 2 ("The run for C+1 waits until C is green and merged").
**Problem:**
- Under §2, children integrate in readiness order, not child order. The replacement rule reads: "No child may integrate after checkpoint C+1's child is integrated until C is green and merged."
- Checkpoint C runs only once its own child and that child's dependencies are integrated.
- Suppose C+1's child doesn't depend on C's child, and it integrates first. Then C's child may not integrate, because C isn't green. C can't run, because its child isn't integrated. Nothing moves, and the run stalls with no stop condition.
- This is likely in exactly the DAG-shaped epics C2 is for: checkpoints are placed "no more than about a day of children apart", not along one chain.
- Separately, "Starting is no longer gated" is a design change: today, fan-out children can't start past an unverified foundation. The owner hasn't seen it as a choice; §5 doesn't list it.

**Fix:**
- Define the gate so that it can't block C's own prerequisites. For example: "a checkpoint's child may not integrate until every earlier checkpoint's child (and its dependencies) has integrated". Or treat checkpoints as positions in integration order: checkpoint C fires at the integration that completes its child's dependency set, and C+1's child may integrate earlier but doesn't trigger C+1 until C has run.
- Add the ungated start to §5 as P-g, with its reason.

### P2-02 — major — With every child a lane, the claim rules still assume only group members have claims, and the claim-violation fallback no longer exists
**Location:** §2 ("Every child now needs a claim when the epic has a pool"); §3 C2 (`scope` edit only); `lanes.md` → Claims ("The child then runs serially after the group"); `plan` → plan.md Claims ("only for a child in a parallel group"); `review` plan mode ("for a parallel child, claims that stay inside its `epic.md` claim, which doesn't overlap its siblings' claims"); `scope` → Parallel groups (claims are defined only for members).
**Problem:**
- Every child now has a claim, and the start rule depends on it.
- A child that used to be serial (often foundation or cross-cutting work) now stops its lane whenever its plan, refresh or build needs a file outside its claim. The only remedy written is "runs serially after the group", which doesn't exist when there is a pool.
- `plan` still writes Claims only for group members. Plan review still checks claims only "for a parallel child". So the claims the start rule reads are never refined or reviewed for most children.
- C2 lists none of these edits.

**Fix:**
- C2 should edit `plan` → Claims ("every child, when the epic has a pool") and `review` plan mode ("claims stay inside the `epic.md` claim; for a group member, they don't overlap its siblings'").
- C2 should also replace `lanes.md` → Claims' fallback. For example: "a child that needs files outside its claim reports it. The orchestrator widens the claim in `epic.md` under Decisions if no running child's claim overlaps the addition; otherwise the child waits (or pauses) until those children integrate".
- `scope` → epic.md should define claims for every child, with no-overlap required only within a group.

### P2-03 — major — "Members of a group start together" can starve a group that is larger than the free pool
**Location:** §2 bullet 2 ("a pool worktree is free for each member … members of a group start together"); §3 C2 `lanes.md` → Starting lanes ("run up to `maxLanes` lanes at once").
**Problem:**
- Today a group runs "up to `maxLanes` children of one group at once", so a group larger than `maxLanes` or the pool is legal and runs in waves.
- Under the new rule, such a group can never start: the pool or `maxLanes` can never offer one worktree per member.
- A smaller group still waits until enough lanes are free at the same moment. Meanwhile, lower-priority children keep taking worktrees as they free up, so the group can starve.
- D1 needs members to *integrate* together, not to start together.

**Fix:** let members start individually under the start rule, as worktrees free up. Keep integration once per group. To prevent starvation, a group that is ready gets the next free worktree ahead of non-members, or ahead of children numbered after it.

### P2-04 — major — Every serial-chain child now pays a full group integration, including a group T1 that the identical-tree skip will almost never cover
**Location:** §2 bullet 1 (a group of one "integrated through `lanes.md` → Integrating"); §3 C9 last bullet; `lanes.md` → Integrating steps 1, 3 and 6, and → The pool ("reset the test data"); `orchestrate` → Where work runs ("commit them as you go"); §3 C2 Planning ("merge the plan branch into the work branch" at approval).
**Problem:**
- Before, a serial child closed with no integration. Under §2 each serial child takes these steps before its dependent can start:
  - find an integration worktree;
  - prepare it (switch branch, maybe reinstall, reset test data);
  - cut `integration/<group>`;
  - merge;
  - run a group T1;
  - merge into the work branch.
- C9 skips a rerun only when the tree and the command line match a passing run. But the work branch moves between lane cut and integration with every orchestrator state commit and every approved plan merge (C2), so the integration tree almost never equals the lane tip. The group T1 then reruns in full on the critical path for every child of a chain.
- This works against the §1 target, where integration is one of the overheads being cut. §7 would show it as a regression.

**Fix:** add a group-of-one fast path to `lanes.md` → Integrating. When the work branch has changed since the lane base only in the orchestrator's files and plan directories (`git diff --name-only <lane base> <work-branch tip>` outside those paths is empty):
- merge the lane branch directly into the work branch (or integrate in the lane's own worktree);
- skip the separate integration worktree, the integration branch and the group T1.

Otherwise use the full procedure. State the same exclusion in C9's identical-tree rule (code tree equal, ignoring orchestrator and plan files).

### P2-05 — minor — No budget or deadline exists before plan approval
**Location:** §3 C3 `scope` → Budget ("Set at plan approval"); `orchestrate` → Bounds ("planner and implementer from the child's budget"; wall time includes the "plan loop").
**Problem:**
- The plan loop counts toward the child's wall-time budget, and the plan-author's deadline is derived from that budget. But the budget only exists after the plan is approved.
- Without one, the planner falls back to the harness default of 30 minutes, which Bounds calls far too short.

**Fix:** set a provisional budget from the `epic.md` rough estimate (same formula) when the plan loop starts, and replace it at approval.

### P2-06 — minor — The edit list misses several lines the new model makes wrong
**Location:** §3 C1 Start step, C2, C3.
**Problem:**
- C1's Start step only covers runs with a pool: "prepare the lane worktree", scout, and refresh "in the lane worktree". The no-pool fallback (§2 bullet 3) has no Start step location or base.
- Three lines still contradict C2's "every child plans in a planning worktree":
  - `lanes.md` → Starting lanes line 10 ("group members plan in their own lane worktrees");
  - the lane-worktree line 6 ("Its plan-author … launch … in that worktree");
  - `orchestrate` → Sizing ("Each slice runs its own plan loop in its lane worktree").
- `scope` → Steps 3 ("fits within a size limit (see `epic.md` → Size limit…)") still refers to the section that C3 renames.

**Fix:**
- Add "without a pool: the work-branch worktree at its HEAD" to C1's Start step 1.
- List the three lane-worktree planning lines in C2.
- Point `scope` step 3 at the review-load signal.

### P2-07 — minor — C8 calls reviewers and scouts read-only, but both commit to the ledger
**Location:** §3 C8 "dead: … relaunch a read-only run (reviewer, scout, helper)"; `review` → Findings (commit the ledger); C1 step 2 (scout commits); `orchestrate` → Recovery ("A dirty tree … belongs to an interrupted session. Resume that session").
**Problem:** a dead reviewer or scout can leave an uncommitted ledger edit. A relaunched run then starts on a dirty tree, which Recovery says belongs to the interrupted session.
**Fix:** before relaunching a dead reviewer or scout, discard its partial ledger edit, or have the fresh run take it over. Say that only implementers and plan-authors are resumed.

**Verdict:** changes needed — 0 blocker, 5 major (P1-04 open, P2-01–P2-04), 3 minor (P2-05–P2-07).

## author response to pass 2

- P1-04: scout range now starts at the commit the plan branch was cut from, recorded in `state.json` (C1 step 2, C2 Planning, C10).
- P2-01: gate is now "checkpoint C+1's child may not integrate until C is green and merged", with checkpoints required to follow dependency order (so C's own prerequisites are never blocked). Ungated starts listed as P-g.
- P2-02: claims for every child: `plan` → Claims, `review` plan mode, `lanes.md` → Claims fallback (widen if no running overlap, else pause until they integrate), `scope` overlap rule within groups only.
- P2-03: members start individually; integration stays together; lowest-numbered ready child first.
- P2-04: group-of-one plain merge when only orchestrator and plan files moved (§2, `lanes.md` → Integrating); identical-tree comparison ignores those files (C9). Listed as P-h.
- P2-05: provisional budget from the `epic.md` estimate at plan start.
- P2-06: no-pool Start base; the three lane-worktree planning lines listed for removal; `scope` step 3 pointer.
- P2-07: dead reviewer/scout/helper: discard its uncommitted ledger edit, relaunch fresh; only plan-authors and implementers are resumed.

## plan pass 3

Scope: `plan.md` at cf42308, checked against the current `orchestrate` (+ `lanes.md`, `checkpoint-failures.md`) and `scope`. Open findings were verified in the plan text. New findings are limited to blockers and majors, or to issues the latest revision caused.

### Open findings
- P1-04: resolved. C1 step 2 starts the range at the commit the plan branch was cut from. C2 Planning records that commit and C10 stores it, so code integrated during the plan loop is in range.
- P2-01: partly resolved. The direct case is fixed: C2 gates only C+1's child on C, and adds the dependency-order rule. The rule is too narrow to prove "the gate can't deadlock", though, so the issue continues as P3-01. P-g lists the ungated start.
- P2-02: resolved. C2 "Claims for every child" edits `plan` → Claims, `review` plan mode and `lanes.md` → Claims, and `scope` limits the no-overlap rule to within a group. The new fallback creates P3-03.
- P2-03: the starvation part is resolved: members start individually, and the lowest-numbered ready child goes first. The case of a group larger than the pool is not resolved. Such a group now starts but can never integrate. It is carried, with the new cross-group case, as P3-02.
- P2-04: resolved. §2 and C2 add the group-of-one plain merge, C9 compares trees ignoring orchestrator and plan files, and P-h lists the change. The merge is still an integration, so the checkpoint gate and the "no merge during a group integration" rule apply to it, and a code change on the work branch falls back to the full procedure. That is correct.
- P2-05: resolved (C3 `scope` → Budget, provisional budget at plan start).
- P2-06: resolved. C1 step 1 states the no-pool base, C2 Planning lists the three lane-worktree lines, and C2 `scope` updates Steps 3.
- P2-07: resolved. In C8, a dead reviewer, scout or helper has its uncommitted ledger edit discarded and is relaunched fresh. Only plan-authors and implementers are resumed.

### P3-01 — major (design) — The checkpoint dependency-order rule doesn't cover transitive dependencies or groups, so the gate can still deadlock
**Location:** §3 C2 "Checkpoint placement" ("a checkpoint's child may not depend on a later checkpoint's child … so the gate can't deadlock"); `lanes.md` → Integrating ("A checkpoint named after a group member runs after the group's last member; for Checkpoints step 2 the group counts as one child").
**Problem:**
- Checkpoint C runs only once its child and every child it depends on are integrated. A group member counts as integrated only when its whole group integrates. Under C2, checkpoint C+1's child (the whole group, if it is a member) may not integrate until C is green.
- The rule checks only *direct* dependencies, so two shapes still deadlock:
  - **Transitive:** C's child depends on X, and X depends on C+1's child.
  - **Group:** C's child depends on member d of group G, and C+1 is named after another member of G. For example, G = {2, 6}, child 4 depends on 2, and the checkpoints come after 4 and after 6. Then 2 can't integrate without 6, 6 waits for C, and C waits for 2.
- Neither shape is ruled out by `scope`. Nothing stops the run, and §2 removes the child-order integration that used to prevent it.

**Fix:** state the rule over the closure. "Everything that must integrate before checkpoint C can run includes no later checkpoint's child. That is C's child, its transitive dependencies, and every member of a group among them." The epic review checks this, and so does the orchestrator whenever it moves or adds a checkpoint.

### P3-02 — major (design) — Members starting individually can fill the pool with unintegrated lanes and stall
**Location:** §2 bullet 2 ("Group members start individually as worktrees free up and still integrate once, together"); §3 C2 `lanes.md` → Starting lanes; `lanes.md` → The pool ("Never reuse … one whose child is not yet integrated"); `lanes.md` → Integrating (worktree: "a pool worktree that is clean and holds no unintegrated child").
**Problem:**
- A finished member keeps its pool worktree until its group integrates, and the group integrates only when every member has finished. Two cases follow:
  - A group with more members than the pool (or than `maxLanes`, if waiting lanes count toward it) can never integrate. This is the case P2-03 named; it now stalls after starting instead of never starting.
  - Two groups can each start some members by readiness and lowest number. For example, with a pool of 2, groups {1, 3} and {2, 4}: 1 and 2 start, finish, and hold both worktrees. Neither 3 nor 4 can start, and neither group can integrate.
- Integration then has no pool worktree to use either, unless the checkpoint worktree is free.
- Before the revision this couldn't happen: one group ran at a time.

**Fix:** add an admission rule in `lanes.md` → Starting lanes:
- A member of a group may start only if the free worktrees, after it takes one, cover the unstarted members of every group that has already started. Otherwise the lowest-numbered group already in progress has priority.
- `scope` → Parallel groups: a group has at most min(pool size − 1, `maxLanes`) members. The −1 leaves room for integration when the checkpoint worktree is busy.
- Say that finished but unintegrated lanes count as running, both for `maxLanes` and for the start rule's claim check.

### P3-03 — major (claims) — The new claim-widening and pause rule deadlocks inside a group and between paused children
**Location:** §3 C2 "Claims for every child", `lanes.md` → Claims bullet ("If no running child's claim covers the addition, the orchestrator widens … otherwise the child pauses until those children integrate").
**Problem:**
- **Sibling overlap:** a group member that needs a file in a *sibling's* claim pauses until that sibling integrates. The sibling integrates only with the group, which includes the paused member, so the group never integrates. The old fallback ("runs serially after the group") took the child out of the group. The new one doesn't.
- **Unstarted sibling:** widening checks only *running* children. It can therefore give a member a claim that overlaps an unstarted sibling's. That breaks `scope`'s no-overlap rule within a group, and the sibling can then never start: the start rule blocks it until the widened member integrates, which needs the sibling.
- **Mutual pause:** two children can each need a file in the other's claim. Both pause, and neither integrates.
- **Wording:** "covers" should be "overlaps". A partial overlap must also block widening.
- Each paused lane also holds a pool worktree, which adds to P3-02.

**Fix:**
- Widen only if the addition overlaps no unintegrated child's claim. That means running, finished or paused children, and every sibling in the group, whether started or not.
- If it overlaps a sibling: stop that member for a re-scope under Decisions. Either move the work to the sibling, or take the member out of the group so it integrates afterwards as a group of one.
- Pause only on children outside the group that are not themselves paused. A pause that would close a cycle stops the run for a re-scope.

**Verdict:** changes needed — 0 blocker, 3 major (P3-01–P3-03), 0 minor.

## author response to pass 3

Simplified rather than patched:
- P3-01: checkpoints no longer gate integration (or starts). Only "C+1's run waits until C is green and merged" and the red-checkpoint pause remain, so there is no gate to deadlock. The dependency-order placement rule is removed. P-g updated.
- P3-02: units (a group, or a child in no group) start together when a worktree is free for every member; groups have at most `maxLanes` members; a lane counts as running until integrated; ready units start in child-number order and a later unit doesn't start while an earlier ready unit waits, so nothing is starved or stranded.
- P3-03: widen a claim only if no unintegrated child that is unordered with it claims the files; otherwise the lane stops, the child leaves its group, gets a dependency on the overlapping child and restarts as a unit of one after it integrates. A new edge between unordered children can't form a cycle; nobody pauses on a sibling.
