# Review ledger: fast verification

## code pass 1

Scope: `c0afc71..ec10014` on `pilot/fast-verification`, against `plan.md` §3, §5, §8, §10 and §13. Canonical skills, agents and the frontier-pipeline plan edits were read in full. `dist/` has no render drift: `node tools/render-skills.mjs --check` passes. `tests/specs/skill-content-spec.sh` (40/40), `skill-render-spec.sh` (75/75) and `repo-structure-spec.sh` (85/85) pass.

Line count for the seven pipeline skills (scope, plan, implement, review, orchestrate, delegate, test-quality) is 459, up from 334 at `c0afc71`. Plan §10 gives 373 as the starting count, which this measurement doesn't reproduce. Orchestrate is 91 lines.

### FV-B1 · blocker · `skills/orchestrate/SKILL.md:38-49`, `skills/implement/SKILL.md:47`: the skills never say which worktree each writer uses
**Problem.** "One writer per worktree" (line 59) and "never reuse a dirty worktree" (line 48) are stated as rules, but no step says where a writer runs. The cases that break are:
- **Lane roles.** Nothing says that a lane's plan-author, implementer, reviewers and helpers run with their cwd in the lane's worktree. The default is the orchestrator's worktree, which holds the epic branch.
- **Culprit fix.** "Pause it and resume the culprit's implementer" (line 41; implement line 47 says "fix it on the branch tip") resumes a session whose cwd is one of two places, and both are unsafe:
  - In serial mode, it is the worktree where the paused child has uncommitted work. The result is two writers and a dirty tree.
  - In lane mode, it is a pool worktree that has probably been re-pointed to another child already, so the session ends up on the wrong branch, next to a live writer.
- **Integrator.** It is resumed in its old lane worktree. Nothing says the merge happens there, or that the worktree is free.
- **Bisect.** "A helper ... bisects" (line 39) doesn't say where. `git bisect` moves HEAD. If it runs in a worktree with a live child, it destroys that child's work.
- **Carried-over blocker.** The orchestrator would write it into a running child's `review.md`, which is a second writer in that worktree. The running implementer also wouldn't see the entry.

**Fix.** Add a short "Where" rule to orchestrate:
- every role for a lane launches with its cwd in the lane's worktree;
- triage and bisect run only in the checkpoint worktree;
- a culprit fix and an integration each run in a clean, idle worktree (a free pool worktree, or the checkpoint worktree once it is idle) checked out at the epic branch tip. Resume the session with that cwd, or, if resume can't change the cwd, use a fresh implementer given the culprit's plan and ledger;
- the paused child is interrupted. Before it continues on the new tip, it commits its own work-in-progress (WIP) or stashes it;
- the carried-over blocker reaches the running child by resuming its implementer with the finding, and the implementer writes it into the ledger. The orchestrator doesn't write it.

### FV-M1 · major · `skills/orchestrate/SKILL.md:29-30`: base-branch integration and baseline refresh dropped
**Problem.** The old close step merged the default branch into the work branch and reran the baseline. The diff replaced it with "Integrate the child into the epic branch", which creates several problems:
- **No step merges the base branch any more.** Line 30 still says "After integrating the base branch", but no step does that merge.
- **The baseline digest is never refreshed.** Checkpoint triage keys on "not in the baseline" (line 39). Without a refresh, a failure that comes in from the base branch looks like an epic regression, and gets bisected and routed to a child.
- **This contradicts the frontier plan.** The frontier plan's §6 Baseline row in this same diff ("after each base-branch integration") and its §4.5 step 3 both keep the refresh.
- **Serial children don't merge.** They commit straight onto the work branch, so "integrate the child" and "if the merge brought in other work" have no clear meaning for a serial child.

**Fix.** Make Close name each case:
- **Serial child:** it is already on the epic branch, so there is nothing to merge.
- **Lane child:** merge the lane branch.
- **Base branch:** merge it at child boundaries, as before.

Then decide what the post-merge run is, and write it down. One option is that a base-branch integration starts a checkpoint whose failures are first checked against the base side, and whose green digest becomes the new baseline. Either way, keep orchestrate and frontier §4.5 and §6 consistent.

### FV-M2 · major · `skills/orchestrate/SKILL.md:38`: the checkpoint bound and "green" are not defined well enough to run unattended
**Problem.** Three questions have no answer in the skill:
- **When does a failed checkpoint become green?** The options are when the fix's T1 and the failing tests pass, or after a full rerun of the gates. The bound depends on the answer.
- **May checkpoint C+1 start while C is running or red?** There is only one checkpoint worktree, and plan §3.3 allows at most one unverified checkpoint. The skill only blocks children from starting.
- **What does "past" mean with lanes?** Does it mean start or integrate? A parallel group can straddle a checkpoint in child order, and plan §8.2.4 says checkpoints apply to the integrated branch.

**Fix.** State the following:
- C is green when the full gates pass on C's commit, or on a later commit that contains the fix. A targeted rerun doesn't count.
- C+1's run waits for C to be green.
- "Past C+1" means integrating a child that comes after C+1 in child order. Lanes may still build.

