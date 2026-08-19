# Plan Template

**Status:** draft | approved | in-progress | completed
**Owner:** <name/agent>
**Created:** YYYY-MM-DD
**Related:** <brief.md, approach.md, findings/>

The executable task graph lives in `tasks.json` beside this file, not in prose here.
This document explains *why* and *what*; `tasks.json` defines *what runs*, including
optional fence groups. The installed `dynamic-create-plan/tools/check-plan.mjs` gate
enforces agreement.

---

## Change Summary
- **What changes:** <what is different after this plan executes>
- **What stays the same:** <explicit non-regressions>
- **Motivation:** <intended user-visible outcome>

## Goals
- [ ] <measurable goal>

## Non-goals
- <explicitly out of scope>

## Context & Constraints
<What exists today, where it lives, and the constraints that shape the approach.
Reference approach.md and findings/ rather than restating them.>

## Assumptions
- <assumption that, if wrong, changes the plan>

## Related Requirements

If the repo maintains requirements, cite the current ones this plan touches.

- Requirement refs: <FR-001, NFR-001, OPR-001 | none | N/A>
- Approved requirement changes to apply: <none | add/update/remove FR-001 in task T3>

## Related Backlog Items
- <none | TASK-0001 — title>

## Open Questions

| Question | Owner | Resolution |
|----------|-------|------------|
| <unresolved> | <who decides> | <answer once resolved> |

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| <what could go wrong> | high/med/low | <how to reduce or handle> |

## Decisions

| Decision | Chosen | Rationale | Revisit If |
|----------|--------|-----------|------------|
| <plan-level decision> | <option> | <why> | <trigger> |

## Task Overview

A readable summary of `tasks.json`. Every ID here must exist there, and every task
there must appear here.

| ID | Task | Depends on | Class | Verification |
|---:|------|------------|-------|--------------|
| T1 | <task> | — | contract | `<command>` |
| T2 | <task> | T1 | check | `<command>` |

## Fence Groups

Default: one implicit group (the whole graph). Name extra groups only where later
work must wait for a host verify.

| Group | Tasks | Why this cut |
|-------|-------|--------------|
| shared | T1–T4 | later collect must not start on an unverified tree |
| collect | T5 | — |

Verification classes are defined in [docs/approaches/parallel.md](../docs/approaches/parallel.md).
Choose per task:

- `contract` — new or changed observable behaviour; a failing test is authored first,
  by someone other than the implementer.
- `characterization` — refactor with no behaviour change; existing tests must stay green.
- `check` — config, wiring, generated artifacts, schema; a structural check must pass.
- `none` — prose-only with no structural contract. Legitimate, but choose it explicitly.

## Verification Plan

| Command | Scope | When | What it proves |
|---------|-------|------|----------------|
| `<fast command>` | touched files | during a task | the change works |
| `<gate command>` | package-wide | at a fence | no cross-module drift |
| `<final command>` | repo-wide | before completion | full repo integrity |

**Baseline:** record what already fails before starting, so a pre-existing failure is
never mistaken for a regression.

| Command | Baseline status | Related to this plan? |
|---------|-----------------|-----------------------|
| `<final command>` | ✅ pass / ❌ N failures | yes/no |

## Completion Criteria
- [ ] Every task in `tasks.json` is done
- [ ] The final gate command passes from a clean tree
- [ ] A fresh-context reviewer has read the full diff

## Compatibility & Migration (if applicable)
- **Backwards compatibility:** <what existing callers are preserved>
- **Migration steps:** <ordered steps>
- **Rollback strategy:** <how to revert>

---

Execution progress is not tracked in this file. Fence-group checkpoint commits and
`git log` are the durable record; deviations and follow-ups belong in the repo
backlog with stable IDs.
