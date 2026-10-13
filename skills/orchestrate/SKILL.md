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
- **At the root:** the baseline gate digest, checkpoints (commit, status, run), regressions (culprit, test, the tier that caught it, what T1 missed), and stops (child, reason, time).

On start, after compaction, or after a crash: read `state.json`, `git status`, `git log`, and the live run list, then resume whatever was in flight.

## Per child
1. **Plan.** Spawn a `plan-author` (`plan` skill) with the paths to `epic.md`, the child's entry, `PROTOTYPE.md` and the previous child's directory. It writes `NN_slug/plan.md` and replies. Then loop:
   - Spawn a fresh `reviewer` (`review` skill, plan mode) with the plan directory.
   - Approved: step 2. Otherwise resume the same plan-author with the ledger path and pass number.
2. **Implement.** Spawn an `implementer` (`implement` skill) with the child's directory and base commit. It builds everything, passes the gates, commits, writes its ledger entry and replies. Then loop:
   - Spawn a fresh reviewer (`review` skill, code mode) with the child's directory and base commit.
   - Approved: step 3. Otherwise resume the same implementer with the ledger path and pass number.
3. **Close.**
   - Mark the child done. Move follow-ups the planner or implementer noted into `epic.md` Follow-ups; file tracker items only if the epic pre-authorized it.
   - Integrate the child into the epic branch. If the merge brought in other work, a helper runs the child's T1 on the merged tree. On conflicts or red gates, resume the implementer to resolve them. Record the new base commit.
   - After integrating the base branch, or the last child before a checkpoint, start the checkpoint.
   - Note anything that changes later children, and adjust their epic entries if the change stays within scope.
   - Commit the state. `self_compact`, with a note naming the next child.

For a single plan, run step 2, then hand to the PR process; the code review already saw the whole diff.

## Checkpoints
`epic.md` names them, and epic close is always one. You may add one after a child that widened T1; record it under Decisions.
- **Run:** a helper runs every gate in the background, in the reusable checkpoint worktree at the checkpoint commit. The next child goes on meanwhile, but no child starts past the next checkpoint until this one is green.
- **Triage** a failure that is not in the baseline and not a known flake: a helper reruns it alone, then bisects the commits since the last green checkpoint, running only the failing tests.
- **Route:**
  - if the running child builds on the broken code, pause it and resume the culprit's implementer to fix it;
  - otherwise, add the failure to the running child's ledger as a carried-over blocker.
- **Record** it in `state.json`, and add the path T1 missed to the test map.

## Lanes
Run up to `maxLanes` children of an `epic.md` parallel group at once. Each runs in a pool worktree, on its own branch off the same base, with its own loops.
- **Before a lane starts,** check free memory (about 6 GB per lane), disk, and the machine-wide E2E worker budget. On model rate-limit errors, drop a lane until the next group.
- **The pool** is created once with the repo's worktree tooling, then reused: a new branch at the base, a reinstall only if the lockfile changed, and reset test data. Never reuse a dirty worktree.
- **Integrate** lanes in child order. On a conflict or red T1, resume one implementer as integrator, with the other child's plan and ledger. A fresh reviewer checks the integration diff, in code mode.
- **Claims:** a plan that must break its claims runs serially, or is re-scoped under Decisions.

## Epic close
1. Spawn a fresh reviewer on the whole diff (`review` skill, epic-diff mode). Findings go to the epic-root ledger.
2. Send its findings to the resumed implementer of the last child. It fixes them and runs T1 for the fixes.
3. Run the final checkpoint: the full gates on the final tree, on the critical path.
4. Hand off to the PR process. Pushing and opening the PR need the epic's pre-authorization; otherwise stop.

## Bounds
- Every review is a new session. Every planner or implementer call resumes that child's session. One writer per worktree.
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
