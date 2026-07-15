# ADR 0002: Split sequential and team planning after approach review

Status: Accepted

Date: 2026-07-15

Requirement refs: FR-007, FR-008, NFR-003, OPR-003

## Context

Sequential execution plans optimize individual tasks for strict TDD, per-task verification,
and per-task commits. Team execution needs early acceptance contracts, parallel file
ownership, role/model routing, live remediation, bounded escalation, and integration-group
gates. Creating a sequential plan and then compiling it into a team plan duplicates work and
preserves the wrong task boundaries.

## Decision

Discovery, research, approach, and approach review remain shared. After approach review,
execution branches:

- sequential planning creates `plan.md` and `plan_review.md`
- team planning creates `team_plan.md` and `team_plan_review.md`

Team execution uses a lead-owned role pipeline with up to three fast implementers, an idle
Strong rescue implementer, a contract/verifier, a cost-controlled live reviewer, and a fresh
strong final reviewer after team closure.

## Consequences

- New `create-team-plan` and `review-team-plan` skills are required.
- Team worklogs consume `team_plan.md`, not `plan.md`.
- Sequential plan skills remain strict-TDD-specific.
- Team readiness checks must cover no-polling coordination, four active slots, early
  contracts, one-retry escalation, and independent final review.
- Documentation and generated OpenCode skills must expose the split consistently.
