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
- `tests/README.md` — current canonical test commands, tiers, prerequisites, and individual spec entry points.
