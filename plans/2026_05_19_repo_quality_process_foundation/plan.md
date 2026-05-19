# Plan: Repository Quality Process Foundation

**Status:** done
**Owner:** pi planning agent
**Created:** 2026-05-19
**Related:** `./brief.md`, `./approach.md`, `./findings/current_state.md`, `./findings/verification_baseline.md`

---

## Execution Contract
This plan is meant to be **executed** with strict TDD (Red → Green → Break-it → Verify).

No implementation change without a failing test (or an explicitly documented exception).

---

## Change Summary
- **What changes:** The repo gains a complete repo-local operating contract layer: root `AGENTS.md`, canonical architecture/coding/environment/testing docs, a Markdown backlog, a lightweight requirements system, per-directory `AGENTS.md` files, `.llm/` guidance, plans/ADR/learnings docs, and executable readiness checks in the test suite. The proof-set verification path issue is also fixed so repo-wide verification is trustworthy.
- **What stays the same:** Existing process docs, skills, agents, Nix modules, templates, and test runners remain the core product structure. Existing command surfaces (`./tests/run-tests.sh fast|all|full`) remain the main verification entry points.
- **Motivation:** Make this repo itself a high-quality reference implementation of the process it teaches, so autonomous work can proceed safely without undocumented assumptions.

## Goals
- [ ] Add a root routing contract and canonical contributor docs for this repo.
- [ ] Establish concrete backlog and requirements systems with stable IDs and clear approval boundaries.
- [ ] Add specialized-area guidance for the repo's high-signal directories.
- [ ] Turn readiness expectations into executable tests.
- [ ] Make repo-wide verification trustworthy enough to act as a real completion gate.
- [ ] Align existing docs so they tell one coherent story about verification, process posture, and model overrides.

## Non-goals
- Rewriting the existing process methodology docs from scratch.
- Introducing an external backlog or requirements service.
- Performing unrelated feature work in Pi/OpenCode packaging.
- Retrofitting every historical test and doc with exhaustive trace metadata beyond what this plan materially touches.

## Related Backlog Items

Items outside this plan's executable scope but relevant for context:
- none

## Related Requirements

The repo does not yet maintain a canonical requirements system at plan creation time.

- Actors/personas: N/A (to be established in T4)
- Use cases: N/A (to be established in T4)
- Workflows/scenarios: N/A (to be established in T4)
- Requirement refs: N/A (to be established in T4)

## Requirement Updates

Approved requirement changes to apply during execution:

| Requirement change | Applied in task | Notes |
|--------------------|-----------------|-------|
| Introduce canonical Markdown requirements system for this repo | T4 | Establish initial actors, use cases, workflows, FR/NFR/OPR IDs, citation policy, and approval boundary |

## Impacted Surface Area
- **Entry points affected:** root repo docs, `AGENTS.md`, plans directory guidance, repo-local shell specs, proof-set verification helpers
- **Modules/components likely touched:** `README.md`, `agents/README.md`, `docs/`, `tests/`, `agents/`, `skills/`, `nix/`, `templates/`
- **External contracts affected:** contributor verification workflow, repo backlog/requirements process, `.pi/settings.json` override guidance, proof-set verification behavior

## Context
The repo already has strong process and architecture content but lacks the repo-local operational contracts it recommends to other repos. There is no root `AGENTS.md`, no repo backlog, no repo requirements system or explicit posture, no dedicated testing strategy doc mapped to standard levels, and no per-directory `AGENTS.md` files. Existing tests are strong enough to host these contracts, but the repo-wide `all` gate currently has a trust issue because proof-set verification emitted a Pi module entrypoint error while still appearing green during assessment.

## Constraints
- Use existing repo commands as the canonical verification surface; do not invent new top-level commands.
- Keep the root `AGENTS.md` concise and route to deeper docs.
- Prefer local Markdown systems over external services for backlog and requirements.
- Keep readiness checks simple and durable; avoid brittle formatting assertions.
- Resolve the proof-set verification ambiguity before relying on the repo-wide final gate.