### FV-M3 · major · `skills/orchestrate/SKILL.md:39-43`: failure routing doesn't cover every case
**Problem.** The routing has two branches: pause the running child, or carry the failure to it as a blocker. Several cases fit neither:
- **Epic close (T3).** There is no running child, so "add it to the running child's ledger" has no target.
- **Several running lanes.** "The running child" is singular. The skill doesn't say which lanes to pause, and which to carry the blocker to.
- **Integration culprits.** The culprit may be a lane merge, an integrator commit or a base-branch merge, and none of these has an implementer to resume.
- **No code review of the fix.** The culprit's fix gets no review, while the integrator's diff does.
- **No ledger named.** Nothing says which ledger the culprit's fix entry goes in.
- **The test-map update has no author.** "Add the path T1 missed to the test map" (line 43) edits a checked-in repo file, and the orchestrator must never commit code (Recovery).
- **No blocking rule.** Plan §3.3 says "that child cannot close until it is fixed". The skill doesn't say it.

**Fix.** Add the following rules:
- **Epic close:** the last child's implementer fixes it.
- **Lanes:** apply the routing per running lane.
- **Merge or integration culprit:** the integrator, or the child that merged last, fixes it.
- **Ledger:** the fix entry goes in the culprit's ledger as `## checkpoint fix`, and gets a code review.
- **Test map:** the implementer that fixes the regression adds the test-map entry.
- **Blocking:** a child with an open carried-over blocker can't close.

### FV-M4 · major · `skills/orchestrate/SKILL.md:34`, `skills/scope/SKILL.md:54-61`, `skills/plan/SKILL.md:20`: the single-plan path never runs the full gates
**Problem.** A single plan runs only step 2 and then goes to the PR. Before this diff, step 2 ended with a full green pass. Under the new implement skill it runs T1 only, and a single plan has no checkpoint and no epic close. The result is that a single plan reaches the PR without any full gate run, unless the plan escalates. This is a quality regression, and it contradicts plan §2, which allows one full run "only for the escalation".

The single plan's T1 also depends on things it has nowhere to put:
- The test map and smoke set are declared in `epic.md`. A single plan's Goal (plan line 20) and the scope's single-plan section carry "gates" only.
- So do the full-gate commands.

**Fix.**
- In orchestrate: "For a single plan: step 2, then the full gates once on the final tree (its T3), with failures routed to the same implementer, then the PR."
- In plan line 20 and scope line 55: the single plan's Gates also name the full-gate commands, the test map and the smoke set.

### FV-M5 · major · implement, plan, scope and orchestrate: no fallback when repo support is missing
**Problem.** The tiers assume the repo-side work in plan §4: a test map, a smoke set, a warm harness, a worktree pool with its own ports, and a checkpoint worktree. The pilot builds these in the prep plan, but the skills are generic, and today an unattended agent hits the gaps with no rule to follow:
- **No test map:** the T1 selection has no defined basis.
- **No smoke set:** the selection list is left with an undefined item.
- **No pool or checkpoint worktree:** the background checkpoint has nowhere to run. Running it in the live worktree would break one writer per worktree.
- **No warm harness:** the T0 rule "against a warm harness" can't be met.

**Fix.** Give each gap one line of fallback:
- **No test map:** the plan names the E2E specs for the touched paths by hand, as the old plan skill did, and the reviewer checks them.
- **No smoke set:** drop that item.
- **No pool:** run no lanes.
- **No checkpoint worktree:** run checkpoints on the critical path, between children.
- **No warm harness:** run T0 cold, single specs only.

Scope records which repo support exists under `epic.md` Gates.

### FV-M6 · major · `skills/plan/SKILL.md:25-30`, `skills/implement/SKILL.md:29`: unit selection safeguards and the T1 contents are missing
**Problem.** Plan §3.1 defines T1 as five parts:
1. full typecheck and build for the touched packages;
2. lint and format on changed files;
3. units selected with `--changed <base>`;
4. a whole-package rerun when config, setup or a shared module changes;
5. the E2E selection.

Only part 5 and the base-commit flag reached the skills. Part 4 is the guard against the selection's known blind spots (§12: dynamic imports, file-system fixtures), and it is missing.

Implement also says to run "the plan's ... selection". The test-map part has to be computed from the actual diff at T1 time, not taken from the plan, which can't know the final changed paths.

**Fix.**
- In plan's Gates (T1): list parts 1–4 alongside the E2E selection.
- In implement Gates step 1: derive the test-map specs from `git diff <base>` at T1 time, and rerun the whole package when config, setup or a shared module changed.

### FV-M7 · major · `skills/implement/SKILL.md:21, 35, 70`: warm-harness staleness and the process-kill rule
**Problem.**
- **Stale servers.** Plan §4.2 says "Never reuse a server across commits without a rebuild check, since stale code passes tests". This rule is not in the skills. Implement only says "Keep built artifacts and services warm". The pool deliberately keeps the dev backend across children (orchestrate line 48), which makes stale-code passes more likely.
- **Who may stop what.** "Kill processes you didn't start" and "touching only processes you started" conflict with how processes now get started:
  - pool-kept servers were started by an earlier child or by the pool setup;
  - T1 servers are started by the helper.

  So an implementer can neither restart a stale warm server nor clean up after its helper. Plan §8.3 scopes the rule by port instead: "a lane never kills processes outside its own ports".

