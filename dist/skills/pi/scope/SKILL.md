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
   - a **single plan**, if it fits within the review-load signal (see `epic.md` → Review-load signal; record it in `plan.md`);
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
- **Children, numbered:** `NN_slug`, with its goal, the children it depends on (the real dependency record: execution starts a child once these are integrated), and when it's done. A few lines each, with a rough estimate in changed lines. A child is a cohesive vertical slice: a piece of behaviour with its data, logic, UI and tests, ending in a testable scenario.
- **Claims** (with a worktree pool): every child's claim, the directories, routes, tables and shared components it may change. Children whose claims overlap never run at once.
- **Parallel groups:** children that build at the same time and integrate together.
  - Members' claims must not overlap, except for the merge-friendly files the epic names, such as indexes and changelogs.
  - Members have no dependency among them. None changes test infrastructure, and none changes schema that a sibling reads.
  - Set `maxLanes` (default 4, at most the pool size) and the machine-wide E2E worker budget (default cores ÷ 4). A group has at most `maxLanes` members.
  - Children in no group still run in parallel when their dependencies and claims allow.
- **Disposal and branch.**
- **Gates:**
  - the repo's T1 (targeted) and full-gate commands, with measured durations;
  - the test map and smoke set;
  - which repo support exists (test map, smoke set, warm harness, parallel E2E, worktree pool, checkpoint worktree), and the disk floor.

  Missing support degrades as the skills say. For example, with no pool there are no lanes.
- **Checkpoints:** where the full gates run in the background. Each is named after a child, and runs once that child and every child it depends on are integrated. Place them:
  - after foundation children;
  - before fan-outs;
  - after children that widen T1 (see `plan`);
  - no more than about a day of children apart.

  Epic close is always one.
- **Escalation implementer** (optional): the agent that takes over a child's code-review fixes when pass 2 isn't approved, when the default implementer is a fast model.
- **Review-load signal:** the changed lines a reviewer can judge in one pass (default about 7k, not counting generated files). A child above it is checked for separable concerns; it is split only if its concerns are separable and the pieces can run as parallel lanes. Never split serial or inherently related work to meet the number: each child adds a fixed cost to the critical path that only parallel lanes hide. Record an initial implementer-hours-per-1k-lines rate for the implementer model, and replace it with one calibrated from the first children's actuals.
- **Budget:** wall time and cost per child: the implementer hours for the plan's estimate × 1.5, plus the per-child fixed cost. Set provisionally from this entry's estimate when the plan loop starts, replaced at plan approval, updated at refresh or resize, and recorded in `state.json`. Exceeding it stops execution.
- **Autonomy:** what the human wants to decide personally beyond the standard stop conditions, and what execution may do without asking: push the branch, open the PR, file tracker items.
- **Decisions:** the human's decisions so far, with reasons. Execution appends to this.
- **Follow-ups:** empty at approval; execution appends to this.
- **Quarantine:** non-gating flaky tests, each with an owner and an expiry. Empty at approval.

Keep it to a few pages.

## Single plan
There is no `epic.md`, so the agreed scope, scenarios, gates, budget and autonomy limits go into `plan.md` itself. Gates there include the full-gate commands, the test map and the smoke set.
1. Spawn a `plan-author` (`plan` skill), writing `plan.md` at the plan directory root, with the agreed scope in the task.
2. Relay the human's feedback by resuming the same plan-author.
3. Get a fresh review and the human's approval.

Execution then runs the implement loop, then the full gates once, then hands to the PR process.

## Do
- Push back on scope creep, and raise gaps the human hasn't considered.
- Size children as vertical slices around reviewable diffs, not layers: a slice ends with a scenario that can be tested; a layer ends with nothing to show.
- Order children so the course-setting decisions land early, where a stop costs least.
- Group by content, not by size. Group independent children for parallel lanes. Being independent and being a checkpoint are separate questions.

## Don't
- Write task lists, implementation detail or test checklists. That is the planner's job.
- Start execution without explicit approval.
