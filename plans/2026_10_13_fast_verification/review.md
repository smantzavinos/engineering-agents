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

## code pass 4

Scope: `c0afc71..a0950b1`, with the pass-3 findings checked against the fix commit `a0950b1`. Read in full: orchestrate, `references/{checkpoint-failures,lanes}.md`, implement, fast-verification plan §3.3, and the frontier §4.5, §4.6 and §6 edits. A grep for the old routing terms ("next reply", "carried", "fix forward", "commit its work in progress") finds only the plan's own revision note. `node tools/render-skills.mjs --check` reports no drift. `skill-content-spec` (40/40) and `skill-render-spec` (75/75) pass. The seven skills total 487 lines; orchestrate is 108.

### Pass-3 findings
- **FV-M13 fixed.** Orchestrate 25 allows merges into the work branch only at a clean point, and the mid-work WIP commit is gone. Close (37) merges a waiting green branch. Checkpoints step 2 (56-60) names the conflict owner (a fresh implementer in the checkpoint worktree, merging the work branch into the checkpoint branch), T1 for the conflicted paths, and the `## checkpoint merge` ledger entry. The bound is "green and merged" (61-62, plan §3.3). Close merges before it starts the next checkpoint, so C+1's branch contains C. No deadlock: a steered child is a clean point, and lane mode merges at any time. Two problems follow from the clean-point rule: FV-M15 and FV-m9.
- **FV-M14 fixed.** Epic close step 2 (67-71) runs the fixes in the work-branch worktree: the resumed last child if it ran serially, or a fresh implementer given that child's plan and ledger if it ran in a lane. Step 3's checkpoint branch is cut from that worktree's commit, so the fixes are gated and reach the PR. Frontier §4.6 step 2 matches.
- **FV-m7 fixed.** Frontier 143 and 218, orchestrate 76 ("except where this skill names a fresh one") and plan §3.3 "Running a checkpoint" step 1 now describe the checkpoint branch.
- **FV-m8 fixed.** `checkpoint-failures.md:17` steers the dependent child at once with the digest and "don't fix; commit, stop, reply", and implement 38 honors both. `checkpoint-failures.md:11` routes a culprit that is the base-merge commit to the last child's plan and ledger.

### FV-M15 · major · `skills/orchestrate/SKILL.md:25`, `references/checkpoint-failures.md:17-21`, `references/lanes.md:39`: a merge into an unfinished child breaks its base commit for T1 and review
**Problem.** This was caused by the pass-2 and pass-3 fixes. A green checkpoint branch can now merge into a child that hasn't closed:
- **Serial mode:** the clean-point rule allows "while a stopped child is waiting". The steered dependent child is meant to get the fix this way. A child between implementer passes, waiting for its code review, also fits the wording.
- **Lane mode:** a paused lane merges the work branch into its lane branch.

The merge brings in the base-branch delta, the checkpoint fix and, in lane mode, other lanes' work. The child keeps its original base commit (orchestrate 15, 32-33). Two things use that base:
- **T1 selection.** It comes from `git diff <base>` (implement 30). Changed-file lint, `--changed <base>` units and test-map specs now cover all the upstream paths. Implement 38's "anything else you fix" then aims the child at upstream code.
- **The code review.** It covers "the child's diff from the base commit" (review 24). The reviewer judges upstream changes against this child's plan, and the claim check (FV-M10) flags upstream files as out of claim.

Pass 1's design avoided this, because the base branch merged only into an idle work branch, followed by "record the new base commit".

**Fix.**
- **Serial mode:** in orchestrate 25, narrow "while a stopped child is waiting" to "while a child stopped by `checkpoint-failures.md` step 4 is waiting". Say that a child in its review loop is not a clean point.
- **After any merge into an unfinished child (serial or lane):** the orchestrator records a new base for that child: the old base commit with the same incoming commit merged in, built off-tree with `git merge-tree --write-tree` and `git commit-tree`, or in the checkpoint worktree. Pass that base to the resumed implementer and to later reviewers.
- **Lane mode:** add the same rule to `lanes.md:39`.

### FV-m9 · minor · `skills/orchestrate/SKILL.md:56-60`: the resolved merge-back is neither re-gated nor reviewed
**Problem.** This was caused by the FV-M13 fix. After a conflicted merge-back, the checkpoint branch's tip is the resolved merge, which only had T1 on the conflicted paths. Line 54 defines green as "the full gates passed on the tip", so it's unclear whether step 4 ("merge again") needs a recheck. A lane integration conflict also gets a fresh review (`lanes.md:30`); this resolution gets none.

**Fix.** Add to step 3: "The resolved tip counts as green without a full rerun; the next checkpoint covers it. A fresh reviewer reviews the resolution (code mode, from the checkpoint branch's tip before the merge), with the normal pass cap." Or state that no review is needed, and say why.

**Counts (pass 4, open):** 0 blocker, 1 major (FV-M15), 1 minor (FV-m9). **Verdict:** changes needed. This is pass 4, so under orchestrate's Bounds the loop stops here for the human (or the oracle) to decide on FV-M15.

### Author responses (pass 4)
The pass cap has been reached. These fixes follow the reviewer's suggested fixes; the owner decides whether they need another pass.
- **FV-M15 fixed.**
  - The clean point is narrowed to "a child stopped by the checkpoint-failures steer", so a child waiting for review no longer qualifies.
  - A new orchestrate rule, "Merging into an unfinished child", covers a stopped serial child and a paused lane. A helper builds the child's new base (its old base with the same incoming commit merged in, detached, in the checkpoint worktree), and the orchestrator records it. T1 and code review then see only the child's own changes.
- **FV-m9 fixed.** A conflicted merge-back resolution gets a fresh code review, from the checkpoint branch's pre-merge tip. The resolved tip counts as green after T1 on the conflicted paths, and the next checkpoint's full run covers the rest. This trade is stated in the skill.

## code pass 5

Scope: `c0afc71..b1eb735`. The owner authorized this pass beyond the cap. The pass-4 findings were checked against the fix commit `b1eb735`, which changes only orchestrate lines 25-26 and 61-62. Re-read in full: orchestrate, `references/{lanes,checkpoint-failures}.md`, implement and review. `node tools/render-skills.mjs --check` reports no drift. `skill-content-spec` (40/40) and `skill-render-spec` (75/75) pass. I checked the merge-base arithmetic in a scratch repo (below).

### Pass-4 findings
- **FV-M15: fixed for a clean merge.**
  - Orchestrate 25 narrows the serial clean point to "a child stopped by the checkpoint-failures steer". A child in its review loop no longer qualifies.
  - Orchestrate 26 adds "Merging into an unfinished child", for both a stopped serial child and a paused lane (`lanes.md:39`, `checkpoint-failures.md:17-21`).
  - The new base is the old base with the same incoming commit merged in. When the merge is clean, the diff from that base to the child's merged tip is exactly the child's own work. That holds for a serial child (the incoming commit is the green checkpoint tip) and for a lane (the incoming commit is the work-branch tip, which already contains the old lane base).
  - Review 24 and orchestrate 34 take the base from state, so later reviewers get the new base.
  - Two gaps remain. Both were caused by this fix and its interaction with the FV-M13/FV-m9 conflict path: FV-M16 and FV-m10.
- **FV-m9: fixed.** Checkpoints step 2.4 (orchestrate 61) adds a fresh code-mode review of the resolution, from the checkpoint branch's tip before the merge. Step 2.5 (62) states the trade: green after T1 on the conflicted paths, with the next checkpoint's full run covering the rest. The Bounds pass cap applies. This matches `lanes.md:30` and `checkpoint-failures.md:14`.

**Consistency of the new rules.**
- **With implement:** implement 30 and review 24 both work from "the base commit"; orchestrate 26 replaces that base. The steered child stopped with "Commit, stop, and reply" (`checkpoint-failures.md:17`; implement 38), so its tree is clean, and orchestrate 25 can treat it as a clean point.
- **With `lanes.md`:** line 39 (a paused lane merges the work branch) is covered by orchestrate 26.
- **With `checkpoint-failures.md`:** step 3 hands the merge to Checkpoints step 2, as expected.
- **Where it breaks:** the conflict branch of step 2, when the work branch carries a stopped serial child's commits (FV-M16).

### FV-M16 · major · `skills/orchestrate/SKILL.md:26, 57-62`: a conflicted merge-back into a stopped serial child moves the child's own commits into its new base
**Problem.** This was caused by the FV-M13, FV-m9 and FV-M15 fixes together. A stopped serial child is exactly the case where merge-back conflicts are likely: it was steered because it builds on the code the checkpoint fix changes. On a conflict, step 2.2 has a fresh implementer merge the **work branch** into the checkpoint branch. The work branch holds the stopped child's work-in-progress commits, so they are now in the resolved tip. Step 2.5 then merges that tip into the work branch. Orchestrate 26 then builds the child's new base as "its old base with the same incoming commit merged in". The incoming commit is the resolved tip, which contains the child's own commits, so:
- **The child's diff from its new base is empty.** I checked this in a scratch repo: W0 → checkpoint fix; work branch W0 → child WIP that touches the same line plus a new file; the merge-back conflicts; resolve on the checkpoint branch; merge back; new base = W0 merged with the resolved tip; `git diff <new base> <child tip>` is empty. With W0 merged with the **green** tip as the base, the diff correctly shows the child's two files.
- **Effect:** the child's pre-stop work drops out of its T1 selection (implement 30) and out of its code review (review 24). That is unreviewed, untested code reaching the PR, which is the problem FV-M15 set out to fix.
- **The 2.4 resolution review is also aimed wrong.** It reviews the stopped child's unfinished work, against the last closed child's plan and ledger (orchestrate 60). It will raise findings on code that is deliberately incomplete, and its fixes land in another child's work.

