# ADR 0003: Restore throughput scheduling in team mode

Status: Accepted

Date: 2026-07-17

Requirement refs: FR-008, NFR-003

Amends: ADR 0002 (the pipeline split stands; the coordination model changes)

## Context

The July 15 role-oriented rewrite (ADR 0002) made the primary-chat lead the sole scheduler
and prohibited members from self-selecting work or checking the task board. An observed
production run (Atlas Sequence Page UX Cleanup, investigated 2026-07-17) showed the result:
every dependency transition required a fresh lead turn, the user acted as the scheduling
watchdog, a single verifier and a single visual implementer serialized the critical path,
almost no implementation reached cheap model routes, dormant members amplified runtime
failures, and the duplicated worklog drifted from reality. Healthy parallel workers completed
packets in ~10 minutes; most wall-clock time was dispatch latency and recovery.

## Decision

Retain the quality control plane (acceptance contracts, file ownership, independent
verification, live review, bounded escalation, fresh final review) and restore a throughput
control plane:

- The lead pre-creates the full task DAG on the team board (`blockedBy` + lane tags
  `[cheap]/[std]/[complex]/[visual]/[verify]`) at team creation.
- Lane-scoped claims: after completing a task, a member checks the board once and claims the
  oldest ready, file-disjoint task in its own lane. Timer polling remains prohibited.
- Relay dispatch: each packet names successors; the completing member notifies them directly.
- Turn-Exit Contract: the lead never ends a turn with a ready task undispatched, nudges a
  member silent across two turns, and restarts the member (not the team) on a third.
- New `bounded-cheap` implementer class on `unspecified-low`: decision-complete multi-file
  work qualifies; deferring design decisions into cheap packets is forbidden. Plans carry a
  Frozen Decisions section, resource locks, named verification profiles, and a throughput
  summary (critical path, ready width, role multiplicity, cheap-lane share).
- One or two verifier lanes on disjoint test files, each publishing contracts immediately.
- The Strong rescue implementer is created on escalation, not declared dormant.
- The team worklog becomes a compact wave ledger; per-task state lives on the team board.
- Waves are commit checkpoints, not scheduling barriers; ready work is pulled forward.

## Consequences

- `create-team-plan`, `review-team-plan`, `create-team-worklog`,
  `execution-orchestrator-team`, their templates, and `docs/team-mode-execution.md` were
  rewritten accordingly.
- `review-team-plan` now blocks on role-multiplicity overcommit, cheap packets with unfrozen
  decisions, and invalid client/server import boundaries, and flags missed pull-forward,
  under-utilized lanes, unlocked shared resources, and duplicated broad gates.
- FR-008 and NFR-003 were updated to reflect lane-scoped claims and the Turn-Exit Contract.
- Runtime capabilities (task leases, automatic `blockedBy` notifications, per-member restart
  APIs, model fallback, stale-lock recovery) remain upstream asks; skills approximate them
  with lead-turn heuristics until available.
- Deployed installs consume these skills via generated dist output; changes take effect only
  after rebuild/redeploy.
