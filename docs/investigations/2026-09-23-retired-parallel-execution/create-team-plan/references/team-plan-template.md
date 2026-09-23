# Team Plan Template

**Status:** draft | reviewed | approved | in-progress | completed
**Owner:** <name/agent>
**Created:** YYYY-MM-DD
**Mode:** team
**Related:** <brief, findings, approach, approach review>

## Execution Contract

This is the canonical plan for team-mode execution. It was created directly from the
reviewed approach and is not derived from `plan.md`.

## Change Summary

- **What changes:** <outcome>
- **What stays the same:** <non-regressions>
- **Motivation:** <user-visible value>

## Goals

- [ ] <measurable goal>

## Non-goals

- <scope boundary>

## Related Requirements

- <IDs or N/A>

## Requirement Updates

| Change | Task | Lead-owned canonical update |
|---|---|---|
| <none or approved change> | <T1> | <requirements file + lead application point> |

## Context and Constraints

- <facts and boundaries from approach/findings>

## Acceptance Contracts

| ID | Behavior | Evidence | Negative/edge cases | Required before implementation? |
|---|---|---|---|---|
| AC1 | <observable behavior> | <test/assertion> | <cases> | yes/no |

## Frozen Decisions

Every decision the approach deferred is resolved here or assigned to a named `complex`
decision task that blocks its dependents. Verify file locations respect framework import
boundaries (client code must not import server-only modules).

| ID | Decision | Resolution or owning complex task |
|---|---|---|
| D1 | <interface/mechanism/location choice> | <frozen answer, or Tn> |

## Verification Profiles

Exact commands copied from canonical repo docs, named once and referenced everywhere.

| Profile | Commands | Scope | Shared resources |
|---|---|---|---|
| backend-targeted | `<command>` | touched files | none |
| broad-gate | `<commands>` | package/repo | `web-build-output` |

## Resource Locks

| Lock | Resource | Holders |
|---|---|---|
| web-build-output | commands mutating generated build output | broad gates, build |
| local-e2e-harness | shared backend/ports/preview server | E2E tasks |
| shared-route-page | `<path>` serialized ownership | <tasks> |
| git-index | commits | lead only |

## DAG Task Table

The lead feeds this table directly into `team_task_create` with `blockedBy` and lane tags.
Waves are commit checkpoints only; any ready, file-disjoint task may be pulled forward.

| Wave | ID | Lane | Deliverable | Write set | BlockedBy | Contracts | Check profile | Relay successors | Risk |
|---|---|---|---|---|---|---|---|---|---|
| 0 | C1 | [verify] | AC1 contract tests | `<test paths>` | none | AC1 | backend-targeted | I1 | low |
| 1 | I1 | [cheap] | <decision-complete change> | `<paths>` | C1 | AC1 | backend-targeted | I3, reviewer | low |
| 1 | I2 | [complex] | <design-bearing change> | `<paths>` | D1 | AC2 | web-client | I4 | high |

Lanes: `[cheap]` mechanical/bounded-cheap → `unspecified-low`; `[std]` standard →
`unspecified-high`; `[complex]` → `deep`; `[visual]` → `visual-engineering`;
`[verify]` → contract/verifier.

### Complex task details

Detailed prose is required only for `[complex]` (and high-risk `[visual]`/`[std]`) tasks.
Cheap-lane tasks must be fully executable from their table row plus referenced frozen
decisions and contracts.

#### Task I2

- **Frozen decisions consumed:** D1
- **Design notes:** <subtle correctness/state/security concerns>
- **Reviewer checklist:** <contract, scope, quality checks>
- **Retry limit:** 1 local remediation retry
- **Escalation target:** Strong rescue implementer (created on demand)

## Team Roster

| Role | Instances | Routing | Start state |
|---|---|---|---|
| Cheap implementers | <n> | `unspecified-low` | active as tasks allow |
| Standard/complex implementers | <n> | `unspecified-high` / `deep` | active as tasks allow |
| Visual implementer (optional) | 0–1 | `visual-engineering` | replaces one slot when UI work exists |
| Contract/verifier lanes | 1–2 (disjoint test files) | `unspecified-high` or domain | active during contracts |
| Live reviewer | 1 | `unspecified-high` | idle until first handoff |
| Strong rescue implementer | on demand | direct `hephaestus` | created only on escalation |
| Lead | 1 | primary chat | active |
| Final reviewer | 1 | fresh external `deep` (escalate `ultrabrain`) | after team closure |

Instances must cover the maximum simultaneous assignments per role in the DAG table.
No more than four members work concurrently.

## Throughput Summary

- **Critical path:** <task chain>
- **Max ready width per wave:** <wave: width>
- **Role multiplicity check:** <max simultaneous assignments per role vs declared instances>
- **Cheap-lane share:** <n>% of implementation tasks (justify each non-cheap task below 50%)

## Live Review and Remediation Protocol

1. Handoffs go to the live reviewer immediately and are reviewed in arrival order.
2. Reviewer creates a remediation task for each significant defect.
3. Original implementer receives one local retry.
4. Failed retry or high-risk/cross-cutting finding routes to a rescue member created on
   demand.
5. Reviewer marks tasks integration-ready only when significant findings are closed.
6. Review queue cap: 2; overflow shifts an idle verifier (own domain) or a slot to review.

## Wave Commit Gates

| Wave | Tasks | Gate profile | Commit |
|---|---|---|---|
| 1 | C1, I1, I2 | broad-gate | `team(W1): <summary>` |

## Baseline Gate Audit

| Profile | Baseline | Related failures? | Policy |
|---|---|---|---|
| broad-gate | pass/fail | yes/no | block/allow/split |

## Final Verification and Review

- **Lead final gate:** <profile>
- **Fresh final reviewer:** external `deep`, full diff vs `team_plan.md` (escalate to `ultrabrain` only for unusually hard or unique reviews)
- **Final remediation owner:** rescue member or fresh remediation team
- **Completion:** zero open Blocker/Critical/Major findings and final gate satisfied

## Risks and Escalation Triggers

| Trigger | Route |
|---|---|
| first local defect | original implementer, one retry |
| failed retry | Strong rescue implementer (create on demand) |
| ambiguity or architecture/security/migration risk | lead clarification or strong implementation immediately |
| repeated defect class | escalate remaining related tasks |

## Compatibility and Rollback

- <compatibility and rollback rules>