**Fix.**
- In implement T0: "Before trusting a warm server, check that it was built from the current source. Rebuild or restart it if not."
- Replace the two process rules with: "Only touch processes bound to your worktree's ports; never others."
- Have helpers stop the servers they start, or leave them to the lane, stated explicitly.

### FV-M8 · major · `skills/orchestrate/SKILL.md:47`: the resource gate can't be enforced
**Problem.**
- **No one receives the budget.** The orchestrator "checks" the machine-wide E2E worker budget, but nothing passes a lane its share of workers. Implement and its helpers run E2E with the repo's default worker count, so 4 lanes plus the checkpoint run oversubscribe the machine. That produces resource flakes, which then get triaged as regressions.
- **Missing details.** The default budget (cores ÷ 4), sharing it with the checkpoint run, the disk check before a checkpoint run, and the repo's disk floor (plan §8.2, §8.3) are all missing.

**Fix.**
- In orchestrate: give each lane and each checkpoint run its E2E worker count in the task (default cores ÷ 4 machine-wide, shared with the checkpoint), and check disk against the repo floor before lanes and before checkpoint runs.
- In implement: "Run E2E with the worker count the task gives you."

### FV-M9 · major · implement line 35 and orchestrate line 39: flake policy (plan §3.4) is missing
**Problem.**
- **"Known flake" is undefined.** Checkpoint triage excludes it, but nothing defines it.
- **Missing quarantine rules.** These are not in the skills:
  - the non-gating quarantine list in `epic.md`, with an owner and an expiry;
  - "a flake seen twice becomes a tracker item";
  - "gates run with retries off; a retry is allowed only in checkpoint triage".

  Without retries off, a repo's configured retries hide flakes from every tier.
- **No outcome for the rerun.** Triage also doesn't say what happens when the isolated rerun passes: record it as a flake and stop, without a bisect.

**Fix.**
- Add a Quarantine entry to scope's `epic.md` sections.
- In orchestrate triage: a failure that passes alone is recorded as a flake, and a second sighting gets a tracker item and goes on the quarantine list, if the epic pre-authorizes filing.
- In implement Gates: run the gates with retries off.
- Frontier §6's flake paragraph needs the same update.

### FV-M10 · major · `skills/scope/SKILL.md:35`, `skills/plan/SKILL.md:31, 41`, `skills/review/SKILL.md` (plan mode): claims have no single source of truth
**Problem.**
- **Scope.** It requires that group members' "claims don't overlap", but `epic.md` has no field that records claims.
- **Plan.** It asks the plan-author to write Claims, then to report "if the design needs to break the child's claims". That presumes the claims were set earlier, by someone else.
- **Review.** The plan reviewer checks claims against siblings' claims. Siblings in the same group are planned concurrently, so their plans may not exist yet.
- **Missing exceptions.** Two of plan §8.1's group rules are missing:
  - the merge-friendly-files exception;
  - "none ... changes the schema in a way a sibling reads".

  Without the first, every pair that touches a changelog or doc index gets serialized.

**Fix.**
- Scope's Parallel groups records each member's claims and the merge-friendly files, and the schema-read exclusion.
- The plan restates and refines its own claims.
- Plan review checks them against the sibling claims in `epic.md`.
- Breaking a claim means going outside the `epic.md` claim.

### FV-M11 · major · `skills/orchestrate/SKILL.md:49`: the integrator is under-specified
**Problem.** Against plan §8.2.3, "resume one implementer as integrator" leaves these open:
- **Which session.** Is it the child being merged now, or the one already on the epic branch?
- **T1 for both children.** Plan §8.2.3 requires it, and the skill doesn't say so.
- **Records.** Which ledger gets the "what it changed" entry is not named.
- **Review.** "Code mode" reviews one child's diff against one `plan.md` from a given base commit. The integration diff has two plans, and its base commit is not named.
- **Loop cap.** Nothing says whether the integration review loop has the pass-4 cap.

The integrator's worktree is covered in FV-B1.

**Fix.** Specify each point:
- **Session:** the implementer of the child being merged.
- **Gates:** T1 for both children on the merged tree.
- **Ledger:** an `## integration` entry in that child's ledger.
- **Review:** reviewed in code mode against both plans, from the epic-branch commit before the merge.
- **Loop cap:** the normal pass cap.

### FV-m1 · minor · `skills/orchestrate/SKILL.md:52-55`, frontier `plan.md` §4.6 and §6: epic-close order differs from plan §3.1
**Problem.**
- **Order.** Plan §3.1 T3 is "every gate in full on the final tree; then the epic-diff review". The skill and frontier §6 run the review first, then the fixes, then the full gates. The skill's order is better, because the full gates then see the post-fix tree, but plan §3.1 still says the opposite.
- **Stale text.** Frontier §4.6 step 2 still says the implementer "re-runs the full gates once".
- **"The last child".** With lanes, this is ambiguous: last in child order, or last to close?