## Assumptions
- A lightweight Markdown backlog is sufficient for this repo's scale and collaboration model.
- A lightweight Markdown requirements system is warranted because the repo ships durable process and tooling behavior.
- Adding a dedicated readiness-docs spec is the cleanest way to keep the new docs under test.
- Existing process docs remain mostly valid; the main need is repo-local operational layering and consistency cleanup.

## Open Questions

None at plan creation time.

If implementation reveals broader requirements-citation backfill beyond the touched readiness specs, capture that work as a backlog follow-up instead of expanding this plan's executable scope.

## Risks & Mitigations

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| The work balloons into rewriting broad process docs | high | medium | Keep edits focused on repo-local contracts, links, and targeted consistency fixes |
| Readiness tests become noisy and hard to maintain | medium | medium | Prefer presence, path, and content-anchor assertions over fragile formatting checks |
| Requirements setup feels heavier than the repo needs | medium | low | Keep the initial requirements baseline intentionally small and operationally useful |
| Proof-set fix reveals multiple Pi package namespaces or layouts | medium | medium | Add path-detection logic plus regression coverage for supported layouts |
| Doc inconsistencies remain after new files are added | high | medium | Finish with a dedicated consistency sweep and repo-wide verification |

## Decisions

| Decision | Options Considered | Chosen | Rationale | Consequences | Revisit If |
|----------|-------------------|--------|-----------|--------------|------------|
| Backlog system | Markdown, GitHub Issues, external tracker | Markdown | Lowest-friction durable local system for this repo | Manual movement between states | The repo outgrows local backlog management |
| Requirements posture | none, Markdown, external tool | Markdown | Repo publishes durable contracts and benefits from stable IDs | Some maintenance overhead | Traceability proves unnecessary in practice |
| Readiness enforcement | convention only, executable tests | Executable tests | Prevents drift and dogfoods the repo's own process | Requires spec maintenance | The checks become too brittle |
| Specialized guidance | root-only, per-dir AGENTS, per-dir AGENTS + `.llm/` | per-dir AGENTS + `.llm/` | Best balance of routing clarity and local specificity | More files to maintain | The `.llm/` layer adds negligible value |
| Global gate policy | allow-scoped-completion, split-follow-up, block-on-global-gate | allow-scoped-completion | The repo-wide gate ambiguity is itself an in-scope repair task, so execution can proceed against the reliable fast gate while T2 hardens `all`; final completion still requires the repo-wide gate to pass | Task execution can continue before the repo-wide gate is repaired, but plan completion cannot | The repo-wide gate is proven clean and reliable before most plan work begins |

## Tooling / Contract Surface

This plan changes repo-local verification tooling, so the proof-set verification surface must be treated as a versioned contract during implementation.

### Versioned I/O contract
- Keep the proof-set fixture and snapshot schema at `schemaVersion: 2` throughout this plan.
- `tests/scripts/resource-snapshot.mjs` must continue to emit snapshot JSON with top-level fields `schemaVersion`, `settings`, `proofSet`, `diagnostics`, and `warnings`.
- `tests/fixtures/proof-set.json` and the `tests/spec-fixtures/resource-snapshot.v2*.json` files remain the canonical fixture/snapshot examples for this contract.
- Supporting both the current `@earendil-works/pi-coding-agent` namespace and the legacy `@mariozechner/pi-coding-agent` namespace must not require a schema bump.

### Exit code policy
- `tests/scripts/resource-snapshot.mjs`: `0` = success, `2` = environment failure, `3` = internal failure.
- `tests/test-fast.sh`: `0` = success, `1` = contract failure, `2` = environment failure, `3` = internal failure.
- `tests/scripts/assert-contract.sh`: `0` = success, `1` = contract failure, `2` = environment failure, `3` = internal failure.
- `tests/run-tests.sh`: preserve its documented runner behavior where spec failures return `1` and environment/usage failures return `2`.
- Inability to resolve the Pi module entrypoint when `pi` is present on PATH in a supported local environment is not a warning-only success path.