**Fix.** Do one of the following.
- **(a) Preferred: route this conflict to the stopped child.** In step 2, if the work-branch worktree holds a stopped serial child, abort, then resume that child's implementer. It is already in the worktree. It merges the green checkpoint tip and resolves. The new base is the old base merged with the green tip. The resolution then sits inside the child's own diff, gets its T1 and its normal code review, and steps 2.2-2.4 are not needed for this case.
- **(b) Keep the fresh resolver, and fix the base.** In orchestrate 26, define "the incoming commit" as the green checkpoint tip before any conflict resolution, for a serial child (for a lane: the work-branch commit merged). Also say that the 2.4 review covers only the conflicted paths, not the stopped child's work in progress.

### FV-m10 · minor · `skills/orchestrate/SKILL.md:26`, `references/checkpoint-failures.md:21`: the resumed implementer isn't told its new base
**Problem.** This was caused by the FV-M15 fix. Orchestrate 26 says only "Record that base". Reviewers get it, because orchestrate 34 passes the base from state. But the implementer computes T1 from the base in its original task (implement 12, 30), and the resume at `checkpoint-failures.md:21` says only "Then continue". So the T1 half of FV-M15 rests on the orchestrator inferring that it should pass the new base. Pass 4's suggested fix said "Pass that base to the resumed implementer".

Separately, building the base "in the checkpoint worktree" can collide with checkpoint C+1's run when a paused lane merges after C has merged. The one-writer rule (orchestrate 21) covers that, but an off-tree build avoids it.

**Fix.**
- **Line 26:** "Record that base and give it to the resumed implementer."
- **`checkpoint-failures.md:21`:** "Then continue, with the new base (orchestrate → Where work runs)."
- **Optional:** "or build it off-tree with `git merge-tree --write-tree` and `git commit-tree`".

**Counts (pass 5, open):** 0 blocker, 1 major (FV-M16), 1 minor (FV-m10). **Verdict:** changes needed. This pass is already past the cap, so FV-M16 goes to the owner, or to the oracle, to decide.

### Author responses (pass 5)
- **FV-M16 fixed, by the preferred option (a) plus a simpler base rule.**
  - **Base rule.** An unfinished child's old base is always an ancestor of the incoming commit. A serial child starts from C, and the green tip descends from C. A lane starts from a work-branch commit, and the work-branch tip descends from it. So the new base is simply the incoming commit (the green checkpoint tip, or the work-branch commit merged), and no helper-built merge base is needed. That base is the green tip from before any resolution, so the child's own work in progress stays in its diff.
  - **Conflict routing.** A merge-back conflict with a stopped serial child is resolved by that child's resumed implementer, in its own worktree, and becomes part of its own diff, T1 and review. Only the other case (no unfinished child on the work branch) uses the fresh resolver, and its review now covers only the conflicted paths.
- **FV-m10 fixed.**
  - Orchestrate says to give the new base to the resumed implementer.
  - `checkpoint-failures.md` says "continue with its new base".
  - `implement` says to compute T1 from a new base once given one.
  - With no helper-built commit, nothing has to be built in the checkpoint worktree.

## size limit and plan-ahead, pass 1
Fresh code-mode review of `a595ff6` (diff `edf23d8..a595ff6`) against plan §13 (the last three bullets) and §14. `dist/` matches the skills (`node tools/render-skills.mjs --check`). Splitting a child mid-implementation is out of scope, per the owner's ruling.

**What holds.**
- The size limit is consistent across the skills: `scope` sets it (scope 53), `plan` checks it first (plan 44), review checks it in epic and plan modes (review 14, 20), and orchestrate splits into real children (orchestrate 102-104). `state.json` gains the estimate (orchestrate 15).
- The planning worktree does keep the plan-author and its reviewers out of the serial implementer's worktree, and a resumed plan-author doing the Refresh is still in its own worktree (orchestrate 28).
- Before a refresh, the plan branch touches only the N+1 directory, so the merges in both directions are clean when nothing else writes to it (but see SP-M3).

### SP-M1 · major · `skills/orchestrate/SKILL.md:37-42, 48-51`; `skills/plan/SKILL.md:48-53`: the "At N's close" steps aren't ordered against Close, and the refresh misses what Close changes
**Problem.** Close (37-42) and "At N's close" (48-51) are two separate lists with no order between them. Close does several things a refresh has to see:
- it merges a waiting green checkpoint branch;
- it records the new base commit;
- it adjusts later children's epic entries;
- it then calls `self_compact`, naming the next child.

If the refresh runs first, the N+1 plan is refreshed without the checkpoint fix or its own adjusted entry. Even when the order is right, Refresh step 2 (plan 51) checks the plan only against "its diff and ledger". It doesn't check the epic entry, Decisions or Follow-ups, or a checkpoint merge that came in since planning started.

Two more gaps:
- **N can close before N+1's plan loop is approved.** A short child against a long plan loop makes this likely. Step 1 then resumes a plan-author that is still running, or is between review passes. Nothing says to wait.
- **N+1's base commit.** Close records the base before the plan branch merges, so N+1's base sits before its own `plan.md`.

**Fix.** Put plan-ahead into Close as numbered steps:
1. mark done, do the lane or checkpoint merges, adjust the epic entries, and commit the state;
2. wait for N+1's plan loop to be approved;
3. Refresh;
4. review, if needed (SP-M2);
5. merge the plan branch;
6. record N+1's base;
7. `self_compact`.

In `plan` → Refresh step 2, add "and against changes to `epic.md` (your entry, Decisions, Follow-ups) and any checkpoint merge since you planned."

### SP-M2 · major · `skills/orchestrate/SKILL.md:50`, `:91`: the post-refresh review is "one" review, with no path when it doesn't approve and no rule for counting passes
**Problem.** "If the design changed, run one fresh plan review." Read literally, the review isn't a loop. A changes-needed verdict has no defined next step, so the orchestrator either implements an unapproved plan or improvises. The Bounds cap (91) doesn't say whether these passes continue N+1's earlier count. If they do, a plan approved at pass 3 gets one try. The refresh is also exactly where the estimate can grow past the size limit, and nothing re-checks it.

**Fix.** "If the design or estimate changed, re-enter step 1's review loop with a fresh reviewer. The refresh starts a new pass count under the normal cap. If the estimate is now over the size limit, resize (Sizing and scope) before implementing." Refresh step 4 (plan 53) should report the estimate as well.

### SP-M3 · major · `skills/orchestrate/SKILL.md:14, 21-28, 102`: plan-ahead makes the orchestrator write to the implementer's worktree during N's implementation
**Problem.** "Update and commit it after every step" (14). `state.json` and `epic.md` live in the plan directory, on the work branch, in the work-branch worktree. During a serial child, that worktree belongs to N's implementer (21-22). Plan-ahead adds orchestrator steps that happen while N is being built, and each one must be committed:
- N+1's planner run ids and plan-review pass counts;
- a resize of N+1 into `NN+1a`/`NN+1b`, which edits the epic's children and Decisions (102);
- follow-ups and "can't plan yet" fallbacks.

Every one of those commits is a second writer in the implementer's worktree. That is the `index.lock` problem §14 cites as the reason for the planning worktree. Uncommitted edits are worse: the implementer's commits sweep them up. The problem partly predates this change, since code-review state is already written during serial implementation, but plan-ahead makes it routine and the skill now claims to prevent it.

**Fix.** Name a home for orchestrator writes while a serial child is implementing. The simplest:
- "While a serial child is implementing, commit `state.json` and `epic.md` changes in the planning worktree, on the plan branch. The refresh merge and the plan-branch merge carry them to the work branch."
- If the planning worktree is idle (plan-ahead skipped), use it anyway.
- The work branch then has only the implementer as a writer until close, so the refresh merge can't conflict on `state.json`.

### SP-M4 · major · `skills/orchestrate/SKILL.md:44-52`; `references/lanes.md:5-6`: plan-ahead is undefined in lane mode
**Problem.** "The default" is to start N+1's plan loop "as soon as child N's implementer starts". In a parallel group, several Ns start at once. Which child is "N+1", and when does it start?
- **If N+1 is a group member:** lanes.md 6 says its plan-author launches in its pool worktree. Plan ahead says the planning worktree. A pool worktree may not be allocated yet; `maxLanes`, memory and disk gate that.
- **If N+1 is the first child after the group:** it must plan against several approved plans, and refresh only after every member is integrated (lanes.md 23). "At N's close" fires per lane, so it would refresh several times, or too early.
- lanes.md doesn't mention plan-ahead at all.

**Fix.** Pick a rule and state it in both places. Simplest: "Plan ahead only when N and N+1 are both serial. For the first child after a group: start it when the group's last member starts implementing, plan against all the members' approved plans, and refresh after the last member is integrated. Group members plan in their own lane worktrees (`lanes.md`)." Add one line to `lanes.md`.

### SP-M5 · major · `skills/orchestrate/SKILL.md:15, 92-93`: a planned-ahead child's wall-time budget counts the time it spends waiting for N
**Problem.** "A child over its wall-time or cost budget stops" (93). Wall time isn't defined; the only data is "phase timestamps". With plan-ahead, N+1's first phase starts when N's implementer starts. So N+1's clock includes all of N's implementation, roughly the 3 h size limit, before its own implementer starts. Measured from first phase to close, nearly every planned-ahead child will overrun a 4 h budget like the pilot's and stop for the human, spuriously, while running unattended. The reverse reading (implementer start to close) is also unwritten. The orchestrator has to guess either way.

**Fix.** Define it in Bounds: "A child's wall time is the sum of its active phases (plan loop, refresh, implement loop). For a planned-ahead child, the wait between plan approval and N's close doesn't count." Record those phases in the per-child timestamps (15).