**Fix.**
- Amend plan §3.1's T3 row and frontier §4.6.
- Say "the last child in child order".

### FV-m2 · minor · `skills/orchestrate/SKILL.md:37`, `skills/scope/SKILL.md:40-45`: checkpoint placement is narrower than the plan
**Problem.**
- **Adjustment.** Plan §3.3 lets the orchestrator adjust placement in any way, with a recorded decision. The skill only allows adding a checkpoint after a widened child.
- **Placement list.** Scope's parenthetical list omits migrations, seed data, visibility and build config, which the plan skill's widen list includes.

**Fix.**
- In orchestrate: "You may move, add or drop a checkpoint, except epic close; record it under Decisions."
- In scope: "after children that widen T1 (see `plan`)".

### FV-m3 · minor · `skills/test-quality/SKILL.md:26, 35-41`: test-quality departs from the guidelines in §5
**Problem.** The skill differs from §5 in four places:
- **Keep list qualifier.** It drops the plan's "independent" qualifier. Without it, the list says to keep a duplicate API or security test, which contradicts the skill's own Duplicate rule.
- **Keep list additions.** It adds "SDK", "platform" and "prompt-byte" contracts, which are not in §5. "Prompt-byte" means nothing to a reader outside this repo.
- **Ban severity.** The Banned paragraph doesn't state the plan's explicit severity: code review flags it as major. It is only implied through "Tautological".
- **Negative controls.** The skill makes them minor. §5 gives minor only to "naming or fixture issues". A negative control that doesn't fail at its intended guard is false proof of an authorization or visibility rule, which is closer to tautological.

**Fix.**
- Keep list: "Keep *independent* API, protocol, ... contracts". Drop the additions, or confirm them with the owner.
- Add "(major)" to Banned.
- Move negative controls to major, or confirm with the owner.