### Warning taxonomy
- Preserve the current stable warning-code model in `tests/scripts/resource-snapshot.mjs`.
- Any new warning introduced during this plan must use a stable string code, be added to the allowlist, be covered by the proof-set runtime regression spec, and be documented in the touched test helper comments if the behavior is non-obvious.
- Module-entrypoint resolution failure must remain an error path, not a warning code.

### Determinism rules
- Snapshot ordering for package/resource collections touched by this plan must remain deterministic.
- Namespace/path support changes must not introduce nondeterministic warning ordering or fixture drift.
- Any fixture updates in `tests/spec-fixtures/resource-snapshot.v2*.json` must correspond to an intentional contract change covered by the regression spec in the same task.

### File / module skeleton
- `tests/specs/proof-set-runtime-spec.sh` — targeted regression spec for namespace/path resolution, exit-status propagation, warning handling, and deterministic touched output.
- `tests/scripts/resource-snapshot.mjs` — discovers the Pi module entrypoint, loads settings/resources, and emits the snapshot JSON contract.
- `tests/scripts/assert-contract.sh` — validates fixture/snapshot contract invariants.
- `tests/test-fast.sh` — orchestrates read-only proof-set verification.
- `tests/run-tests.sh` — exposes the documented `fast`, `all`, and `full` gates.
- `tests/spec-fixtures/resource-snapshot.v2*.json` — representative snapshot fixtures for contract-oriented regression coverage.

### Acceptance checklist
- [ ] Root/test docs consistently identify `./tests/run-tests.sh fast` as the task gate and `./tests/run-tests.sh all` as the final gate for this plan.
- [ ] `bash tests/specs/proof-set-runtime-spec.sh` covers both supported Pi module namespaces or an explicitly documented unsupported-environment branch.
- [ ] Proof-set environment failures are non-green and explicit.
- [ ] Touched snapshot/fixture outputs remain schema-version-consistent and deterministic.
- [ ] `./tests/run-tests.sh fast` passes after tooling changes.
- [ ] `./tests/run-tests.sh all` passes as the final gate.

## Work Plan

### Task Graph
| ID | Task | Depends on | Deliverable | Verification | Status |
|---:|---|---|---|---|---|
| T1 | Add root routing and core contributor docs | — | Root `AGENTS.md` plus canonical architecture/coding/environment docs and initial readiness spec coverage | `bash tests/specs/repo-readiness-docs-spec.sh`, `./tests/run-tests.sh fast` | ⬜ |
| T2 | Canonicalize testing strategy and fix verification trust gap | T1 | `docs/testing-strategy.md`, updated test docs, and proof-set path/error-handling fix | `bash tests/specs/proof-set-runtime-spec.sh`, `./tests/run-tests.sh fast` | ⬜ |
| T3 | Establish repo backlog/task-tracking contract | T1 | `docs/backlog.md` plus root routing/task-tracking integration and readiness checks | `bash tests/specs/repo-readiness-docs-spec.sh`, `./tests/run-tests.sh fast` | ⬜ |
| T4 | Establish lightweight requirements system | T1, T2, T3 | `docs/requirements.md` plus AGENTS references, traceability rules, and readiness checks | `bash tests/specs/repo-readiness-docs-spec.sh`, `./tests/run-tests.sh fast` | ⬜ |
| T5 | Add specialized-area guidance and `.llm/` instructions | T2, T4 | Per-directory `AGENTS.md` files and `.llm/` instruction files under test | `bash tests/specs/repo-readiness-docs-spec.sh`, `./tests/run-tests.sh fast` | ⬜ |
| T6 | Add operational memory docs and consistency cleanups | T2, T3, T4, T5 | `plans/README.md`, ADRs, learnings log, README/doc consistency fixes, and corrected override guidance | `bash tests/specs/repo-readiness-docs-spec.sh`, `./tests/run-tests.sh fast` | ⬜ |
| T7 | Final consistency sweep and repo-wide verification | T6 | Clean cross-links, passing readiness specs, and trustworthy repo-wide verification evidence | `./tests/run-tests.sh fast`, `./tests/run-tests.sh all` | ⬜ |

