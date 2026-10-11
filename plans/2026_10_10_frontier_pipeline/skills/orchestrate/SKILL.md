---
name: orchestrate
description: Run an approved epic or plan to completion without supervision. Plan and implement each child through fresh-review loops using subagents, while keeping your own context small. Use after `scope` approval.
---

# Orchestrate

You drive the work; you don't do it. Planners plan, implementers build, fresh reviewers judge, and the oracle breaks ties. You sequence them, keep state, and decide when to stop. Run until done or until a stop condition fires.

## State
`state.json` in the plan directory is your memory. For each child it records:
- status and base commit;
- the latest planner and implementer run ids;
- the review pass counts.

Update it after every step. On start, or after compaction, read `state.json`, `git status` and `git log`, then continue.

## Per child
1. **Plan.** Spawn a planner (`plan` skill), passing the paths to `epic.md`, the child's entry, `PROTOTYPE.md` and the previous child's handoff. It writes `NN_slug/plan.md`, self-compacts and replies. Then loop:
   - Spawn a fresh reviewer (`review` skill, plan mode).
   - If it is approved, move to step 2.
   - Otherwise, resume the same planner with the findings.
2. **Implement.** Spawn an implementer (`implement` skill), passing `plan.md` and the planner's final handoff. It builds everything, passes the gates, commits, self-compacts and replies. Then loop:
   - Spawn a fresh reviewer (`review` skill, code mode).
   - If it is approved, move to step 3.
   - Otherwise, resume the same implementer with the findings.
3. **Close.**
   - Mark the child done.
   - Note anything that changes later children, and adjust their epic entries if the change stays within scope.
   - Commit the state.
   - `self_compact`, with a note naming the next child.

For a single plan, run only steps 2–3 and then the epic close.

## Epic close
1. Spawn a fresh reviewer on the whole diff (`review` skill, epic-diff mode).
2. Send its findings to the resumed implementer, which re-runs the full gates once.
3. Hand off to the PR process.

## Loops
- Every review is a new session.
- Every planner or implementer call resumes that child's session.
- The cap is 4 passes. If blockers are still open after pass 4, stop.

## Stop for the human only when
- A discovery contradicts the agreed scope or a premise of the prototype.
- The scope would change: adding, dropping or merging a child, or dropping an acceptance scenario.
- An action is destructive or irreversible, or touches shared infrastructure, production data, pushes or merges.
- A loop hits its cap, or a gate failure can neither be fixed nor shown to be pre-existing.
- A decision sets the course for much of the remaining work, and the oracle can't name a clearly better option.

Otherwise, decide. Record tricky decisions in the `epic.md` Decisions section: the options, the choice, why, and whether the oracle was consulted.

## Do
- Pass paths, not pasted content. Subagents read files themselves.
- Keep what you take in small: verdicts, counts, paths and short summaries.
- Self-compact after each child, and whenever your context grows large.

## Don't
- Plan, implement or review yourself.
- Rerun gates the implementer already ran. The reviewer checks the evidence.
- Ask the human anything the oracle can answer.
