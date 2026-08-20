---
name: direct-plan
description: Skip the discovery and design document ceremony and turn the current conversation directly into a lean plan.md plus tasks.json for Parallel execution. Use when the goal, scope, and design were already settled in this session and the human wants to go straight to planning and execution. For unsettled direction use Discovery; for live design forks use Design; for epics use the full path.
harnesses: [pi]
---

# Direct Plan

Produce the two artifacts Parallel execution needs — a lean `plan.md` and a
checked `tasks.json` — straight from the current conversation, then hand off
to `/dynamic-execute-plan`. The conversation is the spec. You skip `brief.md`,
`approach.md`, `findings/`, and the review cycle. You do not skip the task
graph, the checker gate, or human approval.

## Why tasks.json, never a hand-written script

The executor's `workflowScript` is a generated artifact. `tasks.json` drives
script generation, write-collision checking, contract freezing, per-child
model routing, failure classification, and crash resume. A hand-authored
script has none of that and violates the executor's own rules. Planning in
this skill means writing the graph, never the script.

## When to use / when to stop

**Use when:** the goal, scope, and design direction were already settled in
this conversation, the decomposition is effectively known, and the human has
explicitly chosen to skip the document ceremony. Invoking this skill is that
choice — do not re-litigate it.

**Stop and redirect when:**

- the direction or a real design fork is still open — use `/discovery` then
  `/design`
- the work is epic-sized — use the full path; do not write a detailed plan at
  an epic root
- the settled design lives in an earlier session you cannot see — without the
  conversation there is nothing to plan from; ask for a summary or use
  `/discover-and-design` or the full path
- you cannot find the repo's real verification commands — ask; do not invent
  them

## Process

1. **Mine the conversation.** Extract the goal, scope boundaries, the design
   decisions already made, the files and modules in play, and the
   verification approach discussed. If a load-bearing piece is missing, ask
   at most one focused batch of questions.
2. **Read the rules.** Read
   [docs/approaches/parallel.md](docs/approaches/parallel.md) for the
   planning, fence, and verification-class rules, and
   [references/tasks-schema.md](references/tasks-schema.md) for the
   `tasks.json` shape. Both are installed skill resources. Runtime limits
   (spawn budget, timeouts, fixed resources) are in
   [docs/execution-patterns.md](docs/execution-patterns.md).
3. **Find the real verification commands** from the canonical docs `AGENTS.md`
   points to. Run the final gate once and record the baseline.
4. **Decompose.** Ownership tasks, real dependency edges only, a verification
   class and write-set per task, fence groups only where later work must wait
   for a host-verified subgraph. Set `models.cheap` and `models.strong` from
   the repo's model configuration, or ask the human.
5. **Write the artifacts** into `plans/YYYY_MM_DD_<slug>/`:
   - `tasks.json` per the schema.
   - `plan.md`, lean: one short goal/context section naming the conversation
     as the source, a Task Overview table listing every task id, class, and
     fence group, and a Verification Plan with the baseline and the full final
     gate — every gate the repo runs in CI and in its canonical docs. The
     checker requires the Task Overview; the executor runs the final gate from
     the Verification Plan. Skip the rest of the plan template.
   - Requirements mapping if the repo maintains them. Cite IDs; record
     questions instead of editing canonical requirements.
   - If the plan directory tracks state, set `state.json` to
     `{ "phase": "planned", "status": "active" }`.
6. **Run the gate:**
   `node "$HOME/.pi/agent/skills/direct-plan/tools/check-plan.mjs" <plan-dir>`.
   Fix everything it reports. A plan that does not pass cannot be executed.
   If the checker is missing, stop and report an installation error.
7. **Show a compact summary and wait.** Task graph, classes, write-sets,
   fences, verify commands. The human's explicit approval of this summary is
   the only review gate on this path. If the work turns out riskier than the
   fast path assumed, offer `/dynamic-review-plan` before execution.
8. **Commit** the approved `plan.md`, `tasks.json`, and `state.json` as
   `plan: direct plan from discussion for <slug>`.
9. **Next step:** "The plan is approved. Execute it with
   `/dynamic-execute-plan` — it will generate the fence-group scripts from
   `tasks.json` and stop for your approval of each generated script before
   launch."

## Quality bar

- Every task names concrete files, behaviours, and a verify command. "Done" is
  a command.
- Dependency edges are real coupling; write-sets of same-group tasks are
  disjoint.
- The final gate in the Verification Plan covers every gate the repo runs.
- The graph fits one run: roughly 16 tasks at about four spawns each against
  the 64-spawn budget. Split larger work.
- The plan faithfully records the discussed design — no silent scope growth,
  no dropped constraints.

## What you must not do

- Do not write `brief.md`, `approach.md`, or `findings/`.
- Do not hand-author or hand-edit a `workflowScript` / `dataflow.*.js` — that
  is the executor's job, generated from your `tasks.json`.
- Do not implement anything or modify source files.
- Do not invent verification commands without a canonical source.
- Do not leave placeholder tokens (`<...>`) in the final artifacts.
- Do not require `maxWidth` or serialize the graph to fake a fence.
- Do not execute. Hand off to `/dynamic-execute-plan` after approval.