### Task Details

#### T1: Add root routing and core contributor docs
**Depends on:** —
**Deliverable:** Root `AGENTS.md`, `docs/architecture.md`, `docs/coding-rules.md`, `docs/development-environment.md`, and an initial readiness-docs spec wired into the fast test suite.
**Requirement refs:** N/A

**TDD checklist:**
- [ ] Add a failing readiness-docs spec in `tests/specs/repo-readiness-docs-spec.sh` asserting the presence of `AGENTS.md`, `docs/architecture.md`, `docs/coding-rules.md`, and `docs/development-environment.md`
- [ ] Update `tests/run-tests.sh` and `tests/README.md` so the new spec is part of the documented fast suite; run `bash tests/specs/repo-readiness-docs-spec.sh` — confirm failure
- [ ] Implement the minimal doc foundation in `AGENTS.md`, `docs/architecture.md`, `docs/coding-rules.md`, and `docs/development-environment.md`
- [ ] Re-run `bash tests/specs/repo-readiness-docs-spec.sh` — confirm pass
- [ ] **Break-it check:** temporarily remove one required root route (for example the architecture or coding-rules route) or one core doc assertion, confirm the spec fails, then restore
- [ ] Refactor wording and links so the root AGENTS doc stays concise and purely routing-oriented
- [ ] Run task completion gate: `./tests/run-tests.sh fast`

**Verification scope:**
- Fast feedback: `bash tests/specs/repo-readiness-docs-spec.sh` — scope: touched-files
- Task completion gate: `./tests/run-tests.sh fast` — scope: package-wide

---

#### T2: Canonicalize testing strategy and fix verification trust gap
**Depends on:** T1
**Deliverable:** `docs/testing-strategy.md`, updated references from `AGENTS.md`/`tests/README.md`, a proof-set runtime regression spec wired into the fast suite, and a fix for the current Pi module entrypoint/path handling in proof-set verification.
**Requirement refs:** N/A

**Proof-set runtime contract for this task:**
- `tests/specs/proof-set-runtime-spec.sh` must cover both the current `@earendil-works/pi-coding-agent` module path and the legacy `@mariozechner/pi-coding-agent` module path.
- When `pi` is present on PATH in a supported local environment, inability to resolve the Pi module entrypoint is a non-zero environment failure, not a warning-only success.
- If any skip path remains for unsupported environments, the runner output must state it explicitly and must not be reported as a green verification pass.
- The snapshot fixture schema remains `resource-snapshot.v2`; any schema or namespace expectation change must update the affected `tests/spec-fixtures/resource-snapshot.v2*.json` fixtures and the regression spec in the same task.

**TDD checklist:**
- [ ] Add a failing regression spec in `tests/specs/proof-set-runtime-spec.sh` that exercises `tests/scripts/resource-snapshot.mjs` against the supported Pi module package-name layouts and fails on the currently hardcoded legacy-only behavior, incorrect exit-status propagation, or nondeterministic touched output ordering
- [ ] Update `tests/run-tests.sh` and `tests/README.md` so the new proof-set runtime spec is part of the documented fast suite
- [ ] Extend `tests/specs/repo-readiness-docs-spec.sh` with assertions for `docs/testing-strategy.md` and its key anchors (standard-level mapping, scope, timing, prerequisites, task/final gates); run `bash tests/specs/proof-set-runtime-spec.sh` and `bash tests/specs/repo-readiness-docs-spec.sh` — confirm failure
- [ ] Implement `docs/testing-strategy.md` using the existing command surface (`./tests/run-tests.sh fast|all|full`, targeted shell specs) and update `AGENTS.md`/`tests/README.md` to treat it as canonical
- [ ] Update `tests/scripts/resource-snapshot.mjs` to detect the current Pi module package path(s), preserve the documented exit-code and warning taxonomy rules, and adjust `tests/test-fast.sh`, `tests/run-tests.sh`, and any affected `tests/spec-fixtures/resource-snapshot.v2*.json` files so proof-set environment failures fail or skip explicitly instead of appearing green
- [ ] Re-run `bash tests/specs/proof-set-runtime-spec.sh` and `bash tests/specs/repo-readiness-docs-spec.sh` — confirm pass
- [ ] **Break-it check:** temporarily force the helper back to the legacy-only module path or remove the testing-strategy gate mapping, confirm the new regression/spec fails, then restore
- [ ] Refactor doc wording and helper code for clarity without changing behavior
- [ ] Run task completion gate: `./tests/run-tests.sh fast`

