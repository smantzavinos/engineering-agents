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