### FV-m4 · minor · length (459 lines; orchestrate 91 against the target of about 80)
**Problem.** The fixes above add lines. These cuts lose no rule:
- **Audit section.** test-quality's "Auditing existing tests" is 10 lines. The plan-author, implementer and reviewer load it every session, but only audit campaigns use it. Move it to `skills/test-quality/references/audit.md`, as `skills/AGENTS.md` prefers.
- **Widen classes.** Scope's checkpoint parenthetical repeats the plan skill's widen classes. Reference them instead (FV-m2).
- **Escalation clause.** Implement says "unless the plan escalates this child" twice (Gates step 3 and Don't). Keep it once.

**Fix.** Apply these cuts. Put the new orchestrate text (FV-B1, M2, M3, M11) in terse bullets.

**Counts:** 1 blocker, 11 major, 4 minor. **Verdict:** changes needed.

### Author responses (pass 1)
- **FV-B1 fixed.**
  - orchestrate "Where work runs": one writer per worktree; serial children in the work-branch worktree; checkpoint runs, triage and bisect only in the checkpoint worktree; interrupt the running child and have it commit before anyone else writes there.
  - `references/lanes.md`: lane roles launch with their cwd in the lane worktree; integration and lane-mode culprit fixes name their worktree.
  - Carried-over blockers reach the running implementer by resume, and it writes them into its own ledger.
- **FV-M1 fixed.**
  - Close names each case: a serial child is already on the work branch; a lane child merges per `lanes.md`.
  - The base branch merges at each checkpoint, in the idle work-branch worktree, before the full run.
  - Failures that also fail on the base tip join the baseline.
  - Frontier §4.5 and the §6 Baseline row are updated to match.
- **FV-M2 fixed.** Green means the full gates passed on C or on a later commit containing the fix. C+1's run waits for C. "Past C+1" means starting (serial) or integrating (lane) a child after C+1 in child order.
- **FV-M3 fixed.** `references/checkpoint-failures.md` covers routing for each running child, merge culprits, epic close, the `## checkpoint fix` ledger entry with its fresh review, the test-map update by the fixer, and the recheck. Close blocks while a carried-over blocker is open.
- **FV-M4 fixed.**
  - Orchestrate's single-plan path runs the full gates once after code review, before the PR.
  - In plan Goal and scope's Single plan, the gates include the full-gate commands, the test map and the smoke set.
  - Plan §3.1's T3 row is updated.
- **FV-M5 fixed.** Scope's Gates record which repo support exists, and the disk floor. The fallbacks:
  - no test map: the plan names the specs;
  - no warm harness: T0 runs cold;
  - no checkpoint worktree: checkpoints run between children;
  - no pool: no lanes.
- **FV-M6 fixed.** Plan's Gates (T1) lists typecheck and build, changed-file lint, unit selection with the whole-package rule, and E2E. Implement computes the selection from `git diff <base>` and applies the whole-package rule.
- **FV-M7 fixed.** Implement T0 adds the stale-server check. The process rule is now scoped to the worktree's ports, and helpers stop the servers they start unless told otherwise.
- **FV-M8 fixed.** Scope sets the E2E worker budget (default cores ÷ 4). The orchestrator passes each implementer and each checkpoint run its worker count, and checks disk before checkpoint runs and lanes (`lanes.md`). Implement runs E2E with the given count.
- **FV-M9 fixed.** Scope adds a Quarantine section. Triage records flakes, and a second sighting goes to Quarantine with an expiry, plus a tracker item if pre-authorized. Implement runs gates with retries off. The frontier §6 flake paragraph is updated.
- **FV-M10 fixed.** Scope's parallel groups give each member a claim, name the merge-friendly files, and exclude schema a sibling reads. The plan restates and refines its `epic.md` claim; review checks against `epic.md`; going outside the claim stops the lane.
- **FV-M11 fixed** in `lanes.md`:
  - the integrator is the implementer of the child being merged, in its lane worktree;
  - it merges the work branch into the lane branch, runs T1 for both children, and writes `## integration` in its own ledger;
  - a fresh code review covers both plans, from the work-branch commit before the merge, with the normal cap.
- **FV-m1 fixed.** Plan §3.1's T3 row and frontier §4.6 now say: review, fixes, then the full gates. "The last child" now reads "the last child in child order".
- **FV-m2 fixed.** Orchestrate may move, add or drop checkpoints except epic close. Scope refers to `plan`'s widen list.
- **FV-m3 partly fixed:**
  - the "independent" qualifier is restored;
  - Banned is marked (major);
  - a false negative control is now major.

  **Rejected:** dropping SDK, platform and prompt-byte. They come from the owner's own retention list, given in the session that commissioned this plan. "Prompt-byte" is reworded as "exact-prompt-text" for clarity.
- **FV-m4 fixed.**
  - The audit method moves to `test-quality/references/audit.md`.
  - Checkpoint failure handling moves to `orchestrate/references/checkpoint-failures.md`, and lanes to `orchestrate/references/lanes.md`.
  - The escalation clause appears once.
  - Line counts after the fixes: orchestrate 96, scope 77, implement 75, plan 64, review 60, test-quality 53, delegate 47. That is 472 in total, plus 2 reference files of about 60 lines read only when needed.

## code pass 2

Scope: `c0afc71..a07dfcb`, with pass 1's findings checked against the fix commit `a07dfcb`. Read in full: the seven pipeline skills, `orchestrate/references/{lanes,checkpoint-failures}.md`, `test-quality/references/audit.md`, the three agent files, and the frontier `plan.md`/`evaluation.md` edits. `node tools/render-skills.mjs --check` reports no drift. `skill-content-spec` (40/40), `skill-render-spec` (75/75) and `repo-structure-spec` (85/85) pass. Seven-skill total is 472 lines (orchestrate 96), plus 73 lines of on-demand references, within plan §10's revised "about 500".

### Pass-1 findings
- **FV-B1 fixed.** Orchestrate "Where work runs" (lines 20-25) puts serial children in the work-branch worktree and checkpoint runs, triage and bisect in the checkpoint worktree. `lanes.md:6` sets every lane role's cwd to the lane worktree. `lanes.md:19, 26` keep an un-integrated lane worktree for its integrator. `lanes.md:38-39` names the culprit-fix worktree, with a fresh-implementer fallback. Carried-over blockers are written by the receiving implementer (`checkpoint-failures.md:16`, `implement:53`). The serial-mode choice to commit the paused child's work in progress causes a new problem, FV-M12.
- **FV-M1 fixed.** Close names the serial and lane cases (orchestrate 36). The base branch merges at each checkpoint before the full run (49). Base-side failures join the baseline (`checkpoint-failures.md:7`). Frontier §4.5 and the §6 Baseline row match. The §2 diagram is stale; see FV-m6.
- **FV-M2 fixed.** Orchestrate 52-54 defines green, the C+1 wait, and "past" for serial and lane children.
- **FV-M3 fixed.** `checkpoint-failures.md` routes per running child, merge culprits and epic close. It names `## checkpoint fix` in the culprit's ledger, a fresh review, the fixer's test-map update, and the recheck. Orchestrate 34 blocks close while a carried-over blocker is open.
- **FV-M4 fixed.** Orchestrate 41-44 adds the single-plan full run. Plan 20-23 and scope 62 carry the full-gate commands, test map and smoke set.
- **FV-M5 fixed.** Scope 43-45 records which repo support exists. The fallbacks are in plan 32 (no test map), implement 18 (cold harness), orchestrate 24 (no checkpoint worktree) and `lanes.md:3` (no pool). Having no smoke set needs no rule.
- **FV-M6 fixed.** Plan 28-32 and implement 30-32 cover this.
- **FV-M7 fixed.** Implement 21 adds the stale-server check. Implement 40 scopes processes by port and has helpers stop the servers they start.
- **FV-M8 fixed.** Scope 38 sets the budget. Orchestrate 31 and 50 and `lanes.md:9-10` pass the worker count and check disk. Implement 33 uses the given count.
- **FV-M9 fixed.** Scope 57 adds Quarantine. `checkpoint-failures.md:6` covers flakes, implement 33 turns retries off, and frontier §6 matches.
- **FV-M10 fixed.** Claims are recorded in scope 36-37. Plan 35 and 45, review 23 and `lanes.md:33-35` follow them.
- **FV-M11 fixed.** `lanes.md:22-31` covers this.
- **FV-m1 fixed.** Plan §3.1's T3 row and frontier §4.6 are updated, and orchestrate 59 says "in child order".
- **FV-m2 fixed.** Orchestrate 47 and scope 49 are updated.
- **FV-m3 fixed in part; the rejection is accepted.** test-quality restores "independent" (line 41), marks Banned as major (26) and makes a false negative control major (34). The SDK, platform and exact-prompt-text items come from the owner, which is a good reason.
- **FV-m4 fixed.** Audit, checkpoint failures and lanes moved to references, and the escalation clause appears once.

### FV-M12 · major · `skills/orchestrate/SKILL.md:25`, `references/checkpoint-failures.md:15, 22`: in serial mode, the running child's work in progress enters the culprit fix, the recheck and the bisect range
**Problem.** This was caused by the FV-B1 fix. In serial mode, the culprit's implementer works in the work-branch worktree, which is also the running child's worktree. Line 25 makes the running child commit its work in progress first, and that commit lands on the work branch. Every later step then sees half-built work:
- **The fixer's T1.** "T1 plus the failing tests" runs on a tree with half-built code from another child, so typecheck, build or the smoke set can fail for reasons that aren't the fixer's.
- **The recheck.** "Rerun the checkpoint on the fixed commit" runs the full gates on a commit that contains the work in progress. Under orchestrate 52, a commit that contains the fix counts as green, so C's green status now depends on an unfinished child.
- **Triage of a red recheck.** Triage bisects into the work-in-progress commit and routes the failure to the running child. C stays red until that child finishes, and the C+1 run is blocked meanwhile (line 53).

This applies to both routes in serial mode, because the culprit always fixes.

**Fix.** Keep the running child's work off the fix path. One option:
- In serial mode, the culprit fix runs in the checkpoint worktree, which is idle after triage, on a fix branch from C's commit. Use the resumed culprit implementer if resume can take that cwd; otherwise a fresh implementer with its plan and ledger, as in `lanes.md:39`.
- The fixer's T1 and the recheck run on the fix commit.
- The orchestrator then merges the fix branch into the work branch, interrupting the running child only for that merge.
- Say that "green" covers the fix commit on that branch.

If the work-in-progress path is kept instead, the paused child must stash rather than commit, so that the branch tip stays clean.

### FV-m5 · minor · `skills/orchestrate/SKILL.md:49`, `references/lanes.md:24-31, 38`, `references/checkpoint-failures.md:15`: lane-mode details created by the fixes
**Problem.** Four lane-mode cases are underspecified:
- **Base-merge conflicts.** At a checkpoint, these go to "the implementer of the child that just closed". For a lane child, that session's cwd is its lane worktree, but the conflicted merge sits in the work-branch worktree.
- **A conflicted lane merge.** It is left half-done in the work-branch worktree. Nothing says to abort it before the integrator works on the lane branch and the orchestrator merges again.
- **A culprit fix in an idle, un-re-pointed lane worktree** (`lanes.md:38`). That worktree is still on the culprit's old lane branch. Nothing says to switch it to a fix branch from the work-branch tip.
- **A paused lane that builds on the broken code.** Nothing says that it merges the work branch once the fix is integrated. Without that merge, it resumes on the broken base.

**Fix.** Add one line for each case:
- **Base merge:** abort the conflicted base merge, and have the implementer resolve it in a free worktree on a branch from the work-branch tip, then merge that branch.
- **Lane merge:** abort a conflicted lane merge before handing off to the integrator.
- **Culprit fix:** in either worktree, the fix branch starts at the work-branch tip.
- **Paused lane:** it merges the work branch after the fix lands, then continues.

### FV-m6 · minor · `plans/2026_10_10_frontier_pipeline/plan.md:55` and related lines: stale gate model
**Problem.** The FV-M1 fix moved the base-branch merge to checkpoints, but the §2 flow diagram's CLOSE line still says "integrate base branch". The same sweep would also catch three other lines that still describe the old model:
- **Line 38:** "the full gates once at the end";
- **Line 167:** "children run in sequence ... parallelism is deliberately narrow", which lanes now contradict;
- **Line 385:** "the end-of-implementation full gate ... catch[es] them".

**Fix.**
- **Line 55:** "integrate (base branch at checkpoints)".
- **Lines 38, 167 and 385:** point each one to fast verification §3 or §8, or reword it.

**Counts (pass 2, open):** 0 blocker, 1 major, 2 minor. **Verdict:** changes needed.

### Author responses (pass 2)
- **FV-M12 fixed, by simplifying the design.** pi-subagents resumes keep their stored worktree ("Retained resumes keep their stored contracts"), so a resumed culprit can't move. Instead, all checkpoint work happens on a **checkpoint branch** in the checkpoint worktree:
  - the base merge, with conflicts aborted and resolved there by a fresh implementer;
  - gate runs, triage, the bisect, and the fix, by a fresh implementer given the culprit's plan and ledger;
  - the fix's fresh review, and the recheck.

  "Green" means the full gates passed on the checkpoint branch's tip, which then merges into the work branch. Running children never see half-fixed state, and the culprit fix never sees their work in progress.
  - Carried-over blockers and "fix forward" are gone, since nothing needs them now.
  - A running child that builds on the broken code pauses until the merge.
  - Orchestrate's "Where work runs" adds two rules: interrupt-commit-merge-resume when merging into a serial child's worktree, and "resumed sessions keep their worktree".
  - Plan §3.3 is rewritten to match.
- **FV-m5 fixed.**
  - Base-merge conflicts are covered above.
  - `lanes.md` integration aborts a conflicted merge, or resets after a red T1, before handing to the integrator.
  - Culprit fixes never run in lane worktrees.
  - A paused lane merges the work branch after the checkpoint branch has merged.
- **FV-m6 fixed.** In the frontier plan, principle 6, the §3 diagram's CLOSE line, the §10 parallelism paragraph and the §13 "fewer gates" risk row now point to fast verification.

## code pass 3

Scope: `c0afc71..7bddf77`, with the pass-2 findings checked against the fix commit `7bddf77`. Read in full: orchestrate, `references/{checkpoint-failures,lanes}.md`, implement, plan §3.3, and the frontier `plan.md` edits. A grep for the old routing terms ("carried", "fix forward", "culprit") found leftover text only in the frontier plan (FV-m7). `node tools/render-skills.mjs --check` reports no drift. `skill-content-spec` (40/40) and `skill-render-spec` (75/75) pass. The seven skills total 477 lines; orchestrate is 98.

### Pass-2 findings
- **FV-M12 fixed.** Base merge, gate runs, triage, bisect, fix, review and recheck all happen on the checkpoint branch in the checkpoint worktree (orchestrate 24, 50-54; `checkpoint-failures.md:3, 9-14`). That branch starts from C's work-branch commit, so the fixer's T1, the recheck and the bisect range can't contain a running child's work in progress. The only remaining WIP commit is the one orchestrate 25 needs to merge the green branch back. That merge-back has its own gap, FV-M13.
- **FV-m5 fixed.**
  - Base-merge conflicts are aborted and resolved in the checkpoint worktree (orchestrate 51).
  - A conflicted lane merge is aborted, and a red T1 is reset (`lanes.md:26`).
  - Culprit fixes never run in a lane worktree (`lanes.md:38`).
  - A paused lane merges the work branch before it continues (`lanes.md:39`, `checkpoint-failures.md:16-18`).
- **FV-m6 fixed** for the four lines named: frontier 38, 55, 167 and 385 now match. The redesign left two other frontier lines stale; see FV-m7.

**Consistency of the redesign.** Orchestrate, `checkpoint-failures.md`, `lanes.md`, implement 52-56 and plan §3.3 agree on the following:
- the checkpoint branch and worktree;
- a fresh implementer for the fix, since a resumed session can't move;
- the fix's T1, test-map entry, `## checkpoint fix` ledger entry and fresh review;
- "green" meaning a full-gate pass on the branch tip, then a merge into the work branch;
- children that build on the broken code pause until that merge.

Two gaps remain: who resolves a conflicted merge-back (FV-M13), and where epic-close fixes land in lane mode (FV-M14, which the new "resumed sessions keep their worktree" rule makes explicit).

### FV-M13 · major · `skills/orchestrate/SKILL.md:25, 54`, `references/checkpoint-failures.md:14`: no owner for a conflicted merge of the checkpoint branch into the work branch
**Problem.** This was caused by the pass-2 fix. The checkpoint branch now carries the base-branch merge and any regression fix, both based on C. Meanwhile the work branch has moved on: in serial mode, the next child commits there, and in lane mode, other lanes integrate. So merging the green checkpoint branch back can conflict. Before pass 2, the base branch merged straight into an idle work branch, and the implementer that had just closed resolved any conflict. Now nothing says who resolves a conflict at this merge, and the cases break as follows:
- **Serial mode.** Line 25 interrupts the running child, commits its work in progress, and merges inside its worktree. A conflict leaves a half-done merge in a live child's worktree. The orchestrator may not resolve it ("Never commit code yourself", line 74). The child is resumed onto a conflicted tree, or the run stalls.
- **Lane mode.** The merge runs in the idle work-branch worktree, but the same question applies: who resolves it?
- **Verification.** Nothing says whether a resolved merge needs T1 before the work branch carries it.

**Fix.** Add one rule to orchestrate Checkpoints step 2, for example:
- **When to merge:** merge only into a clean tree, meaning the idle work-branch worktree or a serial child stopped at a reply. This also drops line 25's mid-work interrupt and WIP commit.
- **On a conflict:** abort the merge. A serial child's implementer, which is already in that worktree, merges and resolves. In lane mode, a fresh implementer in the checkpoint worktree merges the work branch into the checkpoint branch and resolves there, after which the orchestrator merges again.
- **After resolving:** run T1 for the conflicted paths, and record the resolution in the ledger of the child whose files conflicted.

### FV-M14 · major · `skills/orchestrate/SKILL.md:61-62`, frontier `plan.md:153`: in lane mode, epic-close fixes land on a lane branch that the final checkpoint never sees
**Problem.** Epic close step 2 resumes "the implementer of the last child in child order". Line 26 now states that resumed sessions keep their original worktree. If that child ran in a lane, its session is in its lane worktree, on its lane branch. Its fixes for the epic-diff findings are committed there.

Step 3 then runs the final checkpoint, and Checkpoints step 1 creates the checkpoint branch "from the work-branch commit". Nothing merges the lane branch first. So the epic-diff fixes are missing from the gated tree and from the PR. Also, the fixes are made on a lane base that lacks later checkpoint merges.

**Fix.** In Epic close step 2, add one of these:
- "If the last child ran in a lane, its fixes integrate as `references/lanes.md` Integrating says before step 3."
- Or: "A lane child's fixes are made by a fresh implementer in the idle work-branch worktree, given that child's plan and ledger."

Mirror the change in frontier §4.6 step 2.

### FV-m7 · minor · frontier `plan.md:143, 218`, `skills/orchestrate/SKILL.md:66`, fast-verification `plan.md` §3.3 "Running a checkpoint" step 1: text the redesign left stale
**Problem.** Four places still describe the old design:
- **Frontier line 143** still says base-merge conflicts "go to the implementer that just finished". They now go to a fresh implementer in the checkpoint worktree.
- **Frontier line 218** (T2 row) still says failures are "fixed in that child or carried forward as a blocker". That is the routing pass 2 removed.
- **Orchestrate line 66** says "Every planner or implementer call resumes that child's session". This conflicts with line 26, and with the fresh implementers for base-merge conflicts and checkpoint fixes.
- **Plan §3.3 step 1** says the orchestrator "points the checkpoint worktree at that commit". It doesn't mention the checkpoint branch or the base merge that orchestrate 50 now places there.

**Fix.**
- **Line 143:** "conflicts are resolved on the checkpoint branch (`orchestrate`)".
- **Line 218:** "fixed on the checkpoint branch by a fresh implementer, then merged when green".
- **Line 66:** add "except checkpoint work, which uses fresh sessions".
- **§3.3 step 1:** "creates the checkpoint branch at that commit in the checkpoint worktree and merges the base branch into it".

### FV-m8 · minor · `references/checkpoint-failures.md:10, 16`: pausing a dependent child, and merge-commit culprits
**Problem.** Two cases are underspecified:
- **Pausing at the next reply doesn't pause anything.** An implementer replies only at handoff, so a dependent child that is building keeps going on the broken code. Its own T1 may then hit the regression. Implement 38 tells it to fix "anything else", so it may fix the regression in its own tree. That duplicates the checkpoint fix, and the two fixes conflict at merge-back (FV-M13).
- **A base-merge culprit has no children.** If the bisect lands on the checkpoint's own base-merge commit (a semantic clash between base and epic), "the merged children's plans and ledgers" names nothing. The `## checkpoint fix` entry then has no ledger to go in.

**Fix.**
- **Line 16:** "steer it now with the failure digest: don't fix this failure, it is being fixed on the checkpoint branch; then pause it at its next reply".
- **Line 10:** "for the base-merge commit: the last child's plan and ledger, as for a base-merge conflict".

**Counts (pass 3, open):** 0 blocker, 2 major (FV-M13, FV-M14), 2 minor (FV-m7, FV-m8). **Verdict:** changes needed.

### Author responses (pass 3)
- **FV-M13 fixed.**
  - Orchestrate "Where work runs": merges into the work branch happen only at a clean point, meaning between serial children, while a stopped child is waiting, or at any time in lane mode. The mid-work interrupt-and-commit-WIP rule is removed.
  - Close merges any waiting green checkpoint branch.
  - Checkpoints step 2 handles a conflict: abort, then a fresh implementer in the checkpoint worktree merges the work branch into the checkpoint branch and resolves there, runs T1 for the conflicted paths, and records `## checkpoint merge` in the last child's ledger; then merge again.
  - The C+1 bound is now "green and merged". Plan §3.3 is updated to match.
- **FV-M14 fixed.** Epic close step 2 runs the fixes in the work-branch worktree: the resumed last child if it ran serially, or a fresh implementer given that child's plan and ledger if it ran in a lane. Frontier §4.6 is updated to match.
- **FV-m7 fixed.** Frontier §4.5 (base-merge conflicts) and the T2 row are updated. The orchestrate Bounds resume rule adds "except where this skill names a fresh one". Plan §3.3 "Running a checkpoint" now names the checkpoint branch and the base merge.
- **FV-m8 fixed.**
  - A dependent child is steered at once with the failure digest: don't fix it, commit, stop and reply. Implement treats a failure that is being fixed on a checkpoint branch as not its own, and honors a stop.
  - A culprit that is the checkpoint's own base-merge commit uses the last child's plan and ledger.
