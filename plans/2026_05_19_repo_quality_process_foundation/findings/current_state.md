# Current State: Repository Quality Process Foundation

**Created:** 2026-05-19
**Plan:** ../brief.md

## Summary
The repository already has strong process content and a working test suite, but it is missing several of the repo-local operational contracts it recommends other repos should have. The gap is not a lack of process guidance; it is the absence of a repo-specific operating layer that turns that guidance into executable, discoverable contracts for this codebase.

## Existing strengths
- `README.md` gives a solid product-level overview of the repository and installation flow.
- `docs/process.md`, `docs/orchestration.md`, `docs/plan-directory-structure.md`, and `docs/repo-setup.md` provide strong process and architectural guidance.
- `docs/agent_architecture_and_workflow.md` explains the multi-agent model and workflow relationships.
- `docs/references/standard-test-levels.md`, `docs/references/task-tracking.md`, and `docs/references/requirements.md` define the process-level contracts this repo wants other repos to follow.
- `tests/README.md`, `tests/run-tests.sh`, and the existing shell specs provide a real verification harness.
- `.pi/settings.json` already uses `subagents.agentOverrides`, which matches the recommended override model.

## Readiness gaps confirmed during assessment
- No root `AGENTS.md` at repo root.
- No repo-specific `docs/backlog.md` or equivalent backlog mechanism.
- No repo-specific `docs/requirements.md` or explicit statement that requirements are not maintained.
- No canonical repo testing strategy document that maps commands to standard levels, scope, and timing.
- No per-directory `AGENTS.md` files in specialized areas such as `agents/`, `skills/`, `tests/`, or `nix/`.
- No `.llm/` instruction files.
- No `plans/README.md`.
- No ADR directory or issues/learnings log.
- No centralized contributor environment doc for prerequisites, auth, and expected tooling.

## Architecture documentation shape today
Architecture is documented, but it is distributed across multiple files rather than anchored by a repo-routing contract:
- `docs/agent_architecture_and_workflow.md` focuses on process and agent interaction diagrams.
- `docs/orchestration.md` focuses on mode behavior and delegation strategy.
- `docs/process.md` focuses on lifecycle execution.
- `docs/repo-setup.md` focuses on what good repos should contain.

This is useful content, but a contributor or autonomous agent does not have a single repo-specific architecture entry point explaining this repo's own boundaries: docs, skills, agents, Nix modules, templates, and tests.

## Testing shape today
The repo has real commands and scripts:
- `./tests/run-tests.sh fast`
- `./tests/run-tests.sh all`
- `./tests/run-tests.sh full`
- targeted spec commands such as `bash tests/specs/repo-structure-spec.sh`

However, the canonical meaning of those commands is spread across `tests/README.md` and the script usage text rather than a dedicated testing strategy doc. The current docs do not yet map commands to:
- fast feedback
- task completion gate
- final gate
- scope labels
- timing guidance
- known environment caveats

## Operational contract drift discovered
`agents/README.md` currently says repos can override models by placing agent files at `.pi/agents/` in the repo root. That conflicts with the repo's own recommended guidance, which prefers `.pi/settings.json` with `subagents.agentOverrides` and explicitly advises against full agent file copies.

## Specialized areas that warrant local guidance
The repo has multiple directories with distinct authoring rules:
- `agents/` — agent frontmatter, role boundaries, and override guidance
- `skills/` — skill structure, references, and process constraints
- `tests/` — shell spec style, fixtures, and verification expectations
- `nix/` — Nix module boundaries and generated package behavior
- `templates/` — starter content and placeholder discipline

These are good candidates for per-directory `AGENTS.md` files.

## Recommended direction from current state
A quality setup should add a repo-specific operating layer rather than rewriting the existing process docs:
1. Add root routing (`AGENTS.md`).
2. Add canonical docs for architecture, coding rules, environment, testing, backlog, requirements, ADRs, plans, and learnings.
3. Add per-directory guidance for specialized authoring areas.
4. Make the presence and consistency of these contracts executable through the test suite.