**Verification scope:**
- Fast feedback: `bash tests/specs/proof-set-runtime-spec.sh` — scope: touched-files
- Task completion gate: `./tests/run-tests.sh fast` — scope: package-wide

---

#### T3: Establish repo backlog/task-tracking contract
**Depends on:** T1
**Deliverable:** `docs/backlog.md` with full operations table and item template, plus root `AGENTS.md` task-tracking routing and readiness-spec coverage.
**Requirement refs:** none

**TDD checklist:**
- [ ] Extend `tests/specs/repo-readiness-docs-spec.sh` with failing assertions for `docs/backlog.md`, required task-tracking hooks, stable ID format, source backlink rule, and `AGENTS.md` task-tracking routing
- [ ] Run `bash tests/specs/repo-readiness-docs-spec.sh` — confirm failure
- [ ] Implement `docs/backlog.md` as the canonical Markdown backlog for this repo, including `TASK-XXXX` IDs, operations table, source backlink format, and lifecycle sections
- [ ] Update `AGENTS.md` to point to `docs/backlog.md` and state the capture policy for non-critical vs critical discoveries
- [ ] Re-run `bash tests/specs/repo-readiness-docs-spec.sh` — confirm pass
- [ ] **Break-it check:** temporarily remove a required operation such as `List Up next` or the source backlink rule, confirm the spec fails, then restore
- [ ] Refactor section wording so the backlog remains an operational contract rather than a generic template dump
- [ ] Run task completion gate: `./tests/run-tests.sh fast`

**Verification scope:**
- Fast feedback: `bash tests/specs/repo-readiness-docs-spec.sh` — scope: touched-files
- Task completion gate: `./tests/run-tests.sh fast` — scope: package-wide

---

#### T4: Establish lightweight requirements system
**Depends on:** T1, T2, T3
**Deliverable:** `docs/requirements.md` with initial actors/use cases/workflows/FR/NFR/OPR entries, traceability and approval rules, root `AGENTS.md` requirements routing, and readiness-spec coverage.
**Requirement refs:** none (this task establishes the system)

**TDD checklist:**
- [ ] Extend `tests/specs/repo-readiness-docs-spec.sh` with failing assertions for `docs/requirements.md`, required hooks (store, IDs, citation format, approval boundary, validation/query guidance), and `AGENTS.md` requirements routing
- [ ] Add failing assertions in `tests/specs/repo-readiness-docs-spec.sh` and `tests/specs/proof-set-runtime-spec.sh` for the `Requirement:` citation format used by the new or materially edited readiness-related tests where appropriate
- [ ] Run `bash tests/specs/repo-readiness-docs-spec.sh` — confirm failure
- [ ] Implement `docs/requirements.md` with a small initial baseline for maintainer/contributor/end-user workflows and explicit traceability rules
- [ ] Update `AGENTS.md` to declare the requirements system, ID prefixes, approval policy, and test citation rule
- [ ] Apply requirement citations to `tests/specs/repo-readiness-docs-spec.sh`, `tests/specs/proof-set-runtime-spec.sh`, and any other materially edited readiness-related tests touched by this plan
- [ ] Re-run `bash tests/specs/repo-readiness-docs-spec.sh` — confirm pass
- [ ] **Break-it check:** temporarily remove the approval policy or stable ID guidance, confirm the spec fails, then restore
- [ ] Refactor the requirements wording so the initial baseline stays compact and durable
- [ ] Run task completion gate: `./tests/run-tests.sh fast`