### SP-m1 · minor · `skills/orchestrate/SKILL.md:32, 46`; `skills/review/SKILL.md:18-21`: plan-mode reviewers aren't told the plan was written ahead
**Problem.** N+1's reviewers launch in a worktree that doesn't have N's code. A plan that builds on N's planned APIs fails "fits the codebase" and "can be built without guessing". That produces findings the author must reject, and disputes that go to the oracle, which burns passes toward the cap.

**Fix.** In Plan ahead, pass the reviewer "planned ahead of N; judge references to N's work against `NN/plan.md`". Or add to review plan mode: "If the plan was written ahead, the previous child's approved plan stands in for its code."

### SP-m2 · minor · `skills/orchestrate/SKILL.md:18, 47, 90`: the planning worktree's lifecycle is underspecified
**Problem.**
- **Creation.** "Reuse it for each child" doesn't say who creates it.
- **Reuse.** It doesn't say that reuse means a fresh plan branch at the current work-branch tip, or when reuse is safe.
- **A stale plan-author.** Bounds 90 says planner calls resume that child's session. Once the worktree has moved on to N+2, resuming N+1's plan-author (for example, to fold rework, line 105) would make it a second writer there.
- **Recovery** (18) reads `git status` without saying which worktree.

**Fix.**
- "Create it once with `git worktree add`. For each child, switch it to a new plan branch at the work-branch tip, only when it is clean and the previous plan branch has merged (as `lanes.md` → The pool)."
- "Once a child's implementer starts, plan changes go to a fresh plan-author, not a resumed one."
- Recovery: "`git status` in every worktree in use".

### SP-m3 · minor · `skills/plan/SKILL.md:45`; `skills/review/SKILL.md:21`; `skills/orchestrate/SKILL.md:33, 38`: out-of-scope follow-ups live only in the plan-author's reply
**Problem.** Plan 45 puts follow-ups "in your reply, not into the plan". The reviewer can't see the reply, so "unrecorded extra work" (review 21) has no record to check against. Orchestrate never moves planner-reported follow-ups into `epic.md` Follow-ups: Close (38) handles the child's own follow-ups at close, long after the planner's reply has been compacted away. The scope-growth rule's side items can therefore be lost.

**Fix.**
- **Plan 45:** "…goes under a short Follow-ups line in `plan.md`, not into Changes."
- **Review 21:** "Work beyond the entry, outside Follow-ups, is a major finding."
- **Orchestrate step 1:** on approval, copy the plan's Follow-ups into `epic.md`.

### SP-m4 · minor · `skills/scope/SKILL.md:19`; `skills/review/SKILL.md:20`: the single-plan shape still uses the "one session" test that §14 says isn't a limit
**Problem.** Scope step 3 chooses a single plan "if one implementer can build it in one session". §14 says self-compaction makes that no limit, and a single plan has no epic, so review 20 ("within the epic's size limit") has nothing to check against.

**Fix.**
- **Scope 19:** "…if it is within the size limit (see `epic.md` Size limit; record it in `plan.md`)".
- **Review 20:** "…within the size limit (`epic.md`, or a single plan's own)".

**Counts (pass 1, open):** 0 blocker, 5 major (SP-M1-SP-M5), 4 minor (SP-m1-SP-m4). **Verdict:** changes needed.

### Author responses (size limit and plan-ahead, pass 1)
- **SP-M1 fixed.** Close is now a numbered sequence:
  1. merge the plan branch (state commits plus any plan written ahead);
  2. mark the child done;
  3. lane and checkpoint merges;
  4. start the checkpoint;
  5. adjust epic entries, commit;
  6. if planned ahead: wait for plan approval, Refresh, review if needed, merge the plan branch;
  7. record the next child's base after its plan merges, then `self_compact`.

  `plan` → Refresh also checks changes to `epic.md` (entry, Decisions, Follow-ups) and checkpoint merges.
- **SP-M2 fixed.** If the design or estimate changed, the plan re-enters step 1's review loop with a fresh reviewer and a new pass count under the normal cap, and is resized first if it is now over the limit. Refresh updates and reports the estimate.
- **SP-M3 fixed.** New "Where work runs" rule: while a serial child is in its implement loop, the orchestrator commits `state.json` and `epic.md` in the planning worktree, on its plan branch, even if nothing is being planned ahead. Close step 1 brings them over. The work branch has only the implementer as a writer until Close.
- **SP-M4 fixed.** Plan-ahead applies to serial→serial pairs. For the child after a parallel group, it starts when the last member starts implementing, works from every member's plan, and refreshes after the last member is integrated. Members plan in their lane worktrees. `lanes.md` says the same.
- **SP-M5 fixed.** Bounds defines wall time as the sum of active phases (plan loop, refresh, implement loop), excluding waiting for the previous child. State records each phase's start and end.
- **SP-m1 fixed.** Plan ahead says to tell the plan-author and reviewers. Review plan mode judges references to earlier children's work against their approved plans.
- **SP-m2 fixed.**
  - The planning worktree is created once with `git worktree add`. For each child it is switched to a new plan branch at the work-branch tip, only when clean and after the previous plan branch has merged.
  - Once a child's implementer starts, plan changes go to a fresh plan-author.
  - Recovery runs `git status` in every worktree in use.
- **SP-m3 fixed.**
  - `plan` puts out-of-scope items on a Follow-ups line in `plan.md`.
  - Review treats extra work not on that line as major.
  - Orchestrate copies the plan's Follow-ups into `epic.md` on approval.
- **SP-m4 fixed.** Scope's single-plan test uses a size limit recorded in `plan.md`. Review checks the limit "in `epic.md`, or a single plan's own".

## size limit and plan-ahead, pass 2
Fresh code-mode review of `8a5aea0`. The fixes are diff `b314a94..8a5aea0`, and the full change is `edf23d8..8a5aea0`. Checked against plan §13 (the last three bullets) and §14. `node tools/render-skills.mjs --check` passes: `dist/` matches the skills. Mid-implementation splits stay out of scope, per the owner's ruling.

### Earlier findings, verified in the artifacts
- **SP-M1 fixed.**
  - Close is now one ordered list (orchestrate 38-49).
  - The refresh comes after the checkpoint merge (step 3) and the epic-entry adjustments (step 5).
  - Step 6 waits for the plan loop to be approved.
  - Step 7 records the base after the plan branch merges.
  - Refresh step 2 checks `epic.md` and checkpoint merges (plan 51-54).
  - Merging the plan branch at step 1, before the plan is approved, is safe: step 6 merges the rest, and the planning worktree switches branches only after that.
- **SP-M2 fixed** (orchestrate 47; plan 53-54). There is a review loop with a new pass count under the cap, a resize check, and the estimate is reported.
- **SP-M3 fixed as stated.** While a serial child implements, only the implementer writes to the work-branch worktree (orchestrate 25). The fix causes SP-M6 and SP-M7.
- **SP-M4 fixed** (orchestrate 59-61; lanes 10).
- **SP-M5 fixed** for the case raised (orchestrate 101; state per phase, 15). The new definition causes SP-m5.
- **SP-m1 fixed** (orchestrate 62; review 22).
- **SP-m2 fixed** (orchestrate 18, 63, 64).
- **SP-m3 fixed** (plan 45; review 21; orchestrate 34).
- **SP-m4 fixed** (scope 19; review 20).

### SP-M6 · major · `skills/orchestrate/SKILL.md:21, 25, 63`: the orchestrator is now a second writer in the planning worktree (caused by the SP-M3 fix)
**Problem.** Line 25 sends the orchestrator's `state.json` and `epic.md` commits to the planning worktree while a serial child is in its implement loop. That is exactly when N+1's plan-author and plan reviewers run and commit there (59, 63). The orchestrator commits after every step: run ids, pass counts, and N's code-review passes. On approval it also copies Follow-ups into `epic.md` (34), and a resize edits `epic.md` (110). All of that happens while a plan-author or reviewer is mid-run in the same worktree. This breaks "One writer per worktree at any time" (21). It brings back the `index.lock` collision §14 cites, now in the planning worktree, and a plan-author that commits with `-a`/`-A` sweeps up the orchestrator's half-written edits. The SP-M3 fix moved the second writer instead of removing it.

**Fix.** Give the orchestrator's writes their own worktree:
- "While a serial child is in its implement loop, commit `state.json` and `epic.md` in the state worktree: a plain `git worktree add` with no install, on a state branch cut from the work-branch tip when the implementer starts. Close step 1 merges the state branch and the plan branch."

If a third worktree isn't wanted, the alternative is: "commit in the planning worktree only while no plan-author or reviewer is running there". That needs a rule for where pending state lives in the meantime, and it must survive `self_compact`.

### SP-M7 · major · `skills/orchestrate/SKILL.md:18, 25, 51-54`; `skills/implement/SKILL.md:12, 38`: two copies of `state.json` and `epic.md` during an implement loop, with no rule for which is live (caused by the SP-M3 fix)
**Problem.** During N's implement loop, the current state is on the plan branch, and the work branch's copy is stale until Close step 1. Nothing says so. Three consequences:
- **Recovery (18)** reads "`state.json`" without saying which copy. After a mid-loop `self_compact` (allowed "whenever your context grows large", 127) or a crash, the work-branch copy lacks:
  - N's implementer run id;
  - its code-review pass count;
  - N+1's planner run ids.

  The orchestrator then spawns a second implementer into a worktree that already has one, or restarts the pass count and gets past the cap of 4.
- **The implementer reads the baseline digest from `state.json` in its own worktree** (implement 12, 38). A base-side failure found by checkpoint triage during the loop is added to the baseline (checkpoint-failures 7). A flake is quarantined in `epic.md` (checkpoint-failures 6). Both edits now land on the plan branch, so a running or resumed implementer never sees them before Close. It then treats a baseline failure as its own, and spends its loop on it.
- **Single plan (51-54)** runs step 2 but has no planning worktree and no Close. Read literally, line 25 commits state to a plan branch that nothing ever merges, so the PR hand-off leaves it behind.

