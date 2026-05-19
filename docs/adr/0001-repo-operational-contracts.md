# ADR 0001: Add repo-local operational contracts

Status: Accepted
Date: 2026-05-19
Requirement refs: `FR-001`, `FR-002`, `FR-003`, `FR-004`, `NFR-002`, `OPR-001`

## Context
This repository teaches a multi-stage engineering process, but it also needs to model that process locally. Before this decision, several repo-specific operating contracts were missing or scattered:
- no repo-local planning guide under `plans/`
- no lightweight issues/learnings log for recurring execution knowledge
- no ADR index for durable repo-level decisions
- stale override guidance in `agents/README.md` pointing readers toward copied `.pi/agents/` files instead of centralized `agentOverrides`

That made the repo less self-describing than the process it recommends to other repos and increased the risk of drift between docs, execution behavior, and readiness checks.

## Decision
Adopt a repo-local operational contract layer and keep it under executable readiness checks.

This includes:
- a `plans/README.md` guide that tells planners where verification commands, backlog rules, and requirement policies live for this repo
- a `docs/issues_learnings.md` log for recurring issues and reusable learnings
- a `docs/adr/README.md` index plus numbered ADR files for durable repo-level decisions
- root routing updates in `AGENTS.md` and contributor-facing cross-links in `README.md`
- consistent override guidance that prefers `.pi/settings.json` → `subagents.agentOverrides` over copied `.pi/agents/` agent files

## Consequences
### Positive
- Contributors and agents can discover the repo's local operating contract without guessing.
- Planning, verification, backlog capture, and requirement handling stay aligned with the canonical docs introduced by this repo-quality plan.
- The repo now keeps durable lightweight memory (`issues_learnings.md`) separate from durable decisions (`docs/adr/`).
- Stale override guidance is replaced with the lower-maintenance `agentOverrides` path already documented in `docs/orchestration.md`.

### Costs
- More repo-local docs now need to stay in sync with `AGENTS.md`, `README.md`, and the readiness spec.
- Future contract changes should update both the canonical doc and the readiness checks in the same task.
