# ADR 0007: Pi runs the frontier pipeline; the sequential pipeline is retired there

Status: Accepted

Date: 2026-11-20

Requirement refs: FR-001, FR-002, OPR-001

## Context

ADR 0006 left one pipeline, the sequential one: brief → research → approach →
plan → worklog → task-by-task execution → code review. A second process was
piloted beside it on Pi (`plans/2026_10_10_frontier_pipeline/`): a throwaway
prototype, a scope agreed with the human, one short plan built whole by one
implementer, and fresh-context reviews. Its retrospectives
(`plans/2026_10_15_process_retro/`, `plans/2026_10_20_process_variants/`) and
the design that followed (`plans/2026_10_21_architecture_driven_plans/`) moved
the plan's design into a model built from a project's pattern catalog, approved
by the human from a tour, and checked against the code.

On Pi both sets of skills were installed side by side. A session saw two skills
for each job (`plan` and `create-plan`, `review` and `review-code`,
`implement` and `execute-task`) and two sets of presets. The owner decided
(2026-11-20) to retire the older set.

OpenCode and Hermes have no rendering of the frontier pipeline: its skills are
Pi-only, and they delegate through Pi subagents. Hermes agents and the backlog
dispatcher (`scripts/pipeline-dispatch.py`, the `work-item` skill) run the
sequential pipeline unattended. Hermes passes its own rendered skills to the Pi
subprocesses it starts, so it does not depend on the skills installed for Pi.

## Decision

1. On Pi the process is the frontier pipeline: `prototype`, `scope`,
   `run-plan`, `run-epic` and `map-patterns` as entry points; `plan`,
   `implement` and `review` as role skills; `architecture-model`, `delegate`
   and `test-quality` shared. `docs/frontier-pipeline.md` is its overview and
   the skills are its source of truth.
2. The sequential pipeline is retired for Pi. Its skills are restricted to
   `harnesses: [opencode, hermes]` and are no longer rendered or installed for
   Pi: `discovery`, `design`, `research`, `review-approach`, `review-epic`,
   `create-plan`, `review-plan`, `create-worklog`, `execute-task`,
   `execution-orchestrator`, `review-code`, `prototype-first` and `work-item`;
   `discover-and-design` and `discover-and-design-simple` become Hermes-only.
   The `discovery`, `design` and `execute` presets are removed.
3. OpenCode and Hermes keep the sequential pipeline unchanged, with the
   backlog dispatcher. Nothing is archived or deleted: the skills stay in
   `skills/` because two harnesses still render them.

## Consequences

- A Pi session sees one skill for each job.
- **A repository needs a pattern catalog before `scope` will plan in it.**
  `scope` stops when the project's agent guide names no path file; `map-patterns`
  writes a first catalog and `assess-repo` checks the set-up. There is no other
  planning process on Pi to fall back to.
- No Pi skill renders a delegation macro today, so the Pi delegation style of
  the renderer and the `roles` in `harnesses/pi.json` have no user. They are
  kept for skills that will.
- `docs/process.md`, `docs/orchestration.md`, `docs/plan-levels.md` and
  `docs/agent_architecture_and_workflow.md` describe the sequential pipeline.
  They remain right for OpenCode and Hermes; their Pi sections (presets, Pi
  subagents) are history.
- ADR 0006 still holds for OpenCode and Hermes.

## Not done

- **The older Pi agents are still installed**: `planner`, `plan-reviewer`,
  `code-reviewer`, `worker`, `worker-high`, `worker-low`, `ui-worker`,
  `vision`. No installed Pi skill starts the first three. They stay because
  consumers name them in `agentOverrides`, where an unknown name fails the
  build, and because `worker` and `vision` are used outside any pipeline.
  Removing the first three needs those overrides changed first.
- **Hermes, OpenCode and the backlog dispatcher are not moved** to the frontier
  pipeline. Its approval gate needs the human at the tour; an unattended
  backlog item has no such step yet.
- **A backlog item on Pi** has no skill that runs it: `work-item` runs the
  sequential pipeline, so it left with it.
