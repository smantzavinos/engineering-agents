---
name: dynamic-create-plan
description: Write a dynamic-workflow plan from an approved approach — both plan.md for humans and tasks.json for the wave engine, with a verification class and write-set per task. Use after design is complete and before execution.
harnesses: [pi]
---

# Dynamic: Create Plan

Produce the two artifacts dynamic-workflow execution needs:

1. `plan.md` — the narrative a human reads and approves.
2. `tasks.json` — the graph the wave engine runs.

Both are **outputs of this skill**, written together in one pass. They are not separate
authoring steps: a task's verification class and write-set are plan decisions, and `plan.md`'s
Task Overview displays them. Splitting the two would mean deciding half here and half
elsewhere, then policing the drift that split created.

They are different documents with different audiences. Do not put the executable graph in
prose, and do not put rationale in JSON.

Read [references/tasks-schema.md](references/tasks-schema.md) before writing `tasks.json`.
Read [docs/execution-patterns.md](docs/execution-patterns.md) for what the engine does with it.
These are installed skill resources, not files the target repository must provide.

## Inputs

- `brief.md`, `approach.md`, and `findings/` in the plan directory. **`plan.md` is not an
  input** — you are writing it.
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
10. **Run the gate:**
    `node "$HOME/.pi/agent/skills/dynamic-create-plan/tools/check-plan.mjs" <plan-dir>`.
    Fix everything it reports. A plan that does not pass cannot be executed. Use the installed
    checker; do not create framework tooling in the target repository. If the checker is missing,
    stop and report an installation error.

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

Each task declares `writes`: repository-relative POSIX paths in the limited dialect documented
in [references/tasks-schema.md](references/tasks-schema.md). `*` is the only wildcard and must
occupy a whole path segment. Do not use `**`, `?`, character classes, braces, or partial-segment
patterns.

Two tasks can be scheduled in the same wave unless one transitively depends on the other. If
two such tasks declare overlapping writes, they will race in the shared tree. `check-plan.mjs`
rejects this. When it fires, either add the missing dependency or merge the tasks — do not
widen a glob to make the message go away.

## Decomposing for parallel execution

Wave and dataflow engines run the same `tasks.json`; what differs is what serialization
costs. A wave engine merely tolerates an over-serialized graph (it wastes width); a DAG
dataflow run is built to exploit a well-shaped one (every unnecessary dependency is a
barrier). Shape every graph as if it will be executed as a DAG.

**Every dependency must be real coupling.** Audit each edge against these tests:

- **Real** — the dependent cannot type, compile, or run without the dep's artifact: schema
  before mutations typed against it; contract specs before the code they execute; a
  component before its mount point.
- **Accidental** — treat as a design smell and restructure instead of linking:
  - tasks *share* a component that one of them builds → extract the shared component into
    its own task, so consumers depend on the component, never on each other;
  - a task exists only to avoid a write collision across files several tasks touch → give
    each task complete ownership of its files instead;
  - "this felt like the natural order" → not a dependency.

**Ownership patterns:**

- **One file, one task.** If two tasks would write the same file, either merge them (when
  the changes are cohesive — e.g. one surface's filter and its chips) or extract the shared
  piece. A `check-plan.mjs` write collision is a design signal about your decomposition,
  not an obstacle to route around with a serialization dependency.
- **Shared components are standalone tasks** preceding all their consumers. Bundling a
  shared component with the first consumer's integration task serializes every other
  consumer on work that has nothing to do with them.
- **Collectors merge last.** Tasks that aggregate (requirements regeneration, worklog,
  final docs) naturally depend on everything and run last; never let them fan dependencies
  backwards.

**Anti-patterns seen in practice:** bundling shared components with an integration task; a
trailing "polish" task that touches all surface files after parallel surface tasks (merge
the polish into each surface's ownership); dependency chains between tasks whose files are
disjoint (they serialize nothing but the clock).

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
- Do not add unrelated follow-up work to the task graph. Use the repo's documented follow-up
  mechanism and ID scheme; if none is documented, ask rather than inventing one.
- Do not use this skill for greenfield repo planning.