**Verification scope:**
- Fast feedback: `bash tests/specs/repo-readiness-docs-spec.sh` — scope: touched-files
- Task completion gate: `./tests/run-tests.sh fast` — scope: package-wide

---

#### T5: Add specialized-area guidance and `.llm/` instructions
**Depends on:** T2, T4
**Deliverable:** `agents/AGENTS.md`, `skills/AGENTS.md`, `tests/AGENTS.md`, `nix/AGENTS.md`, `templates/AGENTS.md`, `.llm/process_docs_rules.txt`, `.llm/nix_rules.txt`, and updated root routing/spec coverage.
**Requirement refs:** FR/NFR/OPR from T4 once established

**TDD checklist:**
- [ ] Extend `tests/specs/repo-readiness-docs-spec.sh` with failing assertions for the per-directory `AGENTS.md` files, `.llm/` files, and root `AGENTS.md` links to them
- [ ] Run `bash tests/specs/repo-readiness-docs-spec.sh` — confirm failure
- [ ] Implement the per-directory guidance files with local patterns, anti-patterns, and navigation rules for `agents/`, `skills/`, `tests/`, `nix/`, and `templates/`
- [ ] Implement `.llm/process_docs_rules.txt` and `.llm/nix_rules.txt` with concise “when to read” guidance from the root AGENTS doc
- [ ] Re-run `bash tests/specs/repo-readiness-docs-spec.sh` — confirm pass
- [ ] **Break-it check:** temporarily remove one per-directory route or one anti-pattern section, confirm the spec fails, then restore
- [ ] Refactor for consistency of voice and formatting across the local guidance files
- [ ] Run task completion gate: `./tests/run-tests.sh fast`

**Verification scope:**
- Fast feedback: `bash tests/specs/repo-readiness-docs-spec.sh` — scope: touched-files
- Task completion gate: `./tests/run-tests.sh fast` — scope: package-wide

---

#### T6: Add operational memory docs and consistency cleanups
**Depends on:** T2, T3, T4, T5
**Deliverable:** `plans/README.md`, `docs/issues_learnings.md`, `docs/adr/README.md`, `docs/adr/0001-repo-operational-contracts.md`, README cross-links, and removal of conflicting guidance such as the current `.pi/agents/` override recommendation in `agents/README.md`.
**Requirement refs:** use the IDs established in T4 where relevant

**TDD checklist:**
- [ ] Extend `tests/specs/repo-readiness-docs-spec.sh` with failing assertions for `plans/README.md`, ADR docs, issues/learnings log, and the absence of stale `.pi/agents/` override guidance in `agents/README.md`
- [ ] Run `bash tests/specs/repo-readiness-docs-spec.sh` — confirm failure
- [ ] Implement `plans/README.md`, `docs/issues_learnings.md`, `docs/adr/README.md`, and `docs/adr/0001-repo-operational-contracts.md`
- [ ] Update `README.md`, `agents/README.md`, `AGENTS.md`, `docs/testing-strategy.md`, `docs/backlog.md`, `docs/requirements.md`, and any other touched docs so links and guidance are consistent with `agentOverrides`, the new testing strategy, backlog, and requirements docs
- [ ] Re-run `bash tests/specs/repo-readiness-docs-spec.sh` — confirm pass
- [ ] **Break-it check:** temporarily restore the stale `.pi/agents/` guidance or remove one new operational doc link, confirm the spec fails, then restore
- [ ] Refactor docs so cross-links remain concise and non-duplicative
- [ ] Run task completion gate: `./tests/run-tests.sh fast`

**Verification scope:**
- Fast feedback: `bash tests/specs/repo-readiness-docs-spec.sh` — scope: touched-files
- Task completion gate: `./tests/run-tests.sh fast` — scope: package-wide

---

