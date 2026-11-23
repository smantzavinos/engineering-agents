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
- `0002-split-team-planning-pipeline.md` — *(superseded by 0004, then 0006)* branch after approach review into sequential and role-based team planning pipelines.
- `0003-restore-team-mode-throughput-scheduling.md` — *(superseded by 0004, then 0006)* restore DAG/lane-based throughput scheduling, Turn-Exit Contract, bounded-cheap routing, and compact wave ledger in team mode.
- `0004-replace-team-mode-with-code-mode.md` — *(superseded by 0006)* retire team mode; machine-readable task graph and parent-run verification.
- `0005-parallel-dag-fences.md` — *(superseded by 0006)* Pi Parallel: one DAG scheduler, planned fence groups, default one fence at the end.
- `0006-retire-parallel-execution.md` — retire all parallel execution machinery (dynamic workflow, team mode); sequential-first pipeline with opportunistic dispatch; verification classes and execution tiers promoted to canon.
- `0007-frontier-pipeline-on-pi.md` — Pi runs the frontier pipeline (`scope`, `run-plan`, plans with a model); the sequential pipeline is retired for Pi and kept for OpenCode and Hermes.
- `0008-board-pipeline-from-gm-agent-pipeline.md` — adopt the generic board-pipeline improvements from gm-agent-pipeline: one `Your turn` queue with `Waiting for`, board names, one command parser, `review-bot`/`fix-bot`/`needs-human` PR labels, the GitHub Project adapter and board sync, checked bot comments, "Decide, don't ask" and "Finish in task".
- [0009-delegation-through-t3.md](0009-delegation-through-t3.md) — separate terminal and T3 profiles, with shared role definitions, per-machine model sets and manual-only skills.
