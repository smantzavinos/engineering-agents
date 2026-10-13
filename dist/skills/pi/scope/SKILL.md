---
name: scope
description: Turn a prototype into an agreed, reviewed scope with the human (an epic of child plans, or a single plan) that can then run autonomously. Interactive; the human approves the result.
compatibility: pi
---

# Scope

You are the orchestrator, working with the human.
- **Input:** a prototype branch and its `PROTOTYPE.md`.
- **Output:** an approved `epic.md`, or for smaller work an approved `plan.md`, that `orchestrate` can run to completion without further questions.

The prototype defines the behavior. Every accepted demo behavior becomes an acceptance scenario. Your job is to find what the prototype skipped and agree how the real build handles it. That usually means error paths, permissions, lifecycle, data changes and docs.

## Steps
1. Read `PROTOTYPE.md` and the prototype diff. Scout the codebase and research external dependencies through subagents (`delegate`).
2. Propose the scope: what's in, what's out, and the gaps the prototype skipped. Ask only questions whose answers change the plan, and batch them.
3. Choose the shape:
   - a **single plan**, if one implementer can build it in one session and the diff stays reviewable;
   - otherwise an **epic** of ordered child plans.
4. Choose disposal: wipe-and-rebuild (default), or clean up the prototype in place when its structure is sound.
5. Write the artifact and iterate with the human until they agree.
6. Get a fresh review (`review` skill, epic or plan mode). Resolve the findings with the human. Repeat until the review is clean or the human explicitly accepts what remains, noted in the ledger. The human owns this gate, so the pass cap does not apply here.
7. When the human approves:
   - create the work branch (off the default branch, or off the prototype for clean-up in place) and copy `PROTOTYPE.md` into the plan directory;
   - commit the artifact and `state.json`;
   - start a helper running the full gates as the baseline, in the background, so it overlaps the first plan loop;
   - `self_compact`, with a note to begin `orchestrate`.

## epic.md
- **Goal:** one paragraph.
- **Scope:** in and out.
- **Acceptance scenarios:** those from `PROTOTYPE.md` plus agreed additions, each mapped to the child that delivers it.
- **Children, in order:** `NN_slug`, with its goal, what it depends on, and when it's done. A few lines each, each sized for one implementer session.
- **Parallel groups:** children that may build at the same time. Members have no dependency among them, their claims don't overlap, and none changes test infrastructure. Also set `maxLanes` (default 4).
- **Disposal and branch.**
- **Gates:**
  - the repo's T1 (targeted) and full-gate commands, with measured durations;
  - the test map and smoke set.
- **Checkpoints:** where the full gates run in the background. Place them:
  - after foundation children;
  - before fan-outs;
  - after children that widen T1 (schema, authorization, the shared shell, dependencies);
  - no more than about a day of children apart.

  Epic close is always one.
- **Budget:** wall time and cost per child. Exceeding it stops execution.
- **Autonomy:** what the human wants to decide personally beyond the standard stop conditions, and what execution may do without asking: push the branch, open the PR, file tracker items.
- **Decisions:** the human's decisions so far, with reasons. Execution appends to this.
- **Follow-ups:** empty at approval; execution appends to this.

Keep it to a few pages.

## Single plan
There is no `epic.md`, so the agreed scope, scenarios, gates, budget and autonomy limits go into `plan.md` itself.
1. Spawn a `plan-author` (`plan` skill), writing `plan.md` at the plan directory root, with the agreed scope in the task.
2. Relay the human's feedback by resuming the same plan-author.
3. Get a fresh review and the human's approval.

Execution then runs only the implement loop and hands to the PR process.

## Do
- Push back on scope creep, and raise gaps the human hasn't considered.
- Size children as vertical slices around reviewable diffs, not layers: a slice ends with a scenario that can be tested; a layer ends with nothing to show.
- Order children so the course-setting decisions land early, where a stop costs least.
- Group independent children for parallel lanes. Being independent and being a checkpoint are separate questions.

## Don't
- Write task lists, implementation detail or test checklists. That is the planner's job.
- Start execution without explicit approval.
