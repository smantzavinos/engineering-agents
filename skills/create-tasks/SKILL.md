---
name: create-tasks
description: Turn an approved approach into a Pi code-mode plan — plan.md for humans plus tasks.json for the wave engine, with a verification class per task. Use after design/approach is complete and before execution.
harnesses: [pi]
---

# Create Tasks

Produce the two artifacts code-mode execution needs:

1. `plan.md` — the narrative a human reads and approves.
2. `tasks.json` — the graph the wave engine runs.

They are different documents with different audiences. Do not put the executable graph in
prose, and do not put rationale in JSON.

Read [references/tasks-schema.md](references/tasks-schema.md) before writing `tasks.json`.
Read `docs/execution-patterns.md` for what the engine does with it.

## Inputs

- `brief.md`, `approach.md`, and `findings/` in the plan directory.
- The repo's verification commands, from the docs `AGENTS.md` points to. **Do not invent
  them.** If you cannot find them, ask.
- The repo's requirements and backlog policy, if it has one.

## Process

1. **Read the context.** Brief, approach, findings. For an epic child plan, stay inside the
   boundary the parent `epic.md` set.
2. **Find the real verification commands** from canonical repo docs.
3. **Record the baseline.** Run the final gate command once and note what already fails. A
   pre-existing failure mistaken for a regression wastes a wave. Put it in the plan's
   baseline table.
4. **Decompose into tasks** with explicit dependencies.
5. **Assign a verification class to every task** (see below).
6. **Declare a write-set per task.** This is what makes parallel execution safe — see the
   collision rule below.
7. **Map requirements** if the repo maintains them.
8. **Write `plan.md`** from [references/plan-template.md](references/plan-template.md).
9. **Write `tasks.json`** per the schema.
10. **Run the gate:** `node tools/check-plan.mjs <plan-dir>`. Fix everything it reports. A
    plan that does not pass cannot be executed.

## Verification classes

Every task declares one. Choose by asking: *can this task's test fail because of a change in
the behaviour or artifact the task modifies, without someone editing the test?*

| Class | When | Verification |
|---|---|---|
| `contract` | new or changed observable behaviour | a failing test authored first, by an agent other than the implementer, then frozen |
| `characterization` | refactor with no behaviour change | the existing suite, scoped |
| `check` | config, wiring, generated artifacts, schema | a structural check command |
| `none` | prose with no structural contract | the repo's existing docs spec |

- `contract` tasks must list `testPaths`. Those files are frozen at the contract commit and
  verification asserts they did not change — that is what stops an implementer satisfying a
  task by editing the test.
- Every class except `none` must name a `verify` command. "Done" is a command, not an opinion.
- `none` is a legitimate answer. Choose it deliberately rather than inventing a test that only
  asserts a document contains a sentence someone just wrote. That is not a test.
- There is **no mandatory break-it step**. A reviewer may demand one when a test looks like it
  cannot fail; an implementer never self-administers it.

## Write-sets and parallelism

Each task declares `writes`: the paths or globs it may modify.

Two tasks can be scheduled in the same wave unless one transitively depends on the other. If
two such tasks declare overlapping writes, they will race in the shared tree. `check-plan.mjs`
rejects this. When it fires, either add the missing dependency or merge the tasks — do not
widen a glob to make the message go away.

## Quality rules

**Tasks must be specific.** Name concrete files, specific behaviours, exact commands.

- Bad: "implement the notification service"
- Good: "Create `src/notifications/service.ts` with `createNotification()` and `getUnread()`.
  Test in `src/notifications/service.test.ts` asserts `createNotification()` persists to the
  notifications table."

**Briefs carry paths, never file contents.** The implementer reads files itself. Pasting
source into a brief wastes context and goes stale.

**Tasks must be small enough for one child.** The per-child default timeout is 30 minutes. A
task needing appreciably more should be split, or declare `timeoutMs` deliberately.

**Mind the fan-out ceiling.** A run allows 64 spawns and never refunds them. At roughly four
spawns per task including review and retries, a single run caps near 16 tasks. Larger plans
should be split into separate executions.

## Epic guard

Do not write a detailed plan at an epic root. This skill is for standard plans and epic
**child** plans. Epic roots are decomposed into child plans in `epic.md` first.

## Output

Write `plan.md` and `tasks.json` into `plans/YYYY_MM_DD_<slug>/`, then run the gate. If the
plan directory tracks state, set `state.json` to `{ "phase": "planned", "status": "active" }`.

## What you must not do

- Do not implement anything or modify source files.
- Do not invent verification commands without a canonical source.
- Do not leave placeholder tokens (`<...>`) in the final artifacts.
- Do not add unrelated follow-up work to the task graph; put it in the backlog with a stable
  ID.
- Do not use this skill for greenfield repo planning.
