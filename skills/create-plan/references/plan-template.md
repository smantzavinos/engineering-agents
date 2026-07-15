# Plan Template

**Status:** draft | approved | in-progress | completed
**Owner:** <name/agent>
**Created:** YYYY-MM-DD
**Related:** <links to brief, approach, findings>

---

## Execution Contract
This plan is meant to be **executed** with strict TDD (Red → Green → Break-it → Verify).

No implementation change without a failing test (or an explicitly documented exception).

---

## Change Summary
- **What changes:** <what will be different after this plan executes>
- **What stays the same:** <explicit non-regressions>
- **Motivation:** <intended user-visible outcome>

## Goals
- [ ] <measurable goal 1>
- [ ] <measurable goal 2>

## Non-goals
- <explicitly out of scope>

## Related Backlog Items

Items outside this plan's executable scope but relevant for context:
- <none | TASK-0001 / #123 — title>

## Related Requirements

If the repo maintains requirements, cite relevant current requirements and approved requirement changes.

- Actors/personas: <ACT-001 | none | N/A>
- Use cases: <UC-001 | none | N/A>
- Workflows/scenarios: <WF-001 | none | N/A>
- Requirement refs: <FR-001, NFR-001, OPR-001 | none | N/A>

## Requirement Updates

Approved requirement changes to apply during execution:

| Requirement change | Applied in task | Notes |
|--------------------|-----------------|-------|
| <none; or add/update/remove FR-001> | <T1> | <update canonical requirements before/with implementation> |

## Impacted Surface Area
- **Entry points affected:** <API routes, CLI commands, UI pages, jobs>
- **Modules/components likely touched:** <paths>
- **External contracts affected:** <DB tables, events, endpoints, shared exports>

## Context
<What exists today, where it lives, constraints that matter>
<Reference approach.md and findings/ for details>

## Constraints
- <time, technology, backwards compatibility, regulatory, etc.>
- <copied or referenced from brief.md>

## Assumptions
- <assumption about codebase, environment, or dependencies>
- <assumption about user behavior or usage patterns>

## Open Questions

| Question | Owner | Resolution |
|----------|-------|------------|
| <unresolved question> | <who decides> | <answer once resolved> |

## Risks & Mitigations

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| <what could go wrong> | high/med/low | high/med/low | <how to reduce or handle> |

## Decisions

| Decision | Options Considered | Chosen | Rationale | Consequences | Revisit If |
|----------|-------------------|--------|-----------|--------------|------------|
| <plan-level decision> | A, B | A | <why> | <tradeoffs> | <when to reconsider> |

## Work Plan

### Task Graph
| ID | Task | Depends on | Touched files | Deliverable | Verification | Status |
|---:|---|---|---|---|---|---|
| T1 | <task> | — | <paths/globs this task writes; `(none)` if it writes no files; omit only if unknown> | <artifact/outcome> | <how to verify> | ⬜ |
| T2 | <task> | T1 | <paths/globs> | <artifact/outcome> | <how to verify> | ⬜ |

> **Touched files** is the write-set each task declares. It is optional for sequential execution but required to enable parallel (team-mode) execution, where tasks are grouped into waves that must be file-disjoint. Prefer explicit paths; globs are allowed. Use `(none)` for a task that writes no files. An undeclared/unknown write-set is treated conservatively (the task runs alone in its own wave).

### Task Details

#### T1: <task name>
**Depends on:** —
**Touched files:** <paths/globs this task writes; `(none)` if none; omit only if unknown>
**Deliverable:** <what exists when done>
**Requirement refs:** <FR-001, NFR-001, OPR-001 | none | N/A>

**TDD checklist:**
- [ ] Add failing test for <specific behavior> in `<path/to/test>`
- [ ] Run `<exact test command>` — confirm failure
- [ ] Implement minimal change in `<path/to/file>` to make test pass
- [ ] Re-run `<exact test command>` — confirm pass
- [ ] **Break-it check:** break <key invariant> in `<file>`, confirm test fails, restore
- [ ] Refactor if needed (tests stay green)
- [ ] Run task completion gate: `<command>`

**Verification scope:**
- Fast feedback: `<command>` — scope: touched-files
- Task completion gate: `<command>` — scope: package-wide

---

#### T2: <task name>
**Depends on:** T1
**Touched files:** <paths/globs this task writes; `(none)` if none; omit only if unknown>
**Deliverable:** <what exists when done>
**Requirement refs:** <FR-001, NFR-001, OPR-001 | none | N/A>

**TDD checklist:**
- [ ] Add failing test for <specific behavior> in `<path/to/test>`
- [ ] Run `<exact test command>` — confirm failure
- [ ] Implement minimal change in `<path/to/file>` to make test pass
- [ ] Re-run `<exact test command>` — confirm pass
- [ ] **Break-it check:** break <key invariant> in `<file>`, confirm test fails, restore
- [ ] Refactor if needed (tests stay green)
- [ ] Run task completion gate: `<command>`

**Verification scope:**
- Fast feedback: `<command>` — scope: touched-files
- Task completion gate: `<command>` — scope: package-wide

---

## Behavior / Coverage Matrix

| Behavior | Source of truth | Primary test layer | Negative/edge cases | Needs E2E? | Regression risk |
|----------|----------------|-------------------|---------------------|------------|-----------------|
| <behavior> | <layer> | <unit/integration> | <cases to test> | yes/no | high/med/low |

## Baseline Gate Audit

| Command | Scope | Baseline status | Related failures? | Notes |
|---------|-------|-----------------|-------------------|-------|
| `<fast command>` | package-wide | ✅ pass / ❌ N failures | yes/no | <context> |
| `<final command>` | repo-wide | ✅ pass / ❌ N failures | yes/no | <context> |

### Gate policy for this plan
<!-- Choose one: block-on-global-gate | allow-scoped-completion | split-follow-up -->
**Policy:** <chosen policy>
**Rationale:** <why this policy fits>

## Verification Plan

### Commands
| Command | Scope | When | What it proves |
|---------|-------|------|----------------|
| `<fast command>` | touched-files | During TDD loops | Current behavior works |
| `<gate command>` | package-wide | Before task completion | No cross-module drift |
| `<final command>` | repo-wide | Before plan completion | Full repo integrity |

### Completion Criteria
- [ ] All tasks marked done
- [ ] All verification gates pass
- [ ] Final gate command passes
- [ ] All coverage matrix rows have tests

## Compatibility & Migration (if applicable)

- **Backwards compatibility:** <what existing consumers/callers are preserved>
- **Forwards compatibility:** <how new code handles old data/formats>
- **Migration steps:** <ordered steps to transition>
- **Rollback strategy:** <how to revert if something goes wrong>

---

## Implementation Notes (update during execution)

### Progress Log
- YYYY-MM-DD: <what changed>

### Evidence Ledger
- YYYY-MM-DD: <claim> — <evidence link/path>

### Deviations
- <what changed from this plan and why>

### Issues Encountered
- <symptom → root cause → fix>

### Follow-ups

Do not add new executable tasks here. Capture accepted follow-ups in the repo backlog and reference their stable IDs.

- <none yet | TASK-0001 / #123 — title, source task/review>
