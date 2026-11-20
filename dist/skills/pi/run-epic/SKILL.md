---
name: run-epic
description: Run an approved epic of distinct plans to completion without supervision — for each child a plan loop with its own model, then the build loop of `run-plan`, with lanes, checkpoints and integration between them. Rare; use after `scope` approves an epic.
compatibility: pi
---

# Run epic

You drive the work; you don't do it. Planners plan, implementers build, fresh reviewers judge, and the oracle breaks ties. You sequence them, keep state, bound them, and decide when to stop. Run until done or until a stop condition fires.

Agents: `plan-author`, `implementer`, `reviewer`, `oracle`, plus the fast `helper` and `researcher`. Launch them in the background and wait for completion.

An epic is the rare case: distinct workstreams, each with its own plan and its own model. One plan is built with `run-plan`. This skill adds what crosses plans: units, lanes, checkpoints and integration. Each child is built by the **Build loop of `run-plan`**, run by you in the child's worktree; read that skill, and `architecture-model`, first.

**Untested with models.** No epic has run since plans gained a model. The steps marked *(open)* are settled only as far as written here; when one doesn't fit, stop for the human rather than improvise.

**Known gap.** The check counts changes from the child's approval commit, and can't take a later base. So what other children integrate between that commit and the child's base shows up in the child's results:
- in check 2, as unaccounted lines and as changes to reused elements;
- in check 3, as a re-approval stop for every catalog, rule or profile file another child changed. Every child that follows one proposing a pattern gets this.

Until the check takes a later base: tell the implementer, the code reviewer and the close helper that a result tracing to commits outside the child's own range (base to tip) is not theirs to fix. They list each in the ledger and change nothing to explain it. *(open)* If such a result is all that keeps the check from passing, stop for the human with the list.

## State
`state.json` in the plan directory is your memory. Update it after every step, and commit it when Where work runs allows; every resume returns a new run id, so record it each time.
- **Per child:** status, lane, dependencies, estimate, budget, approvals (date, commit, who approved), plan-branch cut commit, base commit, `readyAt` (when its last dependency integrated), lane start, scout outcome, the latest planner and implementer run ids, per review pass its start, end, reviewed commit and majors by kind, `planPass2Skipped`, `codePass2Skipped`, each T1 run (commit, tree, command lines, workers, runs in flight, result, duration, log path), the start and end of each phase and of each checkpoint stop, and reported usage.
- **At the root:** the baseline gate digest, checkpoints (commit, status, run), groups (members, worktree, base, merged members, T1 run, integrator and review runs, start and end), regressions (culprit, test, the tier that caught it, what T1 missed), flakes (test, sightings), stops (child, reason, time), and **launches**: every run when you launch it (run id, agent, child, phase, worktree, start), marked consumed when you have read its result.

**On start, after compaction, or after a crash,** reconcile: read `state.json`, `git status` in every worktree in use, and `git log`. Then check the status of every launch not yet consumed:
- **finished:** consume its result (its completion notice may have been lost);
- **still running:** wait for it;
- **dead:** resume a plan-author or implementer (Recovery). For a reviewer, scout or helper, discard its uncommitted ledger edit, then relaunch it fresh. Only plan-authors and implementers are resumed.

Never start a writer in a worktree whose last writer isn't confirmed stopped. Record each restart in `stops`.

## Where work runs
One writer per worktree at any time.
- **With a worktree pool, every child runs as a lane** (`references/lanes.md`): in its own pool worktree, on a lane branch cut from the work-branch tip. A child in no group is a group of one. The work-branch worktree holds only your own files, plan merges and integration merges.
- **Without a pool,** children run one at a time in the work-branch worktree, in child order. While a child's implementer, code reviewer or T1 helper is running there, write your own files but run no git commands; commit them between children or before a merge into a stopped child.
- **Planning:** in the planning worktrees (see Planning).
- **Your own files** (`state.json`, `epic.md`): the only current copy is in the work-branch worktree. Pass that path to every session, including those in other worktrees. Otherwise commit them as you go.
- **Checkpoint work:** the base merge, gate runs, triage, bisects, fixes and rechecks all happen only in the checkpoint worktree. If the repo has none, run the checkpoint between children, on the critical path.
- **Merging into the work branch:** only when no one is writing there, and its tree is clean once you have committed your own files. With a pool, that is any time except during a group integration; without one, between children or while a child stopped by the checkpoint-failures steer is waiting.
- **Merging into an unfinished child:** a paused lane that merges the work branch, or (without a pool) a stopped child. The child's new base is the incoming commit: the green checkpoint tip, or the work-branch commit merged. Its old base is always an ancestor of that commit. Record the new base and give it to the resumed implementer, so T1 and code review still see only the child's own changes.
- **Resumed sessions** keep their original worktree. Work that must happen elsewhere gets a fresh session, given the plan and ledger it needs.

