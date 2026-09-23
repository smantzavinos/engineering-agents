# Retired: parallel execution machinery (2026-09-23)

Archived per ADR 0006 (`docs/adr/0006-retire-parallel-execution.md`). These
files are kept as history and reference material only — they are not part of
any pipeline and must not be routed to from canonical docs, skills, or
harness configs.

## What is here

| Path | Was |
|------|-----|
| `dynamic-create-plan/` | Parallel plan skill (plan.md + tasks.json + DAG) |
| `dynamic-execute-plan/` | Fence-group DAG executor skill |
| `dynamic-review-plan/` | Parallel plan reviewer skill |
| `dynamic-review-code/` | Parallel per-group/final reviewer skill |
| `direct-plan/` | Fast-path glue skill into the dynamic pipeline |
| `create-team-plan/`, `review-team-plan/`, `create-team-worklog/`, `execution-orchestrator-team/` | OpenCode team-mode skills |
| `parallel.md`, `execution-patterns.md` | Canonical docs for the parallel approach (were `docs/approaches/` + `docs/`) |
| `check-plan.mjs`, `wave.mjs` | Plan-gate checker and wave/DAG script builder |

## What survived (and where it lives now)

- **Verification classes** (contract / characterization / check / none) →
  `docs/testing-strategy.md`, canonical for every plan.
- **Baseline gate audits** → plan-creation guidance.
- **Repo-hook referencing** (plans use the repo's documented commands) →
  `docs/coding-rules.md` + plan skills.
- **Execution tiers** (high/low model class per task) → plan template.

Do not edit these files except to fix a broken historical link. Do not
restore them without a new ADR.
