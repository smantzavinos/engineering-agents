---
name: create-team-worklog
description: Create the lead-owned execution ledger from a reviewed team_plan.md for role-based OpenCode team-mode execution. Records stages, active slots, assignments, remediation, wake events, evidence, integration groups, and closure.
compatibility: opencode
metadata:
  domain: opencode
---

# Create Team Worklog

Create the durable execution ledger for an approved team plan.

## Role

Translate `team_plan.md` into a compact lead-owned wave ledger. Do not redesign the team plan,
duplicate its contents, or convert sequential tasks into waves. Transient per-task state lives
on the live team task board, not in this document.

## Inputs

- `team_plan.md` and clean `team_plan_review.md`
- Repo verification, backlog, requirements, and directory guidance
- Baseline gate results, if already available

## Process

1. Validate the team plan review is complete.
2. Record baseline gate evidence or require it before the first integration group.
3. Copy only the wave/commit checkpoint list and verification profile names from the plan.
4. Write `team-worklog.md` using
   [references/team-worklog-template.md](references/team-worklog-template.md).
5. Update `state.json` to `{ "phase": "ready", "status": "active", "mode": "team" }`.

## Ledger Contents

The worklog records only:

- baseline gate evidence
- per-wave commit entries: task IDs included, gate profile run, result, commit hash
- deviations from the plan and critical decisions, one line each
- remediation summaries: packet, defect, resolution, route
- evidence references (paths/commands), not command output dumps
- final closure: fresh-review passes, final gate, completion state

It never duplicates packet definitions, member prompts, wake conditions, verification
commands, or risk text — those live in `team_plan.md` and on the live task board. Update the
worklog only at wave commits, deviations, and closure. A worklog that requires updating per
task transition is a design defect; report it against the plan.

## Quality Rules

- The worklog is a wave ledger, not a second plan and not an assignment board.
- The lead is the sole committer, broad-gate runner, and durable-doc writer.
- Task routing follows plan lane tags; the live team task board (created from the plan's DAG
  table with `blockedBy`) is the single source of per-task state.
- No active schedule exceeds four concurrent members.
- Implementers run only minimal packet checks; the contract/verifier owns targeted evidence;
  the lead owns broad gates.
- Original implementer gets one local retry; the Strong rescue implementer is created on
  escalation for failed retries and high-risk/cross-cutting work.
- Fresh final reviewer (default `deep`, escalate to `ultrabrain` for unusually hard/unique
  reviews) runs after the implementation team closes.
- Backlog, requirements, `state.json`, and this worklog remain lead-only writes.

## Output

Write `team-worklog.md`. Do not modify source files or create a sequential `worklog.md`.

## What You MUST NOT Do

- Do not read `plan.md` as the team execution source.
- Do not duplicate the plan's packet tables, prompts, or command lists into the worklog.
- Do not build a per-task assignment board in the worklog; the team task board owns that.
- Do not re-slice packets into dependency waves.
- Do not create a `NEXT STEP` task cursor.
- Do not let members run git or broad gates.