**Fix.**
- Line 25: "While a serial child implements, the live `state.json` and `epic.md` are on the plan (or state) branch."
- Recovery: "read `state.json` from that branch if it hasn't merged; otherwise from the work branch".
- When the baseline or the Quarantine list changes mid-loop, pass the change to the implementer in its steer or resume message.
- Single plan: either exempt it ("commit on the work branch, only between implementer runs"), or merge the state branch before the full-gate run.

### SP-m5 · minor · `skills/orchestrate/SKILL.md:101`: wall time counts a checkpoint stop (caused by the SP-M5 fix)
**Problem.** The definition excludes only waiting for the previous child. A serial child stopped by the checkpoint-failures steer, or a paused lane, waits inside its implement loop for:
- a fix;
- a fix review;
- a full-gate recheck.

Read literally, that wait counts, and it can trip the budget spuriously while the epic runs unattended.

**Fix.** "…Time spent waiting for the previous child, or stopped for a checkpoint (from the steer to the resume), doesn't count." Record the stop and resume times with the phases (15).

### SP-m6 · minor · `skills/orchestrate/SKILL.md:44-49, 65`: when the next child wasn't planned ahead, its base still comes before its own plan (caused by the SP-M1 fix)
**Problem.** Step 7 records the next child's base at close in every case. When the next child wasn't planned ahead (65), its plan is written after that. Where the plan is written isn't specified, so `plan.md` and its plan ledger land after the base, inside the child's diff. This is the gap that SP-M1 closed only for the planned-ahead case. The diff noise is small, but code review and changed-file T1 selection both see it.

**Fix.** Step 6, otherwise branch: "If it wasn't planned ahead, run its plan loop now in the planning worktree, then merge the plan branch." Step 7 then records the base after that merge in both cases.

**Counts (pass 2, open):** 0 blocker, 2 major (SP-M6, SP-M7), 2 minor (SP-m5, SP-m6). SP-M1-SP-M5 and SP-m1-SP-m4 are closed. **Verdict:** changes needed.

### Author responses (size limit and plan-ahead, pass 2)
- **SP-M6 and SP-M7 fixed, by keeping one copy instead of moving the state.** The SP-M3 plan-branch rule is withdrawn.
  - `state.json` and `epic.md` have a single current copy, in the work-branch worktree, and every session gets that path, including sessions in other worktrees.
  - While a serial child is in its implement loop, the orchestrator writes these files but runs no git commands in that worktree, so there is no second git writer and no `index.lock` race. It commits them at Close step 1, and otherwise as it goes.
  - Recovery reads the files on disk, which are current. Implementers read the current baseline digest and Quarantine.
  - Single-plan mode commits at handoff.
  - `implement` must never stage, stash or revert those files, and stages its own paths, never everything. Its Handoff allows only the orchestrator's files to stay modified.
  - The plan branch now carries only plans and plan ledgers.
- **SP-m5 fixed.** Checkpoint stops (from the steer to the resume) are excluded from wall time and recorded in state.
- **SP-m6 fixed.** Close step 6 runs every next-child plan loop in the planning worktree, whether it was planned ahead or not, and merges the plan branch. Step 7 records the base after that merge.

## size limit and plan-ahead, pass 3
Fresh code-mode review of `2af32b3`. The fixes are diff `8da183a..2af32b3`, and the full change is `edf23d8..2af32b3`. Checked against plan §13 (the last three bullets) and §14. `node tools/render-skills.mjs --check` passes: `dist/` matches the skills. Mid-implementation splits stay out of scope, per the owner's ruling. The SP-M3 plan-branch approach is withdrawn. I checked the single-copy rule (orchestrate 25) against every git operation in the work-branch worktree while a serial child implements.

### Earlier findings, verified in the artifacts
- **SP-M6 fixed.** The orchestrator no longer commits in the planning worktree. Its files stay in the work-branch worktree (orchestrate 25), and the plan branch carries only plans and ledgers (65). Plan-author and plan reviewers are the only writers there, one after another.
- **SP-M7 fixed** for the three cases raised:
  - There is one current copy, and every session gets its path (25). Recovery reads that copy (18).
  - The implementer reads the baseline digest and Quarantine from the live file (implement 12). Checkpoint triage writes to the same file.
  - Single plan commits the files before the PR hand-off (56).

  The new rule causes SP-M8 and SP-m8.
- **SP-m5 fixed.** Checkpoint stops are excluded from wall time (103) and recorded per child (15).
- **SP-m6 fixed** for serial children (orchestrate 44-51): every next-child plan loop merges before step 7 records the base. The new "Otherwise" branch causes SP-m7.

### The single-copy rule against git in the work-branch worktree
- **Implementer commits:** safe. Implement 76 says to stage its own paths only and never stash or revert the orchestrator's files. Handoff 59 allows those files to stay modified. The "commit first" before `self_compact` (26) falls under the same rule.
- **Checkpoint-failures steer ("commit, stop"):** the implementer's commit is safe. The merge that has to follow is not; see SP-M8.
- **Merges at clean points:** safe between serial children, because Close step 1 commits first. They break at a steer stop (SP-M8).
- **Lane integration:** safe. There is no serial implement loop in that worktree during a group, so the files are committed as you go. The reset on red T1 (lanes 27) only affects committed state.
- **Recovery's dirty-tree rule:** broken (SP-M8).
- **Single-plan mode:** safe (56).
- **Code reviewer's ledger commit:** not covered (SP-m8).

### SP-M8 · major · `skills/orchestrate/SKILL.md:25, 27, 77, 108`; `references/checkpoint-failures.md:3, 17-21`: the work-branch worktree is never clean during an implement loop, but three rules still need it clean or need git there (caused by the SP-M7 fix)
**Problem.** Line 25 leaves `state.json` and `epic.md` modified for the whole implement loop and forbids git there until Close step 1. Three rules conflict with that:
- **Steer stop.** A serial child stopped by the checkpoint-failures steer is still in its implement loop; it hasn't closed. To resume, it must first get the green checkpoint branch through a merge into the work branch (checkpoint-failures 17-21; orchestrate 77). Line 27 names this stop as a clean point, and allows merging "only when its worktree is clean". The tree isn't clean, because of the orchestrator's own files, and line 25 forbids the git command anyway. Read literally, the merge can never happen, so the stopped child never resumes. Otherwise the orchestrator breaks one of the rules without guidance. Checkpoint-failures 3 adds to the conflict. It says "everything here happens on the checkpoint branch… the work branch… untouched", yet the same file's Quarantine, baseline and regression writes (6, 7, 15) must go to the work-branch copy. If they went to the checkpoint worktree's copy instead, the green merge would collide with the dirty files.
- **Recovery (108).** "A dirty tree at the start of a step belongs to an interrupted session. Resume that session to commit or discard." This is the SP-M7 scenario: after a mid-loop `self_compact` or a crash, Recovery runs `git status` (18). The tree is always dirty with the orchestrator's own files. The rule then has the orchestrator resume the implementer to "commit or discard" them. At best that is a wasted resume, since implement 76 forbids touching them. At worst the implementer follows the task message and discards them, losing N's run id and pass count and N+1's planner run ids. That is exactly the state SP-M7 set out to protect.

**Fix.**
- **Line 25:** "…run no git commands there while its implementer or reviewer is running. At a checkpoint-failures stop, commit your files before merging."
- **Line 27:** "only when its worktree is clean apart from your own files, and you have committed those first."
- **Recovery 108:** "A dirty tree, apart from your own files, belongs to an interrupted session."
- **Checkpoint-failures 3:** "Your own files (`state.json`, `epic.md`) stay in the work-branch worktree (orchestrate → Where work runs)."

### SP-m7 · minor · `skills/orchestrate/SKILL.md:44-51`; `references/lanes.md:6, 10`: Close step 6 plans every next child in the planning worktree, including group members (caused by the SP-m6 fix)
**Problem.** "Otherwise: run its plan loop now… Either way, plan loops run in the planning worktree." Two cases go wrong:
- **Serial child followed by a group.** Step 6 plans the first member in the planning worktree and merges its plan into the work branch before its lane starts. That contradicts lanes.md 6 and 10, and orchestrate 63.
- **A lane child's Close.** Its "next child" is usually a sibling that is already planned or running in its own lane. Step 6 tells the orchestrator to plan it again. Step 7 then records a base for it, which doesn't apply, since lanes share one base (lanes 6).

**Fix.** Step 6: "Plan the next child if it is serial, including the first child after a group (Plan ahead). Group members plan in their lanes (`references/lanes.md`)." Apply step 7's base to serial children only.

### SP-m8 · minor · `skills/review/SKILL.md:52`; `skills/implement/SKILL.md:30`: other sessions in the work-branch worktree don't account for the orchestrator's uncommitted files (caused by the SP-M7 fix)
**Problem.**
- **The code reviewer.** It runs in the work-branch worktree during the implement loop and must "Commit the ledger" (review 52). Only `implement` was told to stage its own paths. A reviewer that runs `git commit -a` or `git add -A` sweeps the orchestrator's files into its review commit. That loses no data, but it is a second session committing them mid-loop, against line 25's intent.
- **T1 selection.** Implement 30 computes T1 from `git diff <base>`, which includes the working tree. It now always contains `state.json` and `epic.md`, and the reviewer's "T1 selection covers the actual diff" check (review 35) sees the same noise. Usually that selects nothing, but a repo whose test map or widening rules cover `plans/` or docs would mis-select.

**Fix.**
- **Review 52:** "Commit the ledger, staging only that file."
- **Implement 30:** "…from `git diff <base>`, excluding the orchestrator's `state.json` and `epic.md`."

