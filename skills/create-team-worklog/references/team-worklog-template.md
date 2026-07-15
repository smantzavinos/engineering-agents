# Team Worklog Template

# <Title> — Team Execution Worklog

## Entry-Point Contract

- **Read this file first** every time you resume this team-mode run.
- The execution unit is the **wave**, not the individual task. Execute one wave at a time.
- The live coordination cursor is the OpenCode `team_task_list`; this file is the durable record.
- Only the **lead** runs git and writes this file, `state.json`, and any backlog/requirement docs.
- After a wave completes review + gate: the lead commits the wave, updates this file, advances `Current Wave`, and starts the next wave.

## Mode & Rigor Notes

- This is the **fast lane**. It deliberately trades some rigor for speed. For maximum rigor use sequential execution instead.
- **Break-it check is dropped by default** in this mode. The in-team reviewer's test-adequacy gate is the backstop.
- Commit granularity is **per wave**, not per task.

## References

- Plan: `<relative path to plan.md>`
- Approach: `<relative path to approach.md>`
- Orchestrator skill: `execution-orchestrator-team`

## Completion Criteria

- [ ] All waves below are complete
- [ ] Final cross-wave review is clean
- [ ] Final verification gate passes
- [ ] Team is closed (Closure Sequence run)

## Prerequisites

### Environment Setup
- Required services: <list with start commands>
- Required env vars: <names only>
- Runtime: <versions>
- Team mode enabled: `team_mode.enabled = true` (OpenCode)

## Baseline Gate Audit

| Command | Scope | Baseline status | Notes |
|---------|-------|-----------------|-------|
| `<gate command>` | package-wide | pass/fail | pre-existing failures documented |

## Testing & Verification

| Command | Scope | When to run | What it checks |
|---------|-------|-------------|----------------|
| `<fast command>` | touched-files | By each worker during TDD (Red→Green→Verify) | scoped fast feedback |
| `<gate command>` | package-wide | Once by the lead at each wave end | cross-module drift |
| `<final command>` | repo-wide | Before plan completion | full repo integrity |

### Gate Policy
- Policy: `<block-on-global-gate | allow-scoped-completion | split-follow-up>`
- Workers run only scoped/fast tests; the authoritative package/repo gate runs once, by the lead, at wave end.

## Git Model

- Shared working tree, single committer (the lead). Members never run git.
- Per-wave commit: `wave(N): <summary>` including the wave's code, tests, and this worklog update.
- Conflicts are avoided by file-disjoint wave construction and resolved live via `team_send_message` when unavoidable.

## Backlog Capture Policy

- Repo backlog: `<location/system>`
- Create item procedure: `<how>`
- Stable ID/reference format: `<TASK-XXXX | #123>`
- Routed through the lead only (never concurrent members).

## Requirement Changes (if relevant)

- Repo requirements: `<location>`
- Approved updates from plan: `<none | IDs>`
- Applied through the lead only.

## Wave Manifest

| Wave | Tasks | Depends on waves | Touched files (per task) | Domain(s) |
|-----:|-------|------------------|--------------------------|-----------|
| 1 | T1 | — | T1: `<paths>` | backend/ui |
| 2 | T2, T3 | 1 | T2: `<paths>`; T3: `<paths>` | backend |
| 3 | T4 | 2 | T4: `<paths>` | ui |

- Parallelism score (tasks ÷ waves): `<n>` — recommendation: `<team | sequential>`.

## Current Wave

**Current Wave:** 1

Intra-wave board is the live `team_task_list`. Claim unblocked tasks lowest-ID first.

After a wave completes:
1. Reviewer completes end-of-wave review; lead resolves any open Blocker/Critical/Major.
2. Lead runs the wave gate once.
3. Lead commits: `wave(N): <summary>`.
4. Lead records the wave entry in the Execution Log below and advances Current Wave.
5. Capture accepted backlog/requirement items (lead only).

## Wave Status

- [ ] Wave 1: <tasks>
- [ ] Wave 2: <tasks>
- [ ] Wave 3: <tasks>

## Decisions / Constraints Discovered (append-only)

- <decision or constraint learned during execution>

## Execution Log

### Wave 1 — YYYY-MM-DD
- **Tasks:** <T1 …>
- **Workers:** <member → task>
- **Live review notes:** <per-task findings + fixes>
- **End-of-wave review:** <outcome>
- **Gate:** `<command>` → pass/fail
- **Commit:** `<sha>` — `wave(1): <message>`
- **Backlog/requirement items:** <none | IDs>
- **Notes:** <conflicts resolved, rebalancing, anything notable>
