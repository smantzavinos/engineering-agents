# Architecture Decision Records

This directory stores accepted and historical architecture decision records (ADRs) for this repository's own operating contracts, tooling posture, and durable structural choices.

Use an ADR when the repo needs a durable decision record with context, alternatives, and consequences. Use `docs/issues_learnings.md` for lightweight operational memory that has not yet become a durable decision.

## ADR File Format
Each ADR should use a numbered filename such as `0001-short-slug.md` and keep the same high-signal structure:
- Title line: `# ADR 0001: Short decision name`
- Status line: `Status: Proposed|Accepted|Superseded`
- Date line: decision date
- `Requirement refs:` when the decision supports or changes durable requirement IDs
- `## Context`
- `## Decision`
- `## Consequences`

Keep ADRs concise, decision-oriented, and explicit about what changes for future contributors.

## Lifecycle
- **Proposed** — under consideration; not yet the repo's binding direction.
- **Accepted** — current approved direction.
- **Superseded** — replaced by a later ADR; keep the historical record and point to the replacement.

When a decision becomes stale, add a superseding ADR instead of deleting the old one.

## Index
- `0001-repo-operational-contracts.md` — adopt repo-local operational contracts, readiness checks, and centralized `agentOverrides` guidance.
- `0002-split-team-planning-pipeline.md` — branch after approach review into sequential and role-based team planning pipelines.
- `0003-restore-team-mode-throughput-scheduling.md` — restore DAG/lane-based throughput scheduling, Turn-Exit Contract, bounded-cheap routing, and compact wave ledger in team mode.