#### T7: Final consistency sweep and repo-wide verification
**Depends on:** T6
**Deliverable:** A coherent doc/test surface with passing readiness checks, a trustworthy repo-wide `all` gate, and execution evidence recorded in the worklog during implementation.
**Requirement refs:** IDs established in T4 as applicable

**TDD checklist:**
- [ ] Add any final failing readiness assertions needed to cover cross-link integrity and canonical doc references discovered during implementation
- [ ] Run `./tests/run-tests.sh fast` — confirm any final failures before cleanup
- [ ] Implement the minimal remaining consistency edits across `AGENTS.md`, `README.md`, touched `docs/` files, touched `tests/` specs, and `tests/scripts/resource-snapshot.mjs` so the fast suite is fully green
- [ ] Re-run `./tests/run-tests.sh fast` — confirm pass
- [ ] Run `./tests/run-tests.sh all` — confirm the repo-wide gate is trustworthy and green, or fails/skips explicitly for documented reasons
- [ ] **Break-it check:** temporarily reintroduce one high-value inconsistency (for example a stale AGENTS route or proof-set helper path assumption), confirm the relevant spec/gate fails, then restore
- [ ] Refactor any duplicated wording uncovered during the sweep
- [ ] Run final gate: `./tests/run-tests.sh all`

**Verification scope:**
- Fast feedback: `./tests/run-tests.sh fast` — scope: package-wide
- Task completion gate: `./tests/run-tests.sh fast` — scope: package-wide

---

## Behavior / Coverage Matrix

| Behavior | Source of truth | Primary test layer | Negative/edge cases | Needs E2E? | Regression risk |
|----------|----------------|-------------------|---------------------|------------|-----------------|
| Root agent entry point routes to the correct repo-specific docs | `AGENTS.md` + canonical docs | repo-local shell spec | Missing route, wrong path, missing section anchor | no | high |
| Canonical testing strategy maps commands to standard levels, scope, timing, and prerequisites | `docs/testing-strategy.md` | repo-local shell spec | Missing level, stale command, mismatched gate designation | no | high |
| Repo backlog operations are agent-executable with stable IDs and source backlinks | `docs/backlog.md` | repo-local shell spec | Missing `Up next`, missing source backlink rule, incomplete lifecycle ops | no | medium |
| Repo requirements are durable and citeable with explicit approval boundaries | `docs/requirements.md` | repo-local shell spec + touched readiness tests | Missing ID scheme, missing citation rule, ambiguous approval policy | no | medium |
| Specialized areas expose local guidance instead of overloading the root doc | per-directory `AGENTS.md` + `.llm/` files | repo-local shell spec | Missing local guide, stale root route, no anti-pattern guidance | no | medium |
| Proof-set verification resolves the active Pi module package path and surfaces failures honestly | `tests/scripts/resource-snapshot.mjs`, `tests/test-fast.sh`, `tests/run-tests.sh` | targeted runtime regression spec + repo-wide gate | Legacy-only path support, silent success on environment failure, unsupported namespace | no | high |
| Override guidance consistently prefers `agentOverrides` over copied `.pi/agents/*.md` files | `docs/orchestration.md`, `agents/README.md`, root `AGENTS.md` | repo-local shell spec | Stale conflicting README text remains | no | medium |

## Bad-test avoidance

The readiness-related tests added or edited by this plan must not be satisfiable by file-exists checks alone.

The plan requires:
- `tests/specs/repo-readiness-docs-spec.sh` to assert key contract anchors and selected contradictory/stale guidance, not just file presence.
- `tests/specs/proof-set-runtime-spec.sh` to exercise namespace/path-resolution behavior and failure propagation, not just fixture existence.
- readiness docs to be tested through the canonical runners (`./tests/run-tests.sh fast` and `./tests/run-tests.sh all`) so false-green local-only checks do not mask integration drift.
- requirement-citation checks, once introduced in T4, to verify actual citation format in materially edited readiness specs rather than relying on prose-only documentation.

