# Brief — SDP Simplification + Hermes SDP Docs

## Goal
One sequential-first software development pipeline in engineering-agents, with
the retired parallel machinery archived, verification classes promoted to the
canonical testing strategy, per-task execution tiers in plans, and a
`docs/hermes/dev-process.md` so any Hermes agent can run this exact process.

## Rulings (human, ratified 2026-09-23)
- Parallel implementation experiments failed in practice (slower, not faster).
  Default back to sequential implementation.
- Opportunistic parallel only: plans note the dependency graph; the
  orchestrator may launch obviously-independent tasks concurrently. No DAG
  planning, no fences, no write-sets.
- Plans keep a fixed template; tasks reference repo hooks for verification
  commands and declare an execution tier (model class).
- Break-it checks are not a default per-task step (never added observed
  value; added real time). Footnote for high-risk invariants only.
- TDD catches legitimate regressions, not volatile content (config values,
  documentation wording). Verification classes formalize this.
- Hermes agents consume engineering-agents by reading its docs and syncing
  their own native skills — no rendered Hermes skill copies.
- Team-mode is a parallel-execution experiment that did not stick either:
  OpenCode team skills + team-plan artifacts retire alongside the DAG
  machinery (same ADR).
- No universal concurrency cap in the canon: opportunistic-parallel bounds
  are each orchestrator's own policy for its environment.

## Non-goals
- No edits to LLS MVP plan docs (standing ruling).
- No changes to PR #3/#4 review-pipeline content beyond one index row in
  `docs/hermes/README.md`.
- No webhook/cron wiring — the sweep pilot waits until #3/#4 merge.
- Deletion of retirement-target spec files (wave-engine-spec, plan-check-spec)
  is in scope under this brief's ratification; listed explicitly in T5.

## Disposition of approach/research stages
Discovery happened in session (Sep 16–23): content audit of process.md, both
skill families, break-it/TDD spread across 17 files; comparison of my
Hermes-side conventions vs repo canon; two scope rulings via structured
questions. Rulings above are the approach of record; no separate
findings/approach artifacts are generated for this plan.
