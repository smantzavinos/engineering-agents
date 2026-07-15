# Team Execution Worklog Template

# <Title> — Team Execution Worklog

## Entry-Point Contract

- Read this file first when resuming.
- `team_plan.md` is the canonical execution design; this file records live state and evidence.
- Primary chat is lead and sole scheduler, committer, broad-gate runner, and durable-doc writer.
- Team members work only from explicit assignments sent by the lead.
- Do not poll. If no actionable assignment exists, report idle once and stop.

## References

- Team plan: `team_plan.md`
- Team plan review: `team_plan_review.md`
- Team protocol: `docs/team-mode-execution.md`

## Completion Criteria

- [ ] All contract, implementation, remediation, and verification packets are terminal
- [ ] All integration groups are reviewed, gated, and committed
- [ ] Implementation team is closed
- [ ] Fresh final review is clean
- [ ] Final gate passes or only approved baseline failures remain

## Team Roster and Routing

| Member | Role | Routing | Start state | Current assignment |
|---|---|---|---|---|
| impl-1..3 | implementation slots | cheap/domain category; one may be `visual-engineering` | idle/active | <packet/none> |
| rescue | Strong rescue implementer | direct `hephaestus` | idle | none |
| verifier | contract/verifier | domain category | active/idle | <packet/none> |
| live-reviewer | live review | `unspecified-high` | idle | none |
| lead | orchestration | primary chat | active | scheduling |

When UI/UX/a11y/visual packets exist, record which implementation slot was replaced by the
`visual-engineering` member.

## Active Slot Schedule

Maximum active members: 4.

| Stage | Active members | Capacity check | Notes |
|---|---|---|---|
| Contract | <members> | <=4 | <idle roles> |
| Build/review | <members> | <=4 | <handoff flow> |
| Remediation | <members> | <=4 | rescue replaces a fast slot |
| Verification | <members> | <=4 | verifier wakes on explicit signal |

## Baseline Gate Audit

| Command | Scope | Status | Approved unrelated failures | Policy |
|---|---|---|---|---|
| `<command>` | package/repo | pass/fail | <none/list> | block/allow/split |

## Assignment Board

| Packet | Owner | State | Readiness/wake event | Minimal check/evidence | Handoff received |
|---|---|---|---|---|---|
| C1 | verifier | pending | immediate | `<command>` | no |
| I1 | impl-1 | blocked | lead wakes after <event> | `<minimal check>` | no |

States: pending, assigned, in-progress, review, remediation, verified, completed, failed.

## Remediation Queue

| ID | Parent | Finding | Severity | Owner | Retry | Escalates to | Status |
|---|---|---|---|---|---|---|---|
| R1 | I1 | <defect> | Major | impl-1 | 1/1 | rescue | pending |

## Evidence Ledger

| Contract/packet | Evidence | Command/result | Reviewer verdict |
|---|---|---|---|
| AC1/C1 | <path/output> | <result> | pending/pass/fail |

## Integration Groups

| Group | Packets | Review | Gate | Commit | Status |
|---|---|---|---|---|---|
| G1 | C1, I1, V1 | pending | `<command>` | pending | pending |

## Event Log

- YYYY-MM-DD HH:MM — lead assigned <packet> to <member> because <readiness event>.
- YYYY-MM-DD HH:MM — reviewer created remediation <ID>; <owner> retry 1/1.
- YYYY-MM-DD HH:MM — lead escalated <ID> to Strong rescue implementer.

## Final Review and Closure

- **Team closure:** <pending/complete>
- **Fresh final reviewer:** external `ultrabrain`
- **Final findings:** <artifact/status>
- **Final remediation:** <none/owner/team>
- **Final gate:** `<command>` → <result>
- **Completion commit/state:** <sha/status>

## Backlog and Requirement Changes

- Lead-only accepted follow-ups: <none/IDs>
- Lead-only approved requirement updates: <none/IDs>