**Counts (pass 3, open):** 0 blocker, 1 major (SP-M8), 2 minor (SP-m7, SP-m8). SP-M6, SP-M7, SP-m5 and SP-m6 are closed. **Verdict:** changes needed.

### Author responses (size limit and plan-ahead, pass 3)
- **SP-M8 fixed.**
  - The no-git rule now applies only while a serial child is *actively building*. Before merging into a stopped child, the orchestrator commits its own files.
  - "Merging into the work branch" requires a clean tree *after* the orchestrator commits its files.
  - Recovery's dirty-tree rule exempts the orchestrator's own files: they are its to commit, and never to discard.
  - `checkpoint-failures.md` names the merge into a stopped child as the one exception to "the work branch stays untouched".
- **SP-m7 fixed.** Close step 6 says parallel-group members plan in their lane worktrees.
- **SP-m8 fixed.** The review skill commits the ledger by staging only that file. Implement's T1 selection excludes the orchestrator's files.

## size limit and plan-ahead, pass 4
Fresh code-mode review of `659ea8a`. The fixes are diff `ed990b0..659ea8a`, and the full change is `edf23d8..659ea8a`. Checked against plan §13 (the last three bullets) and §14. `node tools/render-skills.mjs --check` passes: `dist/` matches the skills. Mid-implementation splits stay out of scope, per the owner's ruling. This is the last pass under the cap.

### Earlier findings, verified in the artifacts
- **SP-M8 fixed.** All three conflicts are resolved:
  - **Steer stop.** The no-git rule now covers only a child that is actively building, and the orchestrator commits its own files before a merge into a stopped child (orchestrate 25). The merge rule needs a clean tree once those files are committed (27), so the merge at a steer stop can happen. `checkpoint-failures.md` 3 names that merge as the one exception to "the work branch stays untouched".
  - **Conflict path.** When the merge conflicts (orchestrate 79), the resumed implementer merges while the orchestrator's files may be modified again. That merge is safe. The checkpoint branch never changes `state.json` or `epic.md`, because their only copy is in the work-branch worktree (25), so `git merge` doesn't touch the dirty paths.
  - **Recovery.** Recovery exempts the orchestrator's files: they're its to commit, and never to discard (108). The SP-M7 state can no longer be discarded by a resumed session.
- **SP-m8 fixed.** The review skill commits the ledger by staging only that file (review 52). T1 selection excludes `state.json` and `epic.md` (implement 30).
- **SP-m7 partly fixed; still open (minor).**
  - **Fixed:** the serial-then-group case. Close step 6 now sends group members' plan loops to their lane worktrees (orchestrate 50), matching lanes 6 and 10.
  - **Not fixed:** a lane child's own Close. Steps 6 and 7 still run unconditionally. When a group member that isn't last closes, its "next child" is a sibling that is already planned and possibly implementing in its lane. Step 6 then says to wait for its plan loop to be approved and resume its plan-author to refresh. That plan-author keeps the lane worktree (29), where the sibling's implementer may be running, which contradicts 66 and "one writer per worktree". Step 7 also records a base for that sibling, though lanes share one base (lanes 6).
  - **Fix:** in Close step 6, add: "Skip steps 6 and 7 when the next child has already started, as a sibling in a group does. After the group's last member closes, they apply to the child after the group." An orchestrator will probably skip the sibling anyway, so this stays minor.

### SP-m9 · minor · `skills/orchestrate/SKILL.md:25`: "actively building" doesn't say whether the code reviewer's run counts (caused by the SP-M8 fix)
**Problem.** Before the SP-M8 fix, the no-git window was the whole implement loop. It is now "while a serial child is actively building". The code reviewer runs in the same worktree and commits its ledger (review 52), and that can be read as not "building". Under that reading, the orchestrator may commit `state.json` and `epic.md` while a code reviewer is running. Plan-ahead makes this routine: planner run ids and pass counts change while N is in review. Two git writers in one worktree bring back the `index.lock` race. And if the orchestrator has just staged its files, the reviewer's plain `git commit` sweeps them into the review commit, even though the reviewer staged only the ledger.

**Fix.** Line 25: "While a serial child's implementer or code reviewer is running, write these files but run no git commands there."

**Counts (pass 4, open):** 0 blocker, 0 major, 2 minor (SP-m7 residual, SP-m9). SP-M8 and SP-m8 are closed. **Verdict:** approved.

### Author responses (size limit and plan-ahead, pass 4)
- **SP-m7 fixed.** Close step 6 skips steps 6 and 7 when the next child is a sibling in the same parallel group, because it is already running.
- **SP-m9 fixed.** The no-git rule now reads "while a serial child's implementer or code reviewer is running".

## test budget and escalation, pass 1
Fresh code-mode review of `18bfbba` (diff `152fb93..18bfbba`), against plan §15's rulings. Checked against `test-quality`, `plan`, `implement`, `review`, `orchestrate` (with `references/lanes.md` and `references/checkpoint-failures.md`) and `scope`. `node tools/render-skills.mjs --check` passes: `dist/` matches the skills. The rulings themselves (the Tests list as the budget, the ledger escape hatch, the ratio as a signal only, escalation from pass 3) are settled. These findings concern only how the text carries them out.

### TB-M1 · major · `skills/review/SKILL.md:32`; `skills/plan/SKILL.md:27`; `skills/implement/SKILL.md:64`: the traceability rule flags legitimate tests that relocate or rewrite existing proof
**Problem.** Review 32 makes "every new test" that doesn't trace to the plan's Tests, or to "a contract the ledger adds", a major finding. Three kinds of legitimate test fall outside both routes as written:
- **Moved, split or rewritten tests.** test-quality asks for consolidation ("extend table cases… instead of near-copies"; "don't delete a test without naming… where that proof now lives"). When behavior changes, an implementer often deletes an old test and writes its replacement, or moves it to the owning layer. In the diff these are new tests. They prove existing contracts, not ones "the plan didn't list", so implement 64 doesn't prompt the implementer to record them. A fresh reviewer then raises a major. The easy way to clear it is to drop the new test, and that loses coverage whose original is already gone.
- **Independent contracts outside the Tests scope.** Plan 27 scopes Tests to "each acceptance scenario and each risky piece of logic". test-quality's Keep list (config, default value, migration, API, exact prompt text, generated output, package) covers contracts a child often adds without their being a scenario or risky logic. "Keep it complete" doesn't override the narrower definition just before it, so these contracts are routinely left off the list.
- **Regression tests outside the implement handoff.** Integration and checkpoint-fix loops are reviewed in code mode (lanes step 4; checkpoint-failures step 2), but `## integration` and `## checkpoint fix` entries don't carry implement 64's bullet. test-quality requires a regression test for the regression these loops fix, and that test has no route to trace through.

In each case the escape hatch technically exists, but nothing tells the author to use it. The result is false majors that burn passes under a cap of 4, and push children into escalation.

**Fix.**
- **Review 32:** "Every new test proves a contract in the plan's Tests, carries over an existing test's proof that the diff moved, split or rewrote, or proves a contract the ledger adds with a reason (a regression test names its bug). Any other test is a major finding."
- **Plan 27:** "…each acceptance scenario, each risky piece of logic, and each independent contract the child adds or changes (`test-quality` Keep)…"
- **Implement 64:** "any contract you proved that the plan didn't list, including regression tests for bugs you found, and why; tests you moved, split or rewrote, and where each came from". Have `## integration` and `## checkpoint fix` record the same thing (implement 52–56).

### TB-M2 · major · `skills/orchestrate/SKILL.md:102`: the escalation launch doesn't say where it runs, what it gets, or which loops it covers
**Problem.** "Code-review fix passes from pass 3 on go to a fresh one of those, given the ledger." Elsewhere, a fresh session carries its context explicitly ("Resumed sessions keep their original worktree. Work that must happen elsewhere gets a fresh session, given the plan and ledger it needs"; step 2 gives the implementer the directory, base commit and E2E worker count). This line gives only the ledger, which leaves three gaps:
- **Worktree.** A lane child's or checkpoint fix's escalation launched with the orchestrator's default cwd lands in the work-branch worktree. There it edits the wrong branch, and is a second writer beside the serial child that may be building there. That breaks "one writer per worktree".
- **Base.** Without the child's *current* base (it may have moved after a merge into a stopped child, orchestrate 28), T1 selection and the next reviewer's diff are computed from the wrong commit.
- **Scope.** Code-mode loops also run for lane integration (lanes step 4), checkpoint-merge conflicts (orchestrate 83) and checkpoint fixes (checkpoint-failures step 2), each with "the normal pass cap". Read literally, escalation applies to all of them. Each needs a different worktree and different inputs (the failure digest, both plans), and none of them is stated.

**Fix.** Line 102: "…go to a fresh session of that agent (`implement` skill), in the same worktree as the loop's implementer, with the same inputs (the child's directory, its current base, E2E worker count, and for integration or checkpoint loops, the plans, ledgers and digest that loop names) plus the ledger. Later passes resume it." Also state whether integration and checkpoint loops escalate. If they don't, say "child implement loops only".

### TB-m1 · minor · `skills/orchestrate/SKILL.md:14, 37, 100`; `skills/implement/SKILL.md:9`; `references/lanes.md:27`: after escalation, "that child's implementer" is ambiguous
**Problem.** Several places resume "the child's implementer": Bounds 100, Close/epic close 92 ("resume it"), the checkpoint-merge conflict (79), the lane integrator (lanes 27) and Recovery. After escalation there are two such sessions. State 14 keeps only "the latest … implementer run ids", and implement 9 still tells the original that "this session owns the code until it is approved". Plan §15 also wants escalations measured, but the state has no field for them.

