---
name: orchestrate
description: Run an approved epic or plan to completion without supervision. Plan and implement each child through fresh-review loops using subagents, while keeping your own context small. Use after `scope` approval.
compatibility: pi
---

# Orchestrate

You drive the work; you don't do it. Planners plan, implementers build, fresh reviewers judge, and the oracle breaks ties. You sequence them, keep state, bound them, and decide when to stop. Run until done or until a stop condition fires.

Agents: `plan-author`, `implementer`, `reviewer`, `oracle`, plus the fast `helper` and `researcher`. Launch them in the background and wait for completion.

## State
`state.json` in the plan directory is your memory. Update it after every step, and commit it when Where work runs allows; every resume returns a new run id, so record it each time.
- **Per child:** status, lane, estimate, base commit, the latest planner and implementer run ids, review pass counts, the start and end of each phase and of each checkpoint stop, and reported usage.
- **At the root:** the baseline gate digest, checkpoints (commit, status, run), regressions (culprit, test, the tier that caught it, what T1 missed), flakes (test, sightings), and stops (child, reason, time).

On start, after compaction, or after a crash: read `state.json`, `git status` in every worktree in use, `git log`, and the live run list, then resume whatever was in flight.

## Where work runs
One writer per worktree at any time.
- **Serial children:** run in the work branch's worktree.
- **Lanes:** see `references/lanes.md`.
- **Planning ahead:** in the planning worktree (see Plan ahead).
- **Your own files** (`state.json`, `epic.md`): the only current copy is in the work-branch worktree. Pass that path to every session, including those in other worktrees. While a serial child's implementer or code reviewer is running, write these files but run no git commands there. Commit them at Close step 1, or before a merge into a stopped child. Otherwise, commit them as you go.
- **Checkpoint work:** the base merge, gate runs, triage, bisects, fixes and rechecks all happen only in the checkpoint worktree. If the repo has none, run the checkpoint between children, on the critical path.
- **Merging into the work branch:** only when no one is writing there, and its tree is clean once you have committed your own files. That means between serial children, while a child stopped by the checkpoint-failures steer is waiting, or at any time in lane mode.
- **Merging into an unfinished child:** this happens to a stopped serial child, or to a paused lane that merges the work branch. The child's new base is the incoming commit: the green checkpoint tip, or the work-branch commit merged. Its old base is always an ancestor of that commit. Record the new base and give it to the resumed implementer, so T1 and code review still see only the child's own changes.
- **Resumed sessions** keep their original worktree. Work that must happen elsewhere gets a fresh session, given the plan and ledger it needs.

## Per child
1. **Plan**, ahead of time where possible (see Plan ahead). Spawn a `plan-author` (`plan` skill) with the paths to `epic.md`, the child's entry, `PROTOTYPE.md` and the previous child's directory. It writes `NN_slug/plan.md` and replies. Then loop:
   - Spawn a fresh `reviewer` (`review` skill, plan mode) with the plan directory.
   - Approved: copy the plan's Follow-ups into `epic.md`, then go to step 2. Otherwise resume the same plan-author with the ledger path and pass number.
2. **Implement.** Spawn an `implementer` (`implement` skill) with the child's directory, its base commit and its E2E worker count. It builds everything, passes T1, commits, writes its ledger entry and replies. Then loop:
   - Spawn a fresh reviewer (`review` skill, code mode) with the child's directory and base commit.
   - Approved: step 3. Otherwise resume the same implementer with the ledger path and pass number.
3. **Close**, in this order:
   1. Commit your files. If the next child was planned ahead, merge the plan branch.
   2. Mark the child done. Move follow-ups into `epic.md` Follow-ups; file tracker items only if the epic pre-authorized it.
   3. A serial child is already on the work branch. A lane child merges as `references/lanes.md` says. Merge any green checkpoint branch that is waiting (Checkpoints step 2).
   4. If this was the last child before a checkpoint, start the checkpoint.
   5. Note anything that changes later children, and adjust their epic entries if the change stays within scope. Commit the state.
   6. Plan the next child. Skip steps 6 and 7 when the next child is a sibling in the same parallel group: it is already running.
      - **If it was planned ahead:**
        - wait for its plan loop to be approved;
        - resume its plan-author to refresh (`plan` → Refresh);
        - if the design or estimate changed, re-enter step 1's review loop with a fresh reviewer, starting a new pass count, and resize first if it is now over the size limit.
      - **Otherwise:** run its plan loop now (step 1).
      - Either way, plan loops run in the planning worktree, except for parallel-group members, which plan in their lane worktrees. Merge the plan branch when the loop is done.
   7. Record the next child's base commit (after its plan has merged), and commit the state. `self_compact`, with a note naming the next child.

**Single plan:**
1. Run step 2.
2. A helper runs the full gates once on the final tree. Failures go back to the same implementer, inside the normal loop.
3. Commit your files, then hand to the PR process.

## Plan ahead
Plan the next child while the current one is being implemented. This is the default; plan only one child ahead.
- **When:**
  - If child N and child N+1 are both serial, start N+1's plan loop when N's implementer starts.
  - For the first child after a parallel group, start it when the group's last member starts implementing. Its plan-author works from every member's plan, and refreshes after the last member is integrated.
  - Group members plan in their lane worktrees (`references/lanes.md`).
