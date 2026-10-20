---
name: orchestrate
description: Run an approved epic or plan to completion without supervision. Plan and implement each child through fresh-review loops using subagents, while keeping your own context small. Use after `scope` approval.
harnesses: [pi]
---

# Orchestrate

You drive the work; you don't do it. Planners plan, implementers build, fresh reviewers judge, and the oracle breaks ties. You sequence them, keep state, bound them, and decide when to stop. Run until done or until a stop condition fires.

Agents: `plan-author`, `implementer`, `reviewer`, `oracle`, plus the fast `helper` and `researcher`. Launch them in the background and wait for completion.

## State
`state.json` in the plan directory is your memory. Update it after every step, and commit it when Where work runs allows; every resume returns a new run id, so record it each time.
- **Per child:** status, lane, dependencies, estimate, budget, plan-branch cut commit, base commit, `readyAt` (when its last dependency integrated), lane start, scout outcome, the latest planner and implementer run ids, per review pass its start, end, reviewed commit and majors by kind, `planPass2Skipped`, `codePass2Skipped`, each T1 run (commit, tree, command lines, workers, runs in flight, result, duration, log path), the start and end of each phase and of each checkpoint stop, and reported usage.
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
1. **Plan** (see Planning). Spawn a `plan-author` (`plan` skill) with the paths to `epic.md`, the child's entry, `PROTOTYPE.md`, and the plans and ledgers of the children it depends on. It writes `NN_slug/plan.md` and replies. Set the child's provisional budget (`epic.md` → Budget). Then loop:
   - Spawn a fresh `reviewer` (`review` skill, plan mode) with the plan directory.
   - **Approved:** copy the plan's Follow-ups into `epic.md`, set the budget from the plan's estimate, and merge the plan branch into the work branch: with a pool, at once (or right after a running group integration); without one, between children, before this child's Start. The planning worktree is then free.
   - **Changes needed after pass 1:** resume the same plan-author with the ledger path and pass number. Skip pass 2 only when the reviewer replied `pass 2 needed: no`, and the plan-author fixed every major, rejected none, and reports that no fix changed a contract. Then append `approved after fixes, no pass 2` to the ledger, record it, and treat the plan as approved.
   - Otherwise resume the plan-author and review again.
2. **Start**, once the child's unit may start (`references/lanes.md` → Starting lanes; without a pool, when the previous child has closed):
   1. Prepare the lane worktree at the work-branch tip (without a pool: the work-branch worktree at its HEAD). That commit is the child's base; record it.
   2. **Scout.** A `helper` in that worktree compares the range from the plan-branch cut commit to the base, excluding the child's own directory, with every section of the plan; the child's `epic.md` entry, Decisions and Follow-ups; the ledgers of the children it depends on; and any checkpoint merge in the range. It appends `## refresh scout` to the child's ledger: per plan section, what changed, with paths; then `relevant` or `nothing relevant` (when unsure, `relevant`). It commits the ledger.
   3. **Nothing relevant:** go to Implement.
   4. **Relevant:** a fresh plan-author refreshes the plan in that worktree (`plan` → Refresh). One fresh reviewer reviews the refresh (`review` → Plan refresh), given the refresh commit and the scouted range. Its majors are fixed by the plan-author, and their IDs go to the implementer's code reviewer; other findings are notes for the implementer. A second refresh pass, on the fix commits only, runs only if claims or scenarios changed. Update the budget from the new estimate; above the review-load signal, see Sizing and scope.
3. **Implement.** Spawn an `implementer` (`implement` skill) with the child's directory and its base commit. It builds everything, passes the fast gates, records the rest of T1, commits, writes its ledger entry and replies. Then loop, in the child's worktree:
   1. Launch together, on the implementer's commit:
      - a fresh reviewer (`review` skill, code mode) with the child's directory and base commit, the IDs of any refresh majors fixed in its plan and, after pass 1, the range from the commit the previous pass reviewed to the implementer's tip, naming any merge in it;
      - a T1 helper with the ledger's recorded command lines and an E2E worker count (`references/lanes.md`). It boots and stops its own services, and reruns each failure alone: one that passes alone and lies outside the child's diff is a flake; one in the baseline digest or under a running checkpoint fix is baseline; anything else is red. It writes nothing tracked, and replies with a digest and the log path.
   2. Record the T1 run and any flakes in `state.json`.
   3. **Review approved and T1 green:** step 4. Otherwise resume the same implementer with the ledger path, the pass number and, if T1 is red, the digest and log path.
   4. Every fix pass counts toward the pass cap, including one for T1 failures alone. After a fix pass, the next review runs unless the reviewer replied `pass 2 needed: no`, the implementer fixed every major and rejected none, and every T1 fix touched only tests or fixtures. Then only the T1 helper runs; green means approved. Append `approved after fixes, no pass 2` to the ledger and record `codePass2Skipped`. A red T1 after fixes means another fix pass.