**Fix.** Bounds 102, add: "From then on, the escalation session is that child's implementer for every later resume (integration, checkpoint merge, epic close, recovery)." In State, record the escalation run id and the pass at which it took over. Implement 9: "…until it is approved or escalated."

### TB-m2 · minor · `skills/orchestrate/SKILL.md:102`; `skills/scope/SKILL.md:53`: "from pass 3 on… later passes resume it" is effectively one pass
**Problem.** Fix pass N answers review pass N (implement 60; orchestrate 37). A loop not approved after review pass 4 stops (101). So the only escalated fix is fix pass 3, and "later passes resume it" never runs. An orchestrator could also count "pass 3" as the third implementer turn (after review pass 2), which gives the escalation implementer two attempts. The two readings differ in both cost and outcome.

**Fix.** Name the pass by its review: "the fixes for review pass 3 onward (with the cap at 4, that is one fix pass)". Or, if the owner meant two escalated attempts, "from review pass 2's fixes on". Mirror the wording in scope 53.

### TB-m3 · minor · `skills/review/SKILL.md:23`: plan review doesn't check the Tests list as a budget
**Problem.** Plan 27 now makes Tests the test budget and says to "keep it complete and lean". The plan-mode check is still just "names the contracts to prove, at sensible layers". A padded list defeats the budget, and an incomplete one causes TB-M1's false majors. Nobody checks either until code review.

**Fix.** Review 23: "names the contracts to prove, at sensible layers (`test-quality`), and is the test budget: complete for the child's scenarios, risky logic and independent contracts, with no contract that test-quality wouldn't keep."

**Counts (pass 1, open):** 0 blocker, 2 major (TB-M1, TB-M2), 3 minor (TB-m1, TB-m2, TB-m3). **Verdict:** changes needed.

### Author responses (test budget and escalation, pass 1)
- **TB-M1 fixed.** Review's traceability rule now:
  - accepts ledger-recorded contracts, naming regression tests for bugs found while building and independent contracts beyond the plan's list (config, defaults, migrations; `test-quality` → Keep);
  - says moved, split or rewritten tests whose contract changed aren't new;
  - keeps a test with no contract as a major finding;
  - makes a contract missing only from the ledger a minor: "record it, don't delete the test".

  Implement's ledger bullet asks for *every* unlisted contract, including regression tests from building or fixing.
- **TB-M2 fixed.** The escalation implementer runs where the child's implementer ran, with the same plan, base commit and ledger. Only the child's own code-review loop escalates; integration and checkpoint fixes don't.
- **TB-m1 fixed.** After escalation, the escalation implementer is the child's implementer: its run id is recorded, and it is resumed for later passes. Implement's ownership line notes the handoff.
- **TB-m2 fixed.** The trigger is now "the child's own code review isn't approved at pass 2". The escalation implementer gets fix passes 2 and 3 under the cap of 4.
- **TB-m3 fixed.** Plan review checks that the Tests list is complete and lean, because it is the test budget.

## test budget and escalation, pass 2
Fresh code-mode review of `152fb93..5725f57`, focused on the pass 1 findings, checked in the skills rather than in the author's responses. `node tools/render-skills.mjs --check` passes: `dist/` matches the skills.

