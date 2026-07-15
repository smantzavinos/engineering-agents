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

| Change | Implementation packet | Lead-owned canonical update |
|---|---|---|
| <none or approved change> | <I1> | <requirements file + lead application point> |

## Context and Constraints

- <facts and boundaries from approach/findings>

## Acceptance Contracts

| ID | Behavior | Evidence | Negative/edge cases | Required before implementation? |
|---|---|---|---|---|
| AC1 | <observable behavior> | <test/assertion> | <cases> | yes/no |

## Team Roster

Use one `visual-engineering` member in place of a general implementation slot whenever any
packet owns UI components, styling, interaction, accessibility, responsive behavior, or
visual verification.

| Role | Default routing | Start state | Responsibilities |
|---|---|---|---|
| Implementation slots (up to 3) | `quick`, `unspecified-high`, or domain category | active as packets allow | speed-run owned files; minimal checks only |
| Visual implementer (optional) | `visual-engineering` | active when UI packets exist | replaces one general slot; UI/UX/a11y/visual work |
| Strong rescue implementer | direct `hephaestus` | idle | high-risk packets and escalations |
| Contract/verifier | `unspecified-high` or domain category | active for contract stage | read acceptance context; own test files; author early behavioral tests; record baseline/red and targeted evidence; classify failures; never fix production code |
| Live reviewer | `unspecified-high` | idle until first handoff | review handoffs; create remediation packets |
| Lead | primary chat | active | schedule, wake roles, gates, commits, lifecycle |
| Final reviewer | fresh external `ultrabrain` | not spawned yet | full independent final review |

## Acceptance Contract Packets

| ID | Contracts | Files owned | Readiness | Minimal command | Expected initial evidence | Status |
|---|---|---|---|---|---|---|
| C1 | AC1 | `<test paths>` | immediate | `<targeted command>` | red/pass baseline | ⬜ |

## Implementation Packets

| ID | Deliverable | Depends on | Role/domain | Risk | Model tier | Files owned | Minimal check | Contracts | Integration group | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| I1 | <coherent change> | C1 | fast/backend | low | cheap | `<paths>` | `<format/LSP/targeted smoke>` | AC1 | G1 | ⬜ |

### Packet I1

- **Readiness event:** <what wakes the implementer>
- **Files owned:** <exclusive write-set>
- **Deliverable:** <observable artifact>
- **Minimal check:** <one cheap command or explicit none-with-rationale>
- **Handoff:** changed files, assumptions, command result, known risks
- **Live reviewer checklist:** <contract, scope, quality checks>
- **Retry limit:** 1 local remediation retry
- **Escalation target:** Strong rescue implementer

## Verification Packets

| ID | Trigger | Evidence | Command | Owner | Blocks |
|---|---|---|---|---|---|
| V1 | I1 reviewed | AC1 | `<targeted command>` | contract/verifier | G1 |

## Live Review and Remediation Protocol

1. Lead wakes live reviewer when a handoff arrives.
2. Reviewer checks the packet diff against its contracts and checklist.
3. Reviewer creates a remediation packet for each significant defect.
4. Original implementer receives one local retry.
5. Failed retry or high-risk/cross-cutting finding routes to Strong rescue implementer.
6. Reviewer marks the packet integration-ready only when significant findings are closed.

## Active Slot Schedule

| Stage | Active slots (max 4) | Idle/wake behavior |
|---|---|---|
| Contract | verifier + up to 3 ready implementers | reviewer/rescue idle until messaged |
| Build/review | up to 3 implementers + live reviewer | verifier sleeps after contracts |
| Remediation | selected implementers + reviewer; rescue replaces one fast slot | lead wakes only assigned roles |
| Verification | verifier + reviewer/needed implementers | unassigned roles idle |

## Integration Groups

| Group | Packets | Readiness | Lead gate | Commit |
|---|---|---|---|---|
| G1 | C1, I1, V1 | reviewed + verified | `<package/repo command>` | `team(G1): <summary>` |

## Baseline Gate Audit

| Command | Scope | Baseline | Related failures? | Policy |
|---|---|---|---|---|
| `<command>` | package/repo | pass/fail | yes/no | block/allow/split |

## Final Verification and Review

- **Lead final gate:** `<command>`
- **Fresh final reviewer:** external `ultrabrain`, full diff vs `team_plan.md`
- **Final remediation owner:** Strong rescue implementer or fresh remediation team
- **Completion:** zero open Blocker/Critical/Major findings and final gate satisfied

## Risks and Escalation Triggers

| Trigger | Route |
|---|---|
| first local defect | original implementer, one retry |
| failed retry | Strong rescue implementer |
| ambiguity or architecture/security/migration risk | lead clarification or strong implementation immediately |
| repeated defect class | escalate remaining related packets |

## Compatibility and Rollback

- <compatibility and rollback rules>

## Execution Notes

- <lead-owned deviations, evidence, and decisions>