4. **Close:**
   1. Mark the child done. Move follow-ups into `epic.md` Follow-ups; file tracker items only if the epic pre-authorized it.
   2. Integrate its unit (`references/lanes.md` → Integrating); without a pool it is already on the work branch. Run the remaining steps once the unit is integrated. Merge any green checkpoint branch that is waiting (Checkpoints step 2).
   3. Start every checkpoint whose child, and every child it depends on, is now integrated.
   4. Note anything that changes later children, and adjust their epic entries if the change stays within scope. Commit the state.
   5. Start every unit that is now ready, and every plan loop that may now start. `self_compact` after an integration, with a note naming what is in flight: each running child, its phase and its run id.

**Single plan:**
1. Run step 3.
2. A helper runs the full gates once on the final tree. Failures go back to the same implementer, inside the normal loop.
3. Commit your files, then hand to the PR process.

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
4. A helper runs T1 for the fixes on the merged tip, with selection from the green checkpoint's tip, widened or escalated as `plan` → Gates says. That run is the fixes' evidence. Red goes back to the fixes' implementer, then T1 again.
5. Hand off to the PR process. Pushing and opening the PR need the epic's pre-authorization; otherwise stop.

## Bounds
- Every review is a new session. Every planner or implementer call resumes that child's session, except where this skill names a fresh one.
- A loop not approved after pass 4 stops.
- **Escalation:** if `epic.md` names an escalation implementer, and a child's own code review isn't approved at pass 2, its fixes go to a fresh escalation implementer. It runs where the child's implementer ran, with the same plan, base commit and ledger. From then on it is the child's implementer: record its run id, and resume it for later passes. Integration and checkpoint fixes don't escalate.
- Every launch gets a deadline: planner and implementer from the child's budget in `state.json`, reviewers and helpers shorter. The harness default is 30 minutes, which is far too short for an implementer.
- A child over its wall-time or cost budget stops. Its wall time is the sum of its active phases: plan loop, start (scout and refresh) and implement loop. Time spent waiting to start, or stopped for a checkpoint (from the steer to the resume), doesn't count.

## Recovery
- If a run ends right after the child called `self_compact`, without a reply, treat it as a checkpoint. Resume it with "Continue from your note."
- A child that times out, crashes or hangs: resume it with "you were interrupted; check `git status` and the ledger, then continue". If resume is rejected, spawn a fresh session of the same role on the plan directory, and record the fallback.
- A dirty tree at the start of a step belongs to an interrupted session. Resume that session to commit or discard. Never commit code yourself. Your own files are the exception: they're yours to commit, and never to discard.
- An environment failure (service, port, disk, credentials) that survives the implementer's one retry is a stop, not a review pass.

## Sizing and scope
- **A planner that proposes a split or a merge:** do it, as long as scope and acceptance scenarios are unchanged, and record it under Decisions with the new budgets. That is a resize, not a scope change.
  - **Split:** only when the child's concerns are separable and the pieces can run as parallel lanes, so only with a worktree pool. The pieces become separate children (`NNa`, `NNb`), each a vertical slice ending in a scenario that can be tested, with its own claim, plan loop, review and close. Write them into `epic.md` as a new group of their own, with the child's dependencies; it starts under the normal start rule. A split at Start releases the child's lane, and the rest of its old group integrates without it.
  - **Merge:** a child into the one it depends on, when their content belongs together; never a group member. The merged child keeps the first child's number, and its entry and scenarios are the union of both.
- A discovery that invalidates a completed child: fold the rework into the current or next plan when scope holds, and record it. If it drops a scenario or contradicts the epic, stop.

## Stop for the human only when
- A discovery contradicts the agreed scope or a premise of the prototype, or the scope would change.
- An action is destructive or irreversible, or touches shared infrastructure, production data, or pushes and merges the epic did not pre-authorize.
- A loop hits its cap, a child exceeds its budget, or an environment failure persists (including a unit that can't start, `references/lanes.md`).
- A gate failure can't be fixed and isn't in the baseline digest.
- The planner reports a course-setting decision where the oracle saw no clearly better option.

Otherwise, decide. Record tricky decisions in the `epic.md` Decisions section: the options, the choice, why, and whether the oracle was consulted. Record every stop in `state.json`.

## Do
- Pass paths, not pasted content. Subagents read files themselves.
- Keep what you take in small: verdicts, counts, paths and short summaries.
- Self-compact at clean points (Close step 5), and whenever your context grows large.

## Don't
- Plan, implement or review yourself.
- Rerun gates the implementer or a T1 helper already ran. The reviewer checks the evidence. A gate whose tree (ignoring your own files and plan directories) and exact command line match a passing run in the ledger or `state.json` is never rerun.
- Ask the human anything the oracle can answer.
