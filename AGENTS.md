# Project Agent Guide

Use this file as the repo entry point. It routes to the canonical docs for this repository's local working rules.

## Rules
- Keep this file short and routing-oriented; put detailed policy in the linked docs.
- Prefer small, focused changes that preserve the existing command surface.
- Follow strict TDD for non-trivial work: failing test first, minimal fix, break-it check, then verification.

## Tech Stack
- Markdown docs define the process and contributor contract.
- Nix flake modules install and configure Pi and OpenCode.
- Bash and Node-based test helpers verify repo structure and packaging contracts.

## Architecture
- `docs/architecture.md` — repository purpose, primary surfaces, core flows, and boundaries.

## Coding Rules
- `docs/coding-rules.md` — repo-wide editing, shell, documentation, and verification rules.

## Development Environment
- `docs/development-environment.md` — required tooling, setup/apply flow, and verification entry points.

## Test Infrastructure
- `docs/testing-strategy.md` — canonical testing levels, task/final gates, scope, timing, and prerequisites.
- `tests/README.md` — suite inventory, individual spec entry points, and file-layout details.

## Task Tracking
- `docs/backlog.md` — canonical backlog and task-tracking contract for durable non-critical follow-up work.
- Non-critical follow-up work belongs in the backlog with a stable `TASK-XXXX` ID and a source backlink.
- Critical discoveries that affect correctness, safety, scope, or verification must be raised immediately instead of being deferred into backlog-only tracking.

## Requirements
- `docs/requirements.md` — canonical requirements system for the repo's current accepted requirements.
- Stable IDs use `ACT-001`, `UC-001`, `WF-001`, `FR-001`, `NFR-001`, and `OPR-001`.
- Tests cite requirements they verify using `Requirement: FR-001`.
- Draft requirement changes stay in plan artifacts until approved.
- Canonical requirement edits require human approval unless explicitly delegated.
