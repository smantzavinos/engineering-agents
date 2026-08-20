---
name: dynamic-create-plan
description: Write a Parallel plan from an approved approach. Produces plan.md for humans and tasks.json for the DAG executor, with verification class, write-set, and optional fence groups per task. Use after design completes and before execution.
harnesses: [pi]
---

# Parallel: Create Plan

Produce the two artifacts Parallel execution needs:

1. `plan.md`, the narrative a human reads and approves.
2. `tasks.json`, the graph the executor runs, including optional `fenceGroups`.

Both are written together. A task's verification class, write-set, and fence
group are plan decisions, and `plan.md`'s Task Overview displays them.

Read [references/tasks-schema.md](references/tasks-schema.md) before writing
`tasks.json`. Read [docs/approaches/parallel.md](docs/approaches/parallel.md)
for the scheduler and fence rules. Those files are installed skill resources,
not files the target repository must provide.

## Inputs

- `brief.md`, `approach.md`, and `findings/` in the plan directory. `plan.md`
  is not an input; you are writing it.
- The repo's verification commands, from the docs `AGENTS.md` points to. Do not
  invent them. If you cannot find them, ask.
- The repo's requirements and backlog policy, if it has one.

## Process

1. **Read the context.** Brief, approach, findings. For an epic child plan,
   stay inside the boundary the parent `epic.md` set.
2. **Find the real verification commands** from canonical repo docs.
3. **Record the baseline.** Run the final gate commands once and note what
   already fails. Put it in the plan's baseline table. The final gate must
   cover every gate the repo runs in CI and in its canonical docs: typecheck,
   lint, unit, E2E, and domain gates. A missing gate is a plan-review finding.
4. **Decompose into ownership tasks** with real dependency edges only.
5. **Assign a verification class** to every task.
6. **Declare a write-set** per task.
7. **Place fence groups.** Default is to omit `fenceGroups`, which means one
   implicit group containing the whole graph. Add groups only where later work
   must not start until the host has verified the subgraph.
8. **Map requirements** if the repo maintains them.
9. **Write `plan.md`** from
   [references/plan-template.md](references/plan-template.md). Name the fence
   groups in the Task Overview or in a Fence Groups section.
10. **Write `tasks.json`** per the schema.
11. **Run the gate:**
    `node "$HOME/.pi/agent/skills/dynamic-create-plan/tools/check-plan.mjs" <plan-dir>`.
    Fix everything it reports. A plan that does not pass cannot be executed.
    If the checker is missing, stop and report an installation error.

## Verification classes

Every task declares one. Ask: *can this task's test fail because of a change in
the behaviour or artifact the task modifies, without someone editing the test?*

| Class | When | Verification |
|---|---|---|
| `contract` | new or changed observable behaviour | a failing test authored first, by an agent other than the implementer, then frozen |
| `characterization` | refactor with no behaviour change | the existing suite, scoped |
| `check` | config, wiring, generated artifacts, schema | a structural check command |
| `none` | prose with no structural contract | the repo's existing docs spec |

- `contract` tasks must list `testPaths`.
- Every class except `none` must name a `verify` command.
- `none` is legitimate. Do not invent a test that only asserts a document
  contains a sentence someone just wrote.
- There is no mandatory break-it step.

## Write-sets and fences

Each task declares `writes` in the dialect described in
[references/tasks-schema.md](references/tasks-schema.md).

Two tasks can run at the same time when they share a fence group and neither
transitively depends on the other. If those two write overlapping paths, the
checker rejects the plan. Fix the decomposition. Do not widen a glob.

Tasks in different fence groups never overlap in time, so they may write the
same path. The later group starts after the earlier group's host verify.

**When the dialect cannot express the path.** Dynamic route segments such as
`[id]` are rejected by the checker, and the whole-segment `*` wildcard can then
collide with a sibling file. When the decomposition is right and only the
dialect is wrong, use the wildcard plus a scheduling-only dependency between
the two tasks, and label the edge as scheduling-only in `plan.md`. The files
are disjoint; the edge exists to satisfy the checker. Do not restructure a
correct decomposition to appease the checker.

**Fixed resources.** Verify commands that bind fixed resources, such as ports
or a single-server test harness, cannot run concurrently. Read verify commands
at plan time. When two tasks' verifies bind the same fixed resource, sequence
them with a scheduling-only dependency or a fence, or move those verifies to
the host at the fence. Tell the human, and name the concrete fix. For example,
configuring Playwright for dynamic ports would let those verifies run
concurrently, which turns a hidden limit into a backlog choice.

## Decomposing for a DAG

Plan ownership, not story order.

**Every dependency must be real coupling.** The dependent cannot type, compile,
or run without the dep's artifact. Drop "this felt like the natural order."

**Ownership**

- One file, one in-flight owner. If two same-group tasks would write the same
  path, merge them or extract the shared piece.
- Shared components are standalone tasks that precede their consumers.
- Collectors such as regeneration scripts and final docs belong in a later
  fence group or depend on everything they collect. Never fan those edges
  backwards.

**Fence groups**

Ask: "If this subgraph is wrong, what later work do I refuse to start?" Put
that later work in the next group. Everything that can safely overlap stays in
the same group, so the DAG can start a dependent as soon as its own deps finish.

Do not place a fence after every currently-ready independent task. That is the
old wave engine.

What a fence verify includes is a per-plan decision: the union of the group's
task verifies plus frozen diffs, a scoped suite, or the full suite. There is
deliberately no universal default. Record the choice in `plan.md`'s
Verification Plan so the executor and the reviewer know what each fence proved.

**Shared-spec partitioning**

One frozen spec file can back several concurrent tasks when it is partitioned
by selectors the tasks verify against independently, such as per-task describe
titles grepped by scope. The scopes must obey a no-cross-substring rule: no
test title inside one task's scope may contain another task's grep string. Pin
the titles in `interfaces.md`. Partition selectors, not files, whenever the
alternative is duplicating a contract across specs.

**Anti-patterns.** Recognize these in a draft plan:

- A shared component bundled into its first consumer's integration task. This
  serializes every other consumer on work that has nothing to do with them.
- A trailing polish task that re-touches files several parallel tasks already
  own. Give each task complete ownership instead.
- Dependency edges between tasks whose write-sets are disjoint. They serialize
  nothing but the clock.
- Edges added only to dodge a checker collision the dialect cannot express. Use
  the scheduling-only escape and label it, so it is not mistaken for coupling.
- Story-order fences. A fence that exists because "these tasks feel like they
  go together" recreates the wave engine.

## Quality rules

- Tasks name concrete files, behaviours, and commands.
- Briefs carry paths, never file contents.
- One child, default 30 minutes. Split or set `timeoutMs`.
- A run allows 64 spawns and never refunds them. At roughly four spawns per
  task, a run caps near 16 tasks. Split larger work.

## Epic guard

Do not write a detailed plan at an epic root. This skill is for standard plans
and epic child plans.

## Output

Write `plan.md` and `tasks.json` into `plans/YYYY_MM_DD_<slug>/`, then run the
gate. If the plan directory tracks state, set `state.json` to
`{ "phase": "planned", "status": "active" }`.

## What you must not do

- Do not implement anything or modify source files.
- Do not invent verification commands without a canonical source.
- Do not leave placeholder tokens (`<...>`) in the final artifacts.
- Do not add unrelated follow-up work to the task graph.
- Do not require `maxWidth` or serialize the graph to fake a fence.