## Per child
1. **Plan** (see Planning). Spawn a `plan-author` (`plan` skill) with the paths to `epic.md`, the child's entry, `PROTOTYPE.md`, the path file, and the plans, models and ledgers of the children it depends on. It writes `NN_slug/plan.md` and `NN_slug/model.c4ish.json`, and replies. Set the child's provisional budget (`epic.md` → Budget). Then loop:
   - Spawn a fresh `reviewer` (`review` skill, plan mode) with the plan directory.
   - **Review approved:** go to Approving a child's plan. Once the approval is recorded, copy the plan's Follow-ups into `epic.md`, set the budget from the plan's estimate, and merge the plan branch into the work branch: with a pool, at once (or right after a running group integration); without one, between children, before this child's Start. The planning worktree is then free.
   - **Changes needed after pass 1:** resume the same plan-author with the ledger path and pass number. Skip pass 2 only when the reviewer replied `pass 2 needed: no`, and the plan-author fixed every major, rejected none, and reports that no fix changed a contract. Then append `approved after fixes, no pass 2` to the ledger, record it, and treat the plan as approved.
   - Otherwise resume the plan-author and review again.
2. **Start**, once the child's unit may start (`references/lanes.md` → Starting lanes; without a pool, when the previous child has closed):
   1. Prepare the lane worktree at the work-branch tip (without a pool: the work-branch worktree at its HEAD). That commit is the child's base; record it.
   2. **Scout.** A `helper` in that worktree compares the range from the plan-branch cut commit to the base, excluding the child's own directory, with every section of the plan; the child's `epic.md` entry, Decisions and Follow-ups; the ledgers of the children it depends on; and any checkpoint merge in the range. It appends `## refresh scout` to the child's ledger: per plan section, what changed, with paths; then `relevant` or `nothing relevant` (when unsure, `relevant`). It commits the ledger.
   3. **Nothing relevant:** go to Implement.
   4. **Relevant:** a fresh plan-author refreshes the plan and the model in that worktree (`plan` → Refresh). One fresh reviewer reviews the refresh (`review` → Plan refresh), given the refresh commit and the scouted range. Its majors are fixed by the plan-author, and their IDs go to the implementer's code reviewer; other findings are notes for the implementer. A second refresh pass, on the fix commits only, runs only if claims or scenarios changed. Update the budget from the new estimate. A refresh records its model changes under Deviations (`plan` → Refresh). *(open)* A refresh that changes anything on the re-approval list is a re-approval: stop for the human with the tour of what differs (`c4ish diff`), send changes to the plan-author, and record `Re-approved:` before the build starts.
3. **Build.** Run `run-plan` → Build loop for this child, in its worktree, with the child's directory as the plan directory and the base recorded at Start. `run-plan`'s Start and Close don't apply: where the loop says Close, continue at step 4 here. In an epic, also:
   - the code reviewer gets the IDs of any refresh majors fixed in the plan, and any merge in its range is named;
   - the T1 helper's E2E worker count comes from `references/lanes.md` → E2E workers (which also applies without a pool), and a failure under a running checkpoint fix counts as baseline;
   - a re-approval stops only this child (`run-plan` → Re-approval). The `Re-approved:` line is committed in the child's worktree while its implementer is stopped. Other lanes go on.
   - when the loop approves the child, a `helper` reruns `c4ish validate --strict` and `model-check all` on its final commit; anything new goes back through the loop. *(open)* The child's approved-versus-shipped comparison and as-built tour are made at Epic close, for the PR.
4. **Close:**
   1. Mark the child done. Move follow-ups into `epic.md` Follow-ups; file tracker items only if the epic pre-authorized it.
   2. Integrate its unit (`references/lanes.md` → Integrating); without a pool it is already on the work branch. Run the remaining steps once the unit is integrated. Merge any green checkpoint branch that is waiting (Checkpoints step 2).
   3. Start every checkpoint whose child, and every child it depends on, is now integrated.
   4. Note anything that changes later children, and adjust their epic entries if the change stays within scope. Commit the state.
   5. Start every unit that is now ready, and every plan loop that may now start. `self_compact` after an integration, with a note naming what is in flight: each running child, its phase and its run id.

