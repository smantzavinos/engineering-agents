---
name: scope
description: Turn a prototype into an agreed, reviewed scope with the human (an epic of child plans, or a single plan) that can then run autonomously. Interactive; the human approves the result.
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
6. Get a fresh review (`review` skill, epic or plan mode). Resolve the findings with the human. Repeat until clean, for at most 4 passes.
7. When the human approves:
   - commit;
   - write `state.json`;
   - `self_compact`, with a note to begin `orchestrate`.

## epic.md
- **Goal:** one paragraph.
- **Scope:** in and out.
- **Acceptance scenarios:** those from `PROTOTYPE.md` plus agreed additions, each mapped to the child that delivers it.
- **Children, in order:** `NN_slug`, with its goal, what it depends on, and when it's done. A few lines each, each sized for one implementer session.
- **Disposal and branch.**
- **Gates:** the repo's quality-gate commands, run at the end of each child.
- **Autonomy:** anything the human wants to decide personally, beyond the standard stop conditions.
- **Decisions:** the human's decisions so far, with reasons. Execution appends to this.

Keep it to a few pages.

## Single plan
There is no `epic.md`.
1. Spawn the planner (`plan` skill), writing `plan.md` at the plan directory root.
2. Relay the human's feedback by resuming the same planner.
3. Get a fresh review and the human's approval.

Execution then runs only the implement loop.

## Do
- Push back on scope creep, and raise gaps the human hasn't considered.
- Size children around reviewable diffs, not around layers.

## Don't
- Write task lists, implementation detail or test checklists. That is the planner's job.
- Start execution without explicit approval.