### Earlier findings
- **TB-M1: fixed.** The fix doesn't widen plan 27's Tests scope as suggested. Instead it changes the severities, which is enough. Review 32 now makes only a test with no contract a major. A test whose real contract is missing only from the ledger (a regression test, an independent Keep contract, or a move or split that the "isn't new" clause doesn't cover) is at worst a minor, "record it, don't delete the test". That removes the false majors and the pressure to drop coverage. Implement 64 asks for every unlisted contract, including regression tests "found while building or fixing". `## integration` and `## checkpoint fix` (implement 52–56) still don't carry that bullet, but under the new severities an omission there costs only a minor.
- **TB-M2: fixed, with one input left out (TB2-m1).** Orchestrate 102 now says where the session runs ("where the child's implementer ran"), what it gets (plan, base commit, ledger) and its scope ("Integration and checkpoint fixes don't escalate"). The base is the one recorded in state, which orchestrate 28 keeps current after a merge into a stopped child, so T1 and the reviewer's diff stay correct.
- **TB-m1: fixed.** Orchestrate 102: "From then on it is the child's implementer: record its run id, and resume it for later passes". Because every other resume names "the child's implementer", it also covers checkpoint merges (79), recovery and epic close. Implement 9 notes the handoff. Recording the escalation run id in the implementer slot doesn't preserve the fact that the child escalated, which plan §15 wants measured. The fix pass ledger shows it, though, so I'm not reopening this.
- **TB-m2: partly fixed, still open (minor).** Orchestrate 102 and plan §15 now use one unambiguous trigger: review pass 2 not approved, so the escalation session gets fix passes 2 and 3 under the cap of 4. Scope 53 wasn't changed and still says "takes over code-review fixes from pass 3 on". That contradicts orchestrate and is the ambiguity this finding named. **Fix:** in scope 53, "…the agent that takes over a child's code-review fixes when its review isn't approved at pass 2…". Then re-render `dist/`.
- **TB-m3: fixed.** Review 23: "The list is the test budget, so check that it is complete and lean."

### New findings
#### TB2-m1 · minor · `skills/orchestrate/SKILL.md:102`: the escalation launch omits the E2E worker count (caused by the TB-M2 fix)
**Problem.** Step 2 (line 35) gives the implementer "its E2E worker count". `references/lanes.md:11` splits the machine-wide budget across lanes and passes each lane its count. Implement 33 runs E2E with "the E2E worker count your task gives". Line 102 gives the escalation implementer "the same plan, base commit and ledger" but no worker count. An escalated lane child that reruns E2E for its fixes then has no count, so it may oversubscribe the machine alongside the other lanes and the checkpoint run, and cause flakes.
**Fix.** Line 102: "…with the same plan, base commit, E2E worker count and ledger."

**Counts (pass 2, open):** 0 blocker, 0 major, 2 minor (TB-m2 in scope 53, TB2-m1). **Verdict:** approved.

### Author responses (test budget and escalation, pass 2)
- **TB-m2 fixed.** Scope's escalation field now reads "when pass 2 isn't approved".
- **TB2-m1 fixed.** The escalation launch passes the E2E worker count.

## group integration and review level, pass 1
Fresh review of `8cd3139` (skills only), treated as plan mode: is the process sound, complete, consistent, and runnable unattended. I read the §16 rulings as settled and judged only how the skill text carries them out. I read the full current text of orchestrate, `references/lanes.md`, `references/checkpoint-failures.md`, review, plan and implement. `node tools/render-skills.mjs --check` passes. The changed lines contain no product or repo names.

### GI1 · major · `references/lanes.md:25`; `orchestrate/SKILL.md:41, 62, 86, 25-27`: a partly integrated group has no defined Close timing
**Problem.** Lanes 25 lets a member still in code review be left out: "integrate the rest, and integrate it alone when it is approved". Orchestrate 41 runs Close steps 4–7 "once the group is integrated", but nothing says whether a group without its straggler counts as integrated. Checkpoints 86 can cause the same split: when a group straddles C+1 and C isn't green, the members past C+1 can't be integrated, and nothing says whether the whole group waits or only part of it integrates. If the orchestrator reads a partial integration as "integrated", it runs the last member's steps 4–7:
- it starts the checkpoint without the straggler;
- the post-group child refreshes and records its base without the straggler, although orchestrate 62 says it refreshes "after the last member is integrated";
- if that child is serial, it occupies the work-branch worktree. Orchestrate 25 and 27 then forbid merging there, so the straggler can't be integrated until that child closes, and a child that depends on the straggler is built without it.

**Fix.** In lanes 25, add: "The group counts as integrated, for Close steps 4–7 and orchestrate → Plan ahead, only when every member is. Integrating part of a group early only surfaces conflicts and red T1 sooner." Apply the same rule to the Checkpoints 86 case: either the whole group waits, or the members up to C+1 integrate and the rest follow under the straggler rule.

### GI2 · major · `references/lanes.md:26, 30`; `orchestrate/SKILL.md:14, 25, 41, 50`: resetting to the group base discards everything else committed to the work branch
**Problem.** Step 5 resets the work branch to the group base after a red T1. Between step 1 and the red result (several merges plus a T1 run that may take tens of minutes), the orchestrator may legitimately commit to the work branch:
- `state.json` and `epic.md`: orchestrate 14 says to update and commit after every step, and 25 says "at any time in lane mode". Recording the group base itself is one such commit.
- a waiting green checkpoint branch (Close step 3);
- the post-group child's plan branch (Close steps 1 and 6).

A hard reset drops those commits and reverts the only copy of `state.json` (orchestrate 25), including the integration-in-progress record that Recovery (orchestrate 18) depends on. The old procedure had the same hazard, but over a window of one merge and one T1.

**Fix.** In lanes 26: "Commit your own files first, then record the group base. Until the group is integrated, merge nothing else into the work branch, and leave your own files uncommitted." In step 5: "Before resetting, save `state.json` and `epic.md`, and restore them afterwards." An alternative is to merge onto a temporary integration branch at the work-branch tip and fast-forward the work branch only once the group is green.

### GI3 · major · `references/lanes.md:28-31`: the conflict and red-T1 paths never reach "integrated"
**Problem.** Only step 3 declares a group integrated, and only for "clean merges and green T1". After a conflict (step 4) or an integrator fix (step 5), nothing says:
- when the group is integrated. Is it green T1 alone, or green T1 plus an approved step 6 review?
- where step 6's review sits relative to the merges. Step 4 says "Then continue merging", so the resolved lane is already on the work branch before its review runs.
- what happens when that review finds a major. The integrator fixes it in its lane, but nothing says to merge the lane again and rerun the group T1.
- whether T1 reruns after step 5's "merge the group again". If the merges are clean, the tree matches the integrator's lane tip, where it already ran the group T1.
- what happens if T1 is red again. No cap applies; "the normal pass cap" in step 6 covers only the review.

An unattended orchestrator can declare the group done before the review approves, start a serial post-group child in the work-branch worktree, and then have no legal point to merge the review's fixes (orchestrate 27).

**Fix.** Add a final step: "The group is integrated when every lane has merged, the group T1 is green, and any integration review is approved. Review fixes are committed on the integrator's lane, then the lane is merged again and the group T1 rerun, unless the merged tree equals the integrator's lane tip and the integrator's T1 there was green. A second red T1 after an integrator fix counts as a pass toward the cap of 4."

### GI4 · major · `references/lanes.md:31`; `review/SKILL.md:29`: the integration review has no diff range
**Problem.** Code mode reviews "the child's diff (from the base commit you were given)". Step 6 says the reviewer sees "only the integrator's changes" but names no base or range. Neither obvious base works:
- **Conflict (step 4):** the resolution lives inside the merge commit. A diff from the work-branch commit shows the whole member; a diff from the old lane tip shows every earlier member. Neither isolates the resolution.
- **Red T1 (step 5):** the integrator's fix sits on top of merges of the other lanes. A diff from its lane base shows the whole group.

The old text gave a base ("from the work-branch commit before the merge"). Without one, the reviewer either reviews whole members again, which is the cost §16 removes, or guesses.

**Fix.** Lanes step 6: "The integrator's `## integration` entry names its range: for a conflict, the merge commit, reviewed as `git show --remerge-diff <merge>` (or the resolved paths against an automatic merge); for a fix, the commit after its last merge of the other lanes, as the base. The reviewer gets that range."

### GI5 · minor · `implement/SKILL.md:52-56`; `references/lanes.md:29-30`: the integrator instructions don't match either integrator case
**Problem.** Implement 54–55 tells every integrator to "run T1 plus any failing tests" and "add the path T1 missed to the test map". Under the new procedure:
- **Conflict:** the group T1 runs after the merges, so the integrator's own T1 is duplicate work, and it runs from its old lane base, so it selects the other members' changes as well. No T1 missed anything.
- **Red T1:** the integrator must run *the group's* T1 against the group base. Lanes 30 doesn't tell the orchestrator to give it the group base as its new base (implement 52).

**Fix.** In lanes 29–30, state each task: "conflict: resolve and commit only; the group T1 follows" and "red T1: new base is the group base; run the group T1 and add the path the members' T1 missed to the test map". Implement 52–56 can then just defer to the task.

### GI6 · minor · `references/lanes.md:27`: the group T1 isn't defined, though it is now the only integration check on the clean path
**Problem.** "One T1 … covering every member's changes" doesn't say:
- that it is the union of the members' Gates: each plan's scenario specs and the smoke set (plan 32), whole-package reruns, and any member's widening or escalation;
- which E2E worker count it uses (lanes 11 splits the budget between lanes and the checkpoint run);
- how a failure is triaged before it counts as red. Implement 38's flake and baseline rules bind the implementer, not a helper.

A helper that selects only from the diff and the test map leaves out sibling scenario specs. That is exactly where one member breaking another shows up. A flake would trigger step 5's reset and integrator for nothing.

**Fix.** "The group T1 is the union of the members' Gates commands, with selection computed from the group base. Widening or escalation by any member applies to the group. Pass it an E2E worker count. A failure that passes alone and is outside the group's diff, or that is in the baseline, is not red (implement → Gates)."

### GI7 · minor · `orchestrate/SKILL.md:48`; `plan/SKILL.md:56`; `review/SKILL.md:28, 46`: the refresh review's trigger and second pass are loosely specified
**Problem.**
- Line 48 reads "if the design or estimate changed, resize first if it is now over the size limit. Otherwise one fresh reviewer…". "Otherwise" can bind to the outer condition, which would mean reviewing only unchanged refreshes. "First" suggests a review also follows a resize.
- The second-pass trigger needs "changed scope" and the size of the estimate change. Plan 56's reply reports neither, so the orchestrator has to read the plan.
- "Changed scope" isn't defined. Going beyond the entry is already a major (review 21), and a scope change is a stop (orchestrate 119).
- What a second pass covers is undefined: the fix commits, or the refresh again.
- The refresh pass's ledger heading and pass number are undefined. If a refresh reviewer counts its pass as pass 1, review 46's "Pass 1 is the deep pass: be complete" pulls against "review only the refresh commit".

**Fix.**
- Orchestrate 48: "If only names and paths changed, no review. Otherwise, if the plan is now over the size limit, resize. If not, one fresh reviewer reviews the refresh commit only…".
- Plan 56: the reply gives the old and new estimate, and says whether Changes, claims or scenarios changed.
- Name the second pass's scope: the plan-author's fix commits.
- Review 28: head refresh passes `## plan refresh pass N`. The deep-pass rule doesn't apply to them.

### GI8 · minor · `orchestrate/SKILL.md:36, 48`; `review/SKILL.md:29-41`: nothing tells code review to verify the refresh majors, or what to do if a fix is wrong
**Problem.** Line 48 names the fixed refresh majors in the implementer's task "for code review to verify". The code reviewer's launch (line 36) gets only the directory and base commit, and code mode says nothing about refresh findings. The generic Earlier passes rule covers it only if the reviewer treats plan-mode findings as its own to verify. Nothing says what happens when the plan-author's fix is itself wrong. Code mode judges code against `plan.md`, so a wrong fix can be built faithfully and approved. The route for a plan change at that point is a fresh plan-author (orchestrate 66), and nothing connects that route to this case.

**Fix.** Orchestrate 36: "…and the IDs of any fixed refresh majors." Review code mode: "Verify each named refresh major in `plan.md` and in the code. A fix that is wrong against the integrated code is a major against the plan, and its plan change goes to a fresh plan-author (orchestrate → Plan ahead)."

### GI9 · minor · `review/SKILL.md:23, 25, 46`: the post-pass-1 list doesn't say where test-budget and T1 issues fall
**Problem.** Line 46 limits new plan majors after pass 1 to "design, boundaries, claims, scope or size", and calls "a fix's test mechanics" minors. Line 23, however, treats some Tests-list issues as contract-level rather than mechanics: a missing contract, the wrong layer, a contract another test already owns. Line 25 adds T1 selection and widening. After pass 1, a reviewer can't tell whether a fix that drops an authorization contract, or adds a migration without widening T1, may be a major: it is neither "mechanics" nor in the list. Two reviewers will grade it differently. Under §16's evidence, these should probably be minors, except where they are boundaries.

**Fix.** Line 46: "…must concern design, boundaries (including a missing contract for authorization, visibility or data integrity), claims, scope or size. Other Tests-list and T1 findings after pass 1 are minors."

### GI10 · minor · `plan/SKILL.md:52`; `review/SKILL.md:28`: refresh inputs still name one previous child
**Problem.** Plan Refresh step 2 checks against "the previous child's diff and ledger". For the child after a group, orchestrate 62 makes it refresh against every member. The refresh reviewer must check fit with "the code that was integrated since it was approved", but it is given only the refresh commit, not that range.

**Fix.** Plan 52: "the previous child's (or every group member's) diff and ledger". Orchestrate 48: pass the reviewer the plan-approval commit and the merge commit from Refresh step 1, as the integrated range.

### GI11 · minor · `orchestrate/SKILL.md:15-18`; `references/lanes.md:26`: state has no slot for a group integration
**Problem.** Lanes 26 says "Record the … group base", but State (orchestrate 15–16) has per-child phases and root records, and no group integration. That leaves nowhere to record:
- the group base;
- which members have merged;
- the integrator and integration-review run ids;
- the start and end times.

Recovery after compaction or a crash in the middle of an integration (orchestrate 18) needs these: which lanes are merged, and where to reset. So does §16's measure, "integration minutes per group".

**Fix.** State, at the root: "groups: members, base, merged members, T1 run, integrator and review runs, start and end".

### Not raised
- Dropping the review after clean merges and green T1 is the owner's ruling. Its residual risk: textual merges of the merge-friendly files that compile but are semantically wrong (duplicate keys, registry order), and one member breaking a sibling's behavior outside the group T1. Only checkpoints and the epic-diff review catch these. GI6 narrows the second.
- Compaction at Close step 7 fits overlapping lanes: lanes run one group at a time, and step 7 runs once per group, after it is integrated (it is skipped for siblings). GI1 is the only case where "integrated" is unclear.

**Counts (pass 1, open):** 0 blocker, 4 major (GI1–GI4), 7 minor (GI5–GI11). **Verdict:** changes needed.

### Author response: pass 1
- **GI1, GI2, GI3, GI4, GI6:** `lanes.md` → Integrating is rewritten.
  - A group integrates only when every member is approved and the checkpoint rule allows all of them, and no member counts as integrated before that. The straggler option is dropped.
  - Merges go onto `integration/<group>` at the work-branch tip, in the checkpoint worktree or a free pool worktree. The work branch never resets; it takes the integration branch once the group is integrated (GI2).
  - Each path now ends in an explicit "integrated" condition (step 6). Review fixes go on the integrator's lane, which is merged again with T1 rerun, and a red T1 after a fix counts toward the cap (GI3).
  - The review range is named: `--remerge-diff` of the merge for a conflict, and merged commit to lane tip for a fix (GI4).
  - The group T1 is the union of the members' Gates from the group base, with a worker count and the flake and baseline rule (GI6).
- **GI5:** the lanes tasks say what each integrator runs. `implement` defers to the task: by default it runs T1 "unless the task says another run follows", and the ledger records the commits a reviewer needs.
- **GI7:**
  - Orchestrate step 6 now reads: names and paths only means no review; over the limit means resize; otherwise one refresh review. A second pass covers the fix commits only, and runs if Changes, claims or scenarios changed, or the estimate moved by more than 20%.
  - The plan's reply gives the old and new estimate and those three flags.
  - Refresh passes are headed `## plan refresh pass N`, and the deep-pass rule doesn't apply to them.
- **GI8:** the code reviewer gets the IDs of the fixed refresh majors. Code mode verifies them; a wrong fix is a major against the plan and goes to a fresh plan-author.
- **GI9:** boundaries include a missing contract for authorization, visibility or data integrity. Other Tests-list and T1 findings after pass 1 are minors.
- **GI10:** Refresh checks against every group member's diff. The refresh reviewer gets the integrated range: the plan's approval commit to the Refresh step 1 merge.
- **GI11:** state gets a root `groups` record.

## group integration and review level, pass 2
Fresh review of `8cd3139` plus `6c415c4`, skills only, in plan mode. I read the §16 rulings as settled. I verified each pass-1 finding against the current text of orchestrate, `references/lanes.md`, `references/checkpoint-failures.md`, review, plan and implement, not against the author response. `node tools/render-skills.mjs --check` passes, and the changed lines stay generic.

### Pass-1 findings
- **GI1 (major): fixed.** Lanes 25 integrates only when every member is approved and Checkpoints step 2 allows all of them, and no member counts as integrated before that. Orchestrate 41 and 62 agree. The fix causes GI15.
- **GI2 (major): fixed.** The work branch is never reset: merges go onto `integration/<group>` (lanes 27–28). The final merge back causes GI12.
- **GI3 (major): fixed.** Lanes 33 defines "integrated". Review fixes go on the integrator's lane, which is merged again with T1 rerun (32). A red T1 after a fix counts toward the cap (31).
- **GI4 (major): fixed.** Lanes 32 names both ranges. GI16 covers a small gap in later passes.
- **GI5 (minor): fixed.** Each integrator task says what it runs (lanes 29, 31). Implement 52–56 defers to the task.
- **GI6 (minor): fixed.** Lanes 30 defines the group T1: the union of the members' Gates, selection from the group base, widening and escalation, a worker count, and the flake and baseline rule.
- **GI7 (minor): fixed.** Orchestrate 48 now orders the trigger correctly and scopes the second pass to the fix commits. Plan 56 reports the estimates and flags. Review 28 names the heading and drops the deep-pass rule. The new trigger wording causes GI14.
- **GI8 (minor): fixed.** Orchestrate 36 and review 33 cover it.
- **GI9 (minor): fixed.** Review 47 covers it.
- **GI10 (minor): fixed.** Plan 52 and the integrated range in orchestrate 48 cover it.
- **GI11 (minor): fixed.** Orchestrate 16 adds the `groups` record. GI13 adds the worktree to it.

### GI12 · major · `references/lanes.md:33`; `orchestrate/SKILL.md:27, 41, 77`: the final merge into the work branch can conflict, and the merged tree is never checked (caused by the GI2 fix)
**Problem.** Step 6 merges the integration branch into the work branch. That is a fast-forward only if the work branch hasn't moved since step 1, but it can move during an integration:
- Orchestrate 14 and 25 commit `state.json` as you go, and lanes 27 records every step. These commits don't conflict, because no lane touches those files.
- A checkpoint that turns green during the integration is merged "at the next clean point". Orchestrate 27 makes that "any time in lane mode". This is reachable: a group whose members are all at or before C+1 may integrate while checkpoint C runs (Checkpoints 86). Its merge brings in the base branch and any checkpoint fixes.

The integration branch then merges into a work branch that holds code it was never tested against. If that merge conflicts, no rule owns it:
- the lanes steps end at step 6;
- Checkpoints step 2's conflict path covers merging the checkpoint branch, not this merge.

An unattended orchestrator is left at a conflicted merge in the work-branch worktree.

**Fix.** In lanes 27, add: "From step 1 until step 6, merge only your own files into the work branch. A green checkpoint waits, and Close step 3 merges it afterwards." In orchestrate 27, change "at any time in lane mode" to "at any time in lane mode, except during a group integration". Close step 3 already merges the waiting checkpoint after the group, and Checkpoints step 2 already owns that merge's conflicts.

### GI13 · major · `references/lanes.md:20-22, 27`; `orchestrate/SKILL.md:16, 26`: the integration worktree may be unavailable, and is neither prepared nor given its own environment (caused by the GI2 fix)
**Problem.** Lanes 27 says to use "the checkpoint worktree when no checkpoint runs there, otherwise a free pool worktree". Four gaps:
- **No free worktree.** By lanes 20, a pool worktree can't be reused while its child isn't integrated, and during an integration no member is. If the pool has only `maxLanes` worktrees and a checkpoint is still running, which is likely right after a checkpoint placed before a fan-out, no worktree qualifies. The text gives no fallback.
- **"Runs" is ambiguous.** A green checkpoint branch that hasn't merged yet still needs the checkpoint worktree: Checkpoints step 2's conflict path resolves there. If the integration takes the worktree first, two writers share it.
- **No preparation.** The chosen worktree last held a checkpoint branch, which included a base-branch merge, or another child. Unlike reused pool worktrees (lanes 17–19), nothing says to reinstall when the lockfile changed or to reset the test data before the group T1.
- **No environment.** Lanes 22 binds only lane tasks. The group T1 helper inherits the orchestrator's environment, and so the ports of the work-branch worktree, and maybe the ports of a concurrent checkpoint run. A run against another worktree's server is stale code passing tests, the false green that `a7c7a40` fixed for lanes.

Recovery (orchestrate 18) also needs to know which worktree holds the integration, but the `groups` record doesn't say.

**Fix.** In lanes 27, replace the worktree sentence with: "Use the checkpoint worktree if it holds no checkpoint branch that is running or waiting to merge. Otherwise use a pool worktree that is clean and holds no unintegrated child. If neither exists, wait. Prepare it as The pool says, and give every task there that worktree's environment and ports." Add "worktree" to the `groups` record in orchestrate 16.

### GI14 · minor · `orchestrate/SKILL.md:48`: the second refresh pass runs on almost every reviewed refresh (caused by the GI7 fix)
**Problem.** A refresh reaches review only when more than names and paths changed. In practice that almost always means `Changes` changed, and `Changes` is now a trigger for the second pass. So the second pass becomes the default whenever the first pass finds majors. §16 limits it to a change of scope, or of the estimate by more than 20%. Scope means the entry, its scenarios and its claims, not the Changes section. Also, nothing says what happens to majors found in the second pass.

**Fix.** Change the trigger to "only if claims or scenarios changed, or the estimate moved by more than 20%". Add: "Its majors are handled like the first pass's."

### GI15 · major · `references/lanes.md:25`; `orchestrate/SKILL.md:41-42, 86`: a checkpoint after a group member that isn't last in the group deadlocks (caused by the GI1 fix)
**Problem.** Scope 75 keeps grouping and checkpoints independent, and scope 46–50 places checkpoints after children that widen T1, which a group member can do. Take a group {C, C+1, C+2} with a checkpoint after C. The two rules then wait on each other:
- Lanes 25 integrates the group only when Checkpoints 86 allows every member, so not until C is green and merged, because C+2 is after C+1.
- C's checkpoint starts at Close step 4, which for a lane child runs only after the group is integrated (orchestrate 41).

Before the fix, the straggler rule let part of the group integrate.

**Fix.** In lanes 25, add: "A checkpoint named after a group member runs after the group's last member, and the members are numbered as one step for Checkpoints 85–86." Alternatively, have scope place checkpoints only at group boundaries, and have orchestrate move any such checkpoint and record it under Decisions.

### GI16 · minor · `references/lanes.md:29-32`: integration-review details for later passes and multiple integrators (caused by the GI3 and GI4 fixes)
**Problem.**
- The conflict range, `--remerge-diff <merge>`, doesn't include the review-fix commits that step 5 adds, so pass 2 has no range for them.
- A group can have two integrators, for example a conflict in one member and a red T1 traced to another. Step 5 speaks of "the integrator's range" and "the integrator's lane" in the singular.
- The review appends `## code pass N` to a member's ledger, which already holds that child's code passes. Nothing says how integration passes are named or counted against the cap.

**Fix.** In step 5: "The reviewer gets every integrator's range, plus any review-fix commits since the last pass. Fixes go on the lane the finding is about. Head passes `## integration pass N`."

### Not raised
- The group T1's E2E worker count isn't in lanes 11's split. The members are idle during integration, so their share is free. This is a nit.

**Counts (pass 2, open):** 0 blocker, 3 major (GI12, GI13, GI15), 2 minor (GI14, GI16). GI1–GI11 are fixed. **Verdict:** changes needed.

### Author response: pass 2
All five are fixed as suggested.
- **GI12:** while a group integrates, only the orchestrator's own files reach the work branch. A green checkpoint waits for Close step 3. Orchestrate's Where work runs carries the exception.
- **GI13:**
  - The worktree rule is now explicit: the checkpoint worktree only if it holds no running or waiting checkpoint branch, otherwise a clean pool worktree with no unintegrated child, otherwise wait.
  - The worktree is prepared as The pool says, and every task there gets that worktree's environment and ports.
  - The `groups` record names the worktree.
- **GI14:** the second-pass trigger is claims or scenarios, or an estimate move of more than 20%. Its majors are handled like the first pass's. The plan's reply flags match.
- **GI15:** a checkpoint named after a group member runs after the group's last member, and the group counts as one child for Checkpoints step 2.
- **GI16:** the review gets every integrator's range plus review-fix commits since the last pass. Passes are headed `## integration pass N` in the ledger of the member concerned, and fixes go on the lane the finding is about.