Insufficient tests for this plan include tautological file-presence assertions, source-reading checks that never exercise runner behavior, and snapshot updates without a behavioral regression assertion.

## Baseline Gate Audit

| Command | Scope | Baseline status | Related failures? | Notes |
|---------|-------|-----------------|-------------------|-------|
| `bash tests/specs/repo-structure-spec.sh` | package-wide | ✅ pass | no | Passed during assessment on 2026-05-19 |
| `./tests/run-tests.sh fast` | package-wide | ✅ pass | no | Passed during assessment on 2026-05-19 |
| `./tests/run-tests.sh all` | repo-wide | ❌ ambiguous | yes | Reported overall success during assessment while proof-set verification emitted `Unable to locate Pi module entrypoint .../@mariozechner/pi-coding-agent/dist/index.js`; this is in-scope and must be fixed |

### Gate policy for this plan
**Policy:** allow-scoped-completion
**Rationale:** The repo-wide `all` gate ambiguity is itself part of this plan's scope and is addressed early in T2. Until that repair lands, the reliable task gate is `./tests/run-tests.sh fast`. The plan still requires `./tests/run-tests.sh all` to pass before completion, so repo-wide verification trust is restored before the work is considered done.

## Verification Plan

### Commands
| Command | Scope | When | What it proves |
|---------|-------|------|----------------|
| `bash tests/specs/repo-readiness-docs-spec.sh` | touched-files | During TDD loops | The repo-local operational contract docs and routes required for this plan exist and contain key anchors |
| `bash tests/specs/proof-set-runtime-spec.sh` | touched-files | During TDD loops for verification-hardening work | The proof-set helper resolves supported Pi module layouts and fails correctly on broken assumptions |
| `./tests/run-tests.sh fast` | package-wide | Before task completion | The repo-local shell spec suite still passes after each documentation and helper change |
| `./tests/run-tests.sh all` | repo-wide | Before plan completion | The repo's broader verification surface, including flake evaluation and proof-set verification, is trustworthy and green |
| `./tests/run-tests.sh full` | repo-wide | Optional release smoke after plan completion | Pi CLI smoke checks still work once the main gates are green |

### Completion Criteria
- [ ] All tasks marked done
- [ ] All verification gates pass
- [ ] Final gate command passes
- [ ] All coverage matrix rows have tests or explicit shell-spec coverage
- [ ] Root `AGENTS.md` routes to all canonical docs and local guidance files introduced by this plan
- [ ] Backlog and requirements mechanisms are documented as agent-executable systems for this repo

## Compatibility & Migration (if applicable)

- **Backwards compatibility:** Existing repo layout, skills, agents, modules, and command names remain intact; the work adds routing and contracts rather than restructuring the project.
- **Forwards compatibility:** New plans and reviews can cite backlog IDs and requirement IDs immediately after these docs land.
- **Migration steps:** Introduce canonical docs first, then route to them from `AGENTS.md`, then keep them under test so later edits preserve the contract.
- **Rollback strategy:** If a specific new doc or spec proves too brittle, revert the narrow change while keeping the broader routing model intact; do not roll back to an undocumented state silently.

---

## Implementation Notes (update during execution)

### Progress Log
- 2026-05-19: Plan created from repo assessment and follow-up direction to produce a quality, process-ready setup rather than minimum compliance.

### Evidence Ledger
- 2026-05-19: Readiness assessment completed — evidence: root repo scan, `README.md`, `docs/process.md`, `docs/orchestration.md`, `docs/repo-setup.md`, `tests/README.md`, `.pi/settings.json`, `./tests/run-tests.sh fast`, `./tests/run-tests.sh all`
- 2026-05-19: Proof-set gate trust issue identified — evidence: assessment output from `./tests/run-tests.sh all` showing legacy `@mariozechner/pi-coding-agent` path assumption

### Deviations
- none yet

### Issues Encountered
- none yet

### Follow-ups

Do not add new executable tasks here. Capture accepted follow-ups in the repo backlog and reference their stable IDs.

- none yet
