# Repository Architecture

## Repository Purpose
This repository packages a reusable autonomous software-delivery process. It combines process documentation, agent definitions, skills, Nix modules, templates, and verification helpers so another repository can install the tooling and follow the workflow consistently.

## Primary Surfaces
- `docs/` — canonical process and reference documentation.
- `agents/` — agent definitions and preset configuration.
- `skills/` — reusable workflow skills used by the agents.
- `nix/` and `flake.nix` — installation and packaging for Pi/OpenCode integration.
- `templates/` — starter files for downstream repositories.
- `tests/` — shell specs and contract checks for repo integrity and packaging behavior.
- `plans/` — plan artifacts used to change this repository with the same process it teaches.

## Core Flows
1. **Consume the repo**: import the flake module, enable the Pi/OpenCode modules, apply with Home Manager, then use the installed agents and skills.
2. **Read the process**: start in `README.md`, then move into `docs/` for workflow, orchestration, setup, and references.
3. **Change the repo safely**: create or follow a plan in `plans/`, implement one task at a time, and verify through `tests/run-tests.sh`.

## Boundaries and Constraints
- The existing top-level command surface is stable: `./tests/run-tests.sh fast|all|full` remains the verification entry point.
- Repo-local docs are the canonical source for how this repository works; agent prompts and plan artifacts should route to them instead of duplicating policy.
- Nix modules, agent definitions, skills, and tests should evolve together so packaging and documentation stay aligned.