## Approving a child's plan
Who approves follows `epic.md` → Autonomy, with one exception: **a child whose plan changes the catalog (a proposed pattern, or a change to an entry, a rule or the profile) always stops for the human.**
- **The human approves:** stop for them with what `scope` → Approval gate gives: the tour command, the static pages, the link to `plan.md` and the short list. Changes go back to the same plan-author and through one more review.
- **Review alone approves** (the epic's Autonomy allows it, and the catalog is untouched): the clean plan review is the approval.

Either way, you record it, as `scope` → Recording the approval says: everything the approval relies on is committed on the plan branch, then `Approved: <date> <commit>` goes into the child's `plan.md` and into `state.json`, with who approved. *(open)* The approval commit is on the plan branch; it reaches the lane through the plan merge, so it is an ancestor of the lane's HEAD.

A pattern a child proposes must be the one `epic.md` → Proposed patterns claims for it. *(open)* One that isn't claimed is recorded under Decisions and claimed before the plan is approved; if another child's plan in flight proposes the same shape, order the two.

A child that uses a cross-plan contract copies it into its own model as reused. The owning child's copy wins: a change to it follows the owner's deviation class, and children that use it are refreshed.

## Planning
- **Worktrees:** up to three planning worktrees, created once with `git worktree add`, with no install. For each child, switch a clean one to a new plan branch at the work-branch tip, and record that commit as the child's plan-branch cut commit. Plan-authors and plan reviewers launch there. Every child plans here, group members included.
- **When:** a child's plan loop starts when every child it depends on has started implementing (at once if it has none). When more children qualify than worktrees are free, take the lowest-numbered.
- **Inputs:** a dependency that isn't built yet is represented by its approved plan. Tell the plan-author and its reviewers so.
- **Plan changes after approval** (refresh, resize, fixes from code review) go to a fresh plan-author in the child's worktree (its lane, or the work-branch worktree without a pool), not a resumed one: the old one's worktree has moved on.
- **Don't plan yet** when the child depends on something its dependency's plan leaves open, or when its plan-author reports that it can't plan yet. Plan it once that dependency is integrated.

## Checkpoints
`epic.md` names them, each after a child; epic close is always one. You may move, add or drop any checkpoint except epic close; record why under Decisions. Checkpoints don't hold back starting or integrating children.
1. **Run**, once the checkpoint's child and every child it depends on are integrated.
   - In the checkpoint worktree, create the checkpoint branch from the work-branch commit, and merge the base branch into it, as the repo prescribes.
   - On a conflict, abort the merge. A fresh implementer then resolves it there, given the last integrated child's plan and ledger.
   - After a disk check, a helper runs every gate with the given E2E worker count.
   - Children go on meanwhile.
2. **Green** means the full gates passed on the checkpoint branch's tip. Targeted reruns don't count.
   - **Merge** the green branch into the work branch at the next clean point (see Where work runs). Then start the next checkpoint if its child and every child it depends on are integrated.
   - **On a conflict,** abort the merge, then:
     - **If a stopped child is in the work-branch worktree** (no pool): resume its implementer. It merges the green tip, resolves the conflict, and carries on. The resolution is part of its own diff from the new base, so its normal T1 and code review cover it.
     - **Otherwise:**
       1. a fresh implementer in the checkpoint worktree merges the work branch into the checkpoint branch and resolves the conflict there;
       2. it runs T1 for the conflicted paths and records `## checkpoint merge` in the last integrated child's ledger;
       3. a fresh reviewer reviews only the conflicted paths;
       4. then merge again. The resolved tip counts as green; the next checkpoint's full run covers the rest.
   - The run for C+1 waits until C is green and merged.
3. **Failures:** follow `references/checkpoint-failures.md`.

## Epic close
1. Spawn a fresh reviewer on the whole diff (`review` skill, epic-diff mode). Findings go to the epic-root ledger. If a green checkpoint is waiting, merge it before the fixes start. Start the final checkpoint on the work-branch tip as soon as the previous checkpoint has merged; it runs alongside the review and the fixes.
2. The fixes go to the implementer of the last child integrated, in the work-branch worktree:
   - without a pool, resume it;
   - with a pool, spawn a fresh implementer there, given that child's plan and ledger.

   It fixes the findings, runs the fast gates and records the rest of T1 for the fixes; another run follows. A review of the fixes checks the recorded command lines.
3. Once the fixes are committed and no one is writing in the work-branch worktree, merge the green final checkpoint (Checkpoints step 2). A red one follows `references/checkpoint-failures.md`; the fixes go on meanwhile, and this step waits for the checkpoint fix to merge.
4. A helper runs T1 for the fixes on the merged tip, with selection from the commit the final checkpoint's full gates passed on, widened or escalated as `plan` → Gates says. That run is the fixes' evidence. Red goes back to the fixes' implementer, then T1 again.
5. Prepare the review record, per child, generated outside the repo tree: approved versus shipped against the child's first approval, with re-approved differences marked, and the as-built tour (`run-plan` → Close step 3).
6. Hand off to the PR process with those. Pushing and opening the PR need the epic's pre-authorization; otherwise stop.

## Bounds
- Every review is a new session. Every planner or implementer call resumes that child's session, except where this skill names a fresh one.
- A loop not approved after pass 4 stops. `run-plan` → Bounds applies to each child's build.
- **Escalation:** if `epic.md` names an escalation implementer, and a child's own code review isn't approved at pass 2, its fixes go to a fresh escalation implementer. It runs where the child's implementer ran, with the same plan, base commit and ledger. From then on it is the child's implementer: record its run id, and resume it for later passes. Integration and checkpoint fixes don't escalate.
- Every launch gets a deadline: planner and implementer from the child's budget in `state.json`, reviewers and helpers shorter. The harness default is 30 minutes, which is far too short for an implementer.
- A child over its wall-time or cost budget stops. Its wall time is the sum of its active phases: plan loop, start (scout and refresh) and implement loop. Time spent waiting to start, or stopped for a checkpoint (from the steer to the resume), doesn't count.

## Recovery
- If a run ends right after the child called `self_compact`, without a reply, treat it as a checkpoint. Resume it with "Continue from your note."
- A child that times out, crashes or hangs: resume it with "you were interrupted; check `git status` and the ledger, then continue". If resume is rejected, spawn a fresh session of the same role on the plan directory, and record the fallback.
- A dirty tree at the start of a step belongs to an interrupted session. Resume that session to commit or discard. Never commit code yourself. Your own files are the exception: they're yours to commit, and never to discard.
- An environment failure (service, port, disk, credentials) that survives the implementer's one retry is a stop, not a review pass.

## Sizing and scope
- **A child is never split to meet a size number.** A child above the review-load estimate is reviewed in groups (`run-plan` → Build loop).
- **A planner that reports distinct workstreams in one child, or proposes merging two children whose content is one design:** do it, as long as scope and acceptance scenarios are unchanged, and record it under Decisions with the new budgets. That is a resize, not a scope change.
  - **Divide:** only into parts with their own goal that could each be approved and shipped alone. The parts become separate children (`NNa`, `NNb`), each with its own claim, plan loop, model, approval and close.
  - **Merge:** a child into the one it depends on, when their content belongs together; never a group member. The merged child keeps the first child's number, and its entry and scenarios are the union of both.
- A discovery that invalidates a completed child: fold the rework into the current or next plan when scope holds, and record it. If it drops a scenario or contradicts the epic, stop.

## Stop for the human only when
- A child's plan needs their approval, or its build needs re-approval (`run-plan` → Re-approval). Only that child waits.
- A discovery contradicts the agreed scope or a premise of the prototype, or the scope would change.
- An action is destructive or irreversible, or touches shared infrastructure, production data, or pushes and merges the epic did not pre-authorize.
- A loop hits its cap, a child exceeds its budget, or an environment failure persists (including a unit that can't start, `references/lanes.md`).
- A gate failure can't be fixed and isn't in the baseline digest.
- The planner reports a course-setting decision where the oracle saw no clearly better option.

Otherwise, decide. Record tricky decisions in the `epic.md` Decisions section: the options, the choice, why, and whether the oracle was consulted. Record every stop in `state.json`.

## Do
- Pass paths, not pasted content. Subagents read files themselves.
- Keep what you take in small: verdicts, counts, paths and short summaries.
- Self-compact at clean points (Close step 5), and whenever your context grows large. Name this skill's path and `run-plan`'s in the note, and re-read both after compaction.

## Don't
- Plan, implement or review yourself, or edit a model.
- Write an approval line for an approval nobody gave: the human's, or a clean plan review where the epic allows it.
- Start a child orchestrator. Each child's Build loop runs in this session.
- Rerun gates the implementer or a T1 helper already ran. The reviewer checks the implementer's evidence; you read the T1 helper's digest. A gate whose tree (ignoring your own files and plan directories) and exact command line (ignoring the E2E worker count) match a passing run in the ledger or `state.json` is never rerun.
- Ask the human anything the oracle can answer.
