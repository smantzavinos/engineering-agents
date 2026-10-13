---
name: orchestrate
description: Run an approved epic or plan to completion without supervision. Plan and implement each child through fresh-review loops using subagents, while keeping your own context small. Use after `scope` approval.
harnesses: [pi]
---

# Orchestrate

You drive the work; you don't do it. Planners plan, implementers build, fresh reviewers judge, and the oracle breaks ties. You sequence them, keep state, bound them, and decide when to stop. Run until done or until a stop condition fires.

Agents: `plan-author`, `implementer`, `reviewer`, `oracle`, plus the fast `helper` and `researcher`. Launch them in the background and wait for completion.

## State
`state.json` in the plan directory is your memory. Update and commit it after every step; every resume returns a new run id, so record it each time.
- **Per child:** status, lane, base commit, the latest planner and implementer run ids, review pass counts, phase timestamps, and reported usage.
- **At the root:** the baseline gate digest, checkpoints (commit, status, run), regressions (culprit, test, the tier that caught it, what T1 missed), flakes (test, sightings), and stops (child, reason, time).

On start, after compaction, or after a crash: read `state.json`, `git status`, `git log`, and the live run list, then resume whatever was in flight.

## Where work runs
One writer per worktree at any time.
- **Serial children:** run in the work branch's worktree.
- **Lanes:** see `references/lanes.md`.
- **Checkpoint work:** the base merge, gate runs, triage, bisects, fixes and rechecks all happen only in the checkpoint worktree. If the repo has none, run the checkpoint between children, on the critical path.
- **Merging into the work branch:** only when its worktree is clean and no one is writing there. That means between serial children, while a child stopped by the checkpoint-failures steer is waiting, or at any time in lane mode.
- **Merging into an unfinished child:** this happens to a stopped serial child, or to a paused lane that merges the work branch. A helper first creates the child's new base: its old base with the same incoming commit merged in, built detached in the checkpoint worktree. Record that base, so T1 and code review still see only the child's own changes.
- **Resumed sessions** keep their original worktree. Work that must happen elsewhere gets a fresh session, given the plan and ledger it needs.

## Per child
1. **Plan.** Spawn a `plan-author` (`plan` skill) with the paths to `epic.md`, the child's entry, `PROTOTYPE.md` and the previous child's directory. It writes `NN_slug/plan.md` and replies. Then loop:
   - Spawn a fresh `reviewer` (`review` skill, plan mode) with the plan directory.
   - Approved: step 2. Otherwise resume the same plan-author with the ledger path and pass number.
2. **Implement.** Spawn an `implementer` (`implement` skill) with the child's directory, its base commit and its E2E worker count. It builds everything, passes T1, commits, writes its ledger entry and replies. Then loop:
   - Spawn a fresh reviewer (`review` skill, code mode) with the child's directory and base commit.
   - Approved: step 3. Otherwise resume the same implementer with the ledger path and pass number.
3. **Close.**
   - Mark the child done. Move follow-ups into `epic.md` Follow-ups; file tracker items only if the epic pre-authorized it.
   - A serial child is already on the work branch. A lane child merges as `references/lanes.md` says. Merge any green checkpoint branch that is waiting (Checkpoints step 2). Record the new base commit.
   - If this was the last child before a checkpoint, start the checkpoint.
   - Note anything that changes later children, and adjust their epic entries if the change stays within scope.
   - Commit the state. `self_compact`, with a note naming the next child.

**Single plan:**
1. Run step 2.
2. A helper runs the full gates once on the final tree. Failures go back to the same implementer, inside the normal loop.
3. Hand to the PR process.

## Checkpoints
`epic.md` names them, and epic close is always one. You may move, add or drop any checkpoint except epic close; record why under Decisions.
1. **Run.**
   - In the checkpoint worktree, create the checkpoint branch from the work-branch commit, and merge the base branch into it, as the repo prescribes.
   - On a conflict, abort the merge. A fresh implementer then resolves it there, given the last child's plan and ledger.
   - After a disk check, a helper runs every gate with the given E2E worker count.
   - The next child goes on meanwhile.
2. **Green** means the full gates passed on the checkpoint branch's tip. Targeted reruns don't count.
   - **Merge** the green branch into the work branch at the next clean point (see Where work runs).
   - **On a conflict:**
     1. abort the merge;
     2. a fresh implementer in the checkpoint worktree merges the work branch into the checkpoint branch and resolves the conflict there;
     3. it runs T1 for the conflicted paths and records `## checkpoint merge` in the last child's ledger;
     4. a fresh reviewer reviews the resolution (code mode, from the checkpoint branch's tip before the merge);
     5. then merge again. The resolved tip counts as green; the next checkpoint's full run covers the rest.
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
- Every launch gets a deadline: planner and implementer from the child's budget in `epic.md`, reviewers and helpers shorter. The harness default is 30 minutes, which is far too short for an implementer.
- A child over its wall-time or cost budget stops.

## Recovery
- If a run ends right after the child called `self_compact`, without a reply, treat it as a checkpoint. Resume it with "Continue from your note."
- A child that times out, crashes or hangs: resume it with "you were interrupted; check `git status` and the ledger, then continue". If resume is rejected, spawn a fresh session of the same role on the plan directory, and record the fallback.
- A dirty tree at the start of a step belongs to an interrupted session. Resume that session to commit or discard. Never commit code yourself.
- An environment failure (service, port, disk, credentials) that survives the implementer's one retry is a stop, not a review pass.

## Sizing and scope
- A planner that reports the child as too large or too small: split or merge children yourself when scope and acceptance scenarios are unchanged, and record it under Decisions. That is a resize, not a scope change.
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
