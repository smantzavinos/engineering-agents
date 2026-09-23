# Team Execution Worklog Template

# <Title> — Team Execution Worklog

## Entry-Point Contract

- Read this file first when resuming.
- `team_plan.md` is the canonical execution design; the live team task board (created from
  the plan's DAG table with `blockedBy` and lane tags) is the source of per-task transient
  state. This file records only wave-boundary facts, deviations, and evidence references.
- Primary chat is lead, sole committer, broad-gate runner, and durable-doc writer, and the
  dispatcher of last resort under the Turn-Exit Contract.
- Update this file only at wave commits, deviations, remediations, and closure — never per
  task transition.

## References

- Team plan: `team_plan.md`
- Team plan review: `team_plan_review.md`
- Team protocol: `docs/team-mode-execution.md`

## Completion Criteria

- [ ] All tasks on the team board are terminal
- [ ] All wave gates are run and committed
- [ ] Implementation team is closed
- [ ] Fresh final review is clean
- [ ] Final gate passes or only approved baseline failures remain

## Baseline Gate Evidence

| Profile | Status | Approved unrelated failures | Policy |
|---|---|---|---|
| broad-gate | pass/fail | <none/list> | block/allow/split |

## Wave Ledger

One row per committed wave. Task IDs and lanes come from the plan's DAG table.

| Wave | Tasks included | Gate profile | Result | Commit |
|---|---|---|---|---|
| 1 | C1, I1, I2 | broad-gate | <pass/fail> | <sha> |

## Deviations and Critical Decisions

One line each: what changed versus the plan and why.

- YYYY-MM-DD — <deviation/decision>

## Remediation Summary

| Task | Defect | Resolution | Route |
|---|---|---|---|
| I1 | <finding> | <fix summary> | retry / rescue |

## Evidence References

Paths and commands only; no output dumps.

- AC1 — `<test path>` via `<profile>` — pass/fail

## Final Review and Closure

- **Team closure:** <pending/complete>
- **Fresh final reviewer:** external `deep` (escalate to `ultrabrain` for unusually hard/unique reviews)
- **Final review passes:** <n>/5 — <findings artifact/status>
- **Final remediation:** <none/owner/team>
- **Final gate:** <profile> → <result>
- **Completion commit/state:** <sha/status>

## Backlog and Requirement Changes

- Lead-only accepted follow-ups: <none/IDs>
- Lead-only approved requirement updates: <none/IDs>
