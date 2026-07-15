---
name: create-team-worklog
description: Create the lead-owned execution ledger from a reviewed team_plan.md for role-based OpenCode team-mode execution. Records stages, active slots, assignments, remediation, wake events, evidence, integration groups, and closure.
harnesses: [opencode]
metadata:
  domain: opencode
---

# Create Team Worklog

Create the durable execution ledger for an approved team plan.

## Role

Translate `team_plan.md` into a self-sufficient lead control document. Do not redesign the
team plan or convert sequential tasks into waves.

## Inputs

- `team_plan.md` and clean `team_plan_review.md`
- Repo verification, backlog, requirements, and directory guidance
- Baseline gate results, if already available

## Process

1. Validate the team plan review is complete.
2. Extract roster, contract/implementation/verification packets, readiness events, active
   slot schedule, integration groups, checks, gates, retry limits, and escalation targets.
3. Record baseline gates or require them before the first integration group.
4. Build an event-driven assignment board. Pre-assign immediately ready packets; leave
   blocked roles idle until the lead wakes them.
5. Write `team-worklog.md` using
   [references/team-worklog-template.md](references/team-worklog-template.md).
6. Update `state.json` to `{ "phase": "ready", "status": "active", "mode": "team" }`.

## Quality Rules

- The worklog is an execution ledger, not a second plan.
- The lead is sole scheduler, committer, broad-gate runner, and durable-doc writer.
- The lead routes each packet strictly by its declared implementer class
  (mechanical→`quick`, standard→`unspecified-high`, complex→`deep`); mechanically-routed
  members receive only mechanically-classified packets. Members never self-select.
- No active schedule exceeds four concurrent members.
- Every blocked assignment names its wake event and sender.
- Do not poll. Idle members stop and wait for `team_send_message` with an actionable task.
- Contract packets start before or alongside implementation where the team plan permits.
- Implementers run only minimal packet checks.
- Live reviewer creates remediation tasks and controls integration readiness.
- Original implementer gets one local retry; Strong rescue implementer receives failed
  retries and high-risk/cross-cutting work.
- Contract/verifier owns targeted evidence; lead owns broad gates.
- Fresh final reviewer (default `deep`, escalate to `ultrabrain` for unusually hard/unique
  reviews) runs after the implementation team closes.
- Backlog, requirements, `state.json`, and this worklog remain lead-only writes.

## Output

Write `team-worklog.md`. Do not modify source files or create a sequential `worklog.md`.

## What You MUST NOT Do

- Do not read `plan.md` as the team execution source.
- Do not re-slice packets into dependency waves.
- Do not create a `NEXT STEP` task cursor.
- Do not instruct members to periodically inspect the task board.
- Do not let members run git or broad gates.
