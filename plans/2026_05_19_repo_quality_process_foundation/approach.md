# Approach: Repository Quality Process Foundation

**Created:** 2026-05-19
**Plan:** ./brief.md
**Based on:** ./findings/current_state.md, ./findings/verification_baseline.md

## Solution Model

The work should add a **repo-specific operational contract layer** on top of the repo's already-strong process content.

That layer has five parts:

1. **Root routing and core contributor docs**
   - A root `AGENTS.md` becomes the entry point for autonomous agents.
   - Canonical repo docs explain this repository's architecture, coding rules, environment setup, and testing strategy.

2. **Executable process contracts**
   - Repo-readiness expectations become shell-spec assertions in the existing test suite.
   - Missing or drifting contracts should fail locally instead of being rediscovered during planning or execution.

3. **Durable operational systems**
   - A lightweight Markdown backlog gives the repo a local, agent-executable task-tracking mechanism.
   - A lightweight Markdown requirements doc gives the repo stable IDs for the durable expectations it publishes.

4. **Progressive discovery for specialized areas**
   - Per-directory `AGENTS.md` files explain local rules for agents, skills, tests, Nix modules, and templates.
   - Lightweight `.llm/` files provide focused, reusable instruction snippets where directory-level AGENTS docs would be too broad.

5. **Operational memory and maintenance docs**
   - `plans/README.md`, ADRs, and an issues/learnings log make the repo easier to maintain through repeated plan cycles.
   - Existing docs are aligned so there is one coherent story about verification, model overrides, and process posture.

## Quality Bar

The target is not minimum compliance. The target is a repo that can credibly serve as a reference implementation for the process it teaches.

That means:
- root routing must be clean and concise,
- detailed rules must live in the right local docs,
- backlog and requirements must be concrete enough for agents to execute,
- verification must be trustworthy,
- and docs must agree with one another.

## Key Decisions

| Decision | Options Considered | Chosen | Rationale | Consequences | Revisit If |
|----------|-------------------|--------|-----------|--------------|------------|
| Backlog system | Markdown backlog, GitHub Issues, external tracker | Markdown backlog in `docs/backlog.md` | Simplest durable local system; no auth dependency; fully agent-executable | Manual triage, but low overhead | The repo needs team-scale tracker automation |
| Requirements posture | No separate requirements system, lightweight Markdown system, external requirements tool | Lightweight Markdown requirements in `docs/requirements.md` | This repo publishes durable process/tooling contracts and benefits from stable IDs and explicit approval boundaries | Small ongoing maintenance burden | The repo remains tiny and requirements tracking proves unnecessary |
| Readiness enforcement | Human convention only, README-only guidance, executable tests | Executable shell-spec checks | Prevents drift and dogfoods the process | Requires modest test maintenance | The checks become noisy or brittle |
| Specialized guidance layout | Root-only guidance, per-directory AGENTS only, per-directory AGENTS plus `.llm/` files | Per-directory `AGENTS.md` plus targeted `.llm/` files | Keeps root AGENTS small while improving local discovery | More files to maintain, but clearer structure | The `.llm/` layer adds no value in practice |
| Verification trust model | Accept ambiguous `all` gate, document caveat only, fix the proof-set path and make failures explicit | Fix and codify the repo-wide gate | This repo should not model untrustworthy completion gates | Requires touching test helpers and fixtures | Pi packaging differences become more complex than expected |

## Documentation Architecture

### Root routing
`AGENTS.md` should route to:
- `README.md`
- `docs/architecture.md`
- `docs/coding-rules.md`
- `docs/development-environment.md`
- `docs/testing-strategy.md`
- `docs/backlog.md`
- `docs/requirements.md`
- `plans/README.md`
- per-directory `AGENTS.md` files
- optional `.llm/` guidance

### Core docs
Create or normalize these as the canonical repo docs:
- `docs/architecture.md`
- `docs/coding-rules.md`
- `docs/development-environment.md`
- `docs/testing-strategy.md`
- `docs/backlog.md`
- `docs/requirements.md`
- `docs/issues_learnings.md`
- `docs/adr/README.md`
- `docs/adr/0001-repo-operational-contracts.md`
- `plans/README.md`

### Specialized-area docs
Add per-directory guidance for:
- `agents/AGENTS.md`
- `skills/AGENTS.md`
- `tests/AGENTS.md`
- `nix/AGENTS.md`
- `templates/AGENTS.md`

Add lightweight `.llm/` guidance for:
- `process_docs_rules.txt`
- `nix_rules.txt`

## Verification Strategy

The implementation should use the existing test harness rather than inventing a separate docs linter.

### Fast feedback model
- Add a dedicated readiness-docs shell spec, likely `tests/specs/repo-readiness-docs-spec.sh`.
- Extend it as each documentation cluster is introduced.
- Use that spec as the default fast feedback loop for most tasks in this plan.

### Task gate
Use `./tests/run-tests.sh fast`.

### Final gate
Use `./tests/run-tests.sh all` after the proof-set path issue is fixed or made explicitly actionable.

### Reliability hardening
The proof-set helper should detect the currently installed Pi module package path instead of hardcoding only the legacy namespace. If environment failures remain possible, they must fail or skip explicitly rather than appear as a green completion signal.

## Requirements and Traceability Posture

This plan should establish that the repo **does maintain a lightweight requirements system** because it ships durable process, packaging, and verification behavior.

The initial requirements baseline should stay small and focus on the repo's core contracts:
- contributor/maintainer workflows,
- repo verification expectations,
- packaging and override guidance,
- process-readiness contracts,
- operational clarity around mutating commands.

The plan does not need to retrofit requirement citations across every existing test. It should define the mechanism, apply it to new or materially edited readiness-related tests, and leave broader backfill as a potential follow-up if needed.

## Sequencing Rationale

The work should proceed in this order:
1. create the core routing/doc foundation,
2. define and harden verification,
3. add backlog and requirements systems,
4. add specialized-area guidance,
5. add operational memory docs and consistency cleanups,
6. finish with repo-wide verification.

This order ensures later docs can point to already-existing canonical locations, and it ensures verification trust is addressed before relying on the final gate.

## What Changes vs What Stays

### What changes
- The repo gains a full repo-local operating contract layer.
- Documentation becomes more hierarchical and discoverable.
- Backlog and requirements become concrete, local systems instead of abstract reference concepts only.
- Readiness expectations become executable tests.
- Verification docs and proof-set behavior become more trustworthy.

### What stays the same
- Existing core process documents remain the authoritative source for process theory and workflow behavior.
- Existing repo layout for skills, agents, Nix modules, and tests remains intact.
- Existing test commands remain the base command surface; the work clarifies and hardens them rather than replacing them.
- Agent model overrides continue to use `.pi/settings.json` with `agentOverrides`.

## Risks and Mitigations

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Scope expands into rewriting all existing docs | high | medium | Keep the work focused on operational contracts and targeted consistency edits only |
| New readiness checks become brittle | medium | medium | Prefer existence/link/grep assertions and command-level tests over fragile formatting checks |
| Requirements system adds overhead without benefit | medium | low | Keep the initial baseline deliberately small and tied to durable repo contracts |
| Proof-set fix uncovers deeper Pi packaging variability | medium | medium | Support current and legacy module paths, add regression coverage, and document remaining environment assumptions clearly |
| Docs drift after initial setup | high | medium | Put the new contracts under executable repo-local tests |

## Open Questions

None block planning. The remaining implementation choices are bounded and can be resolved within the planned tasks.
