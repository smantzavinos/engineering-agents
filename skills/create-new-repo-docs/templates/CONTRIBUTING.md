# Contributing to <Project Name>

## Purpose
This document explains how contributors should work in this repository.

## Development principles
- Keep changes aligned with documented user workflows.
- Preserve requirement traceability from `docs/requirements.md` into tests.
- Update docs when behavior, workflows, or architecture decisions change.
- Prefer small, reviewable changes.

## Repo map
- `README.md` — project overview and quick start
- `docs/architecture.md` — system boundaries and design decisions
- `docs/requirements.md` — tagged requirements and acceptance criteria
- `docs/testing-strategy.md` — test levels, tools, and commands
- `docs/workflows/` — user workflow documentation
- `docs/adr/` — architectural decision records

## Local setup
### Prerequisites
- <tool/runtime 1>
- <tool/runtime 2>

### Install / bootstrap
```bash
<install command>
<bootstrap command>
```

## Development workflow
1. Review the affected workflow docs and requirements.
2. Make the smallest change that satisfies the requirement.
3. Update or add tests according to `docs/testing-strategy.md`.
4. Run the required verification commands.
5. Update documentation if behavior or contracts changed.

## Verification commands
```bash
<unit test command>
<integration test command>
<e2e test command>
<lint command>
<typecheck command>
<build command>
```

## Pull request expectations
- Link the affected requirement IDs.
- Note which user workflow(s) changed.
- Summarize test evidence.
- Call out any ADR-worthy decisions.

## Documentation update triggers
Update docs when any of the following changes:
- user-visible workflow
- architecture boundaries
- requirements or acceptance criteria
- testing strategy or verification commands
- setup or contributor workflow
