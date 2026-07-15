---
name: create-team-worklog
description: Create a wave-oriented team worklog from a reviewed plan for OpenCode team-mode (parallel) execution. The team worklog is the durable execution record whose live coordination cursor is the team task list, replacing the sequential worklog's single NEXT STEP. Use after plan review passes and team-mode execution is selected.
compatibility: opencode
metadata:
  domain: opencode
---

# Create Team Worklog

Create a wave-oriented execution worklog for team-mode (parallel) execution.

## Role

You produce the durable execution record for a team-mode run. Unlike the sequential worklog (a single `NEXT STEP` cursor), the team worklog is organized around **waves** — batches of tasks that execute in parallel. The live coordination cursor is the OpenCode `team_task_list`; this document is the durable record of wave composition and outcomes.

Use this only for OpenCode team-mode execution. For sequential execution, use `create-worklog` instead.

## Inputs

- Plan directory path
- Read: `plan.md` (task graph with `Depends on` and `Touched files`, verification commands, gate policy)
- Read: repo test architecture docs for exact verification commands
- Read: repo task-tracking/backlog docs (follow-up capture policy)
- Read: repo requirements docs if the plan cites or updates requirements

## Process

1. **Read plan.md** — extract the task graph, each task's `Depends on` and `Touched files`, verification commands, and gate policy.
2. **Slice waves** — apply the wave-slicing procedure (see the `execution-orchestrator-team` skill) to produce an ordered list of waves. Record the wave manifest.
3. **Read repo verification commands** — copy exact fast/gate/final commands; do not invent them.
4. **Read backlog + requirement policy** — as for the sequential worklog.
5. **Baseline gate audit** — carry the plan's baseline results in, or instruct running all gates before Wave 1.
6. **Write team-worklog.md** — using [references/team-worklog-template.md](references/team-worklog-template.md).
7. **Update state.json** — set `{ "phase": "ready", "status": "active", "mode": "team" }`.

## Quality Rules

### The wave manifest must be complete and file-disjoint
Every plan task must appear in exactly one wave. Within a wave, no two tasks may share a declared `Touched files` path. A task with an undeclared write-set runs alone in its own wave. No task may depend on another task in the same wave.

### Verification commands must be exact
Copy fast/gate/final commands from plan.md or repo docs verbatim.

### The team worklog must be self-sufficient
A lead resuming a run should be able to read only this file and know: which wave is current, which tasks are in it, each task's declared files, the per-wave gate, and how per-wave commits are recorded.

### The cursor is the current wave, not a single task
Track a `Current Wave` pointer plus the intra-wave task board. Do not reintroduce a single `NEXT STEP` task cursor.

### Backlog + requirement policy must be explicit
Same rules as the sequential worklog: state where the backlog lives, how to capture accepted follow-ups, and how approved requirement edits are applied. Route all such durable-doc writes through the lead, never concurrent members.

## Output

Write `team-worklog.md` in the plan directory. It is designed for wave-at-a-time execution driven by the `execution-orchestrator-team` skill.

## What You MUST NOT Do

- Do not implement code or modify source files
- Do not invent verification commands
- Do not reorder or reinterpret plan tasks
- Do not place two file-overlapping or dependency-linked tasks in the same wave
- Do not reintroduce a single-task `NEXT STEP` cursor