- **Inputs:** the previous children's approved plans stand in for their code. Tell the plan-author and its reviewers so.
- **Where:** the planning worktree, created once with `git worktree add`, with no install. For each child, switch it to a new plan branch at the work-branch tip, but only when it is clean and the previous plan branch has merged. Plan-authors and plan reviewers launch there.
- **After a child's implementer starts,** plan changes for that child go to a fresh plan-author, not a resumed one: the old one's worktree has moved on.
- **Don't plan ahead** when N+1 depends on something N's plan leaves open, or when its plan-author reports that it can't plan yet. Plan it after N closes instead.

## Checkpoints
`epic.md` names them, and epic close is always one. You may move, add or drop any checkpoint except epic close; record why under Decisions.
1. **Run.**
   - In the checkpoint worktree, create the checkpoint branch from the work-branch commit, and merge the base branch into it, as the repo prescribes.
   - On a conflict, abort the merge. A fresh implementer then resolves it there, given the last child's plan and ledger.
   - After a disk check, a helper runs every gate with the given E2E worker count.
   - The next child goes on meanwhile.
2. **Green** means the full gates passed on the checkpoint branch's tip. Targeted reruns don't count.
   - **Merge** the green branch into the work branch at the next clean point (see Where work runs).
   - **On a conflict,** abort the merge, then:
     - **If a stopped serial child is in the work-branch worktree:** resume its implementer. It merges the green tip, resolves the conflict, and carries on. The resolution is part of its own diff from the new base, so its normal T1 and code review cover it.
     - **Otherwise:**
       1. a fresh implementer in the checkpoint worktree merges the work branch into the checkpoint branch and resolves the conflict there;
       2. it runs T1 for the conflicted paths and records `## checkpoint merge` in the last child's ledger;
       3. a fresh reviewer reviews only the conflicted paths;
       4. then merge again. The resolved tip counts as green; the next checkpoint's full run covers the rest.
   - The run for C+1 waits until C is green and merged.
   - No child after C+1 in child order may start (a serial child) or be integrated (a lane child) until C is green and merged.
3. **Failures:** follow `references/checkpoint-failures.md`.

## Epic close
1. Spawn a fresh reviewer on the whole diff (`review` skill, epic-diff mode). Findings go to the epic-root ledger.
2. The fixes go to the implementer of the last child in child order, in the work-branch worktree:
   - if that child ran serially, resume it;
   - if it ran in a lane, spawn a fresh implementer there, given that child's plan and ledger.

   It fixes the findings and runs T1 for the fixes.
3. Run the final checkpoint on the critical path.
4. Hand off to the PR process. Pushing and opening the PR need the epic's pre-authorization; otherwise stop.

## Bounds
- Every review is a new session. Every planner or implementer call resumes that child's session, except where this skill names a fresh one.
- A loop not approved after pass 4 stops.
- **Escalation:** if `epic.md` names an escalation implementer, and a child's own code review isn't approved at pass 2, its fixes go to a fresh escalation implementer. It runs where the child's implementer ran, with the same plan, base commit, E2E worker count and ledger. From then on it is the child's implementer: record its run id, and resume it for later passes. Integration and checkpoint fixes don't escalate.
- Every launch gets a deadline: planner and implementer from the child's budget in `epic.md`, reviewers and helpers shorter. The harness default is 30 minutes, which is far too short for an implementer.
- A child over its wall-time or cost budget stops. Its wall time is the sum of its active phases: plan loop, refresh and implement loop. Time spent waiting for the previous child, or stopped for a checkpoint (from the steer to the resume), doesn't count.

## Recovery
- If a run ends right after the child called `self_compact`, without a reply, treat it as a checkpoint. Resume it with "Continue from your note."
- A child that times out, crashes or hangs: resume it with "you were interrupted; check `git status` and the ledger, then continue". If resume is rejected, spawn a fresh session of the same role on the plan directory, and record the fallback.
- A dirty tree at the start of a step belongs to an interrupted session. Resume that session to commit or discard. Never commit code yourself. Your own files are the exception: they're yours to commit, and never to discard.
- An environment failure (service, port, disk, credentials) that survives the implementer's one retry is a stop, not a review pass.

## Sizing and scope
- **A planner that reports the child over the epic's size limit, or as trivially small:** split or merge it, as long as scope and acceptance scenarios are unchanged, and record it under Decisions. That is a resize, not a scope change.
  - The pieces become separate children (`NNa`, `NNb`), each with its own plan loop, review and close. Don't keep them inside one child.
  - Split into vertical slices, each ending in a scenario that can be tested.
- A discovery that invalidates a completed child: fold the rework into the current or next plan when scope holds, and record it. If it drops a scenario or contradicts the epic, stop.

## Stop for the human only when
- A discovery contradicts the agreed scope or a premise of the prototype, or the scope would change.
- An action is destructive or irreversible, or touches shared infrastructure, production data, or pushes and merges the epic did not pre-authorize.
- A loop hits its cap, a child exceeds its budget, or an environment failure persists.
- A gate failure can't be fixed and isn't in the baseline digest.
- The planner reports a course-setting decision where the oracle saw no clearly better option.

Otherwise, decide. Record tricky decisions in the `epic.md` Decisions section: the options, the choice, why, and whether the oracle was consulted. Record every stop in `state.json`.

## Do
- Pass paths, not pasted content. Subagents read files themselves.
- Keep what you take in small: verdicts, counts, paths and short summaries.
- Self-compact after each child, and whenever your context grows large.

## Don't
- Plan, implement or review yourself.
- Rerun gates the implementer already ran. The reviewer checks the evidence.
- Ask the human anything the oracle can answer.
