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
