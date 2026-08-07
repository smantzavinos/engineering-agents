# Findings: Crew substrate review and dispatch behavior

**Source inspected:** installed `pi-messenger` package source at
`~/.pi/agent/packages/pi-messenger/_source` (the managed install of the pinned v0.15.0 line).
Complements `docs/investigations/2026-07-31-plan-execution-efficiency/notes/crew-execution-model.md`.
Line references are approximate against that source tree.

## 1. Autonomous work returns control to the lead at every wave boundary

`crew/handlers/work.ts` `execute()` dispatches one batch via `spawnAgents(workerTasks, cwd, …)`
(≈`work.ts:197-204`), processes results, and **returns**. Autonomous continuation is not an
internal loop: `index.ts` sends the lead session a `crew_continue` steer message with
`{ triggerTurn: true, deliverAs: "steer" }` (≈`index.ts:1124-1133`), which causes the lead's LLM
to call `work` again. Therefore:

- The lead is **not** blocked for the whole autonomous run; it regains a turn at every wave
  boundary and may do work (e.g. launch reviewers) before re-invoking `work`.
- Continuation has a repeat guard: repeated continuations without wave progress stop autonomous
  mode (`AUTONOMOUS_CONTINUE_REPEAT_LIMIT`, ≈`index.ts:1104-1121`).

This resolves the plan's open question 1: per-task review runs at wave boundaries, pipelined
against the next wave via async read-only reviewer subagents.

## 2. Crew native review is structurally unusable under lead-owned Git

`crew/handlers/review.ts` `reviewImplementation()`:

- Builds the reviewer prompt from `git diff ${baseCommit}..HEAD` and
  `git log ${baseCommit}..HEAD` (≈`review.ts:281-307`). It reviews **committed** history only.
  Our worker override forbids worker commits and the lead commits only after review, so at
  review time `HEAD == base_commit` and the diff is `*No changes*`.
- Truncates diffs at 50,000 characters (≈`review.ts:288-290`), below the failed run's observed
  bundle sizes (61-79 KB for T7 alone).
- Uses one fixed `crew-reviewer` agent prompt (`crew/agents/crew-reviewer.md`) with a single
  `models.reviewer` model, no negative scope contract, no in/out-of-scope tagging, and no
  reviewer rotation.
- Its bounded loop exists (`config.review.maxIterations`, default `review: { enabled: true,
  maxIterations: 3 }` in `crew/utils/config.ts:91`; `NEEDS_WORK` → `store.resetTask`,
  `MAJOR_RETHINK` → block in `work.ts:259-296`) but operates on the wrong evidence.

Conclusion: ADR 0004's `review.enabled: false` is correct. The bounded two-round protocol must
be lead-run against uncommitted write-set bundles.

## 3. Dispatch remains chained barrier waves

Confirms the regression investigation §6: `spawnAgents` is awaited for the whole batch; there is
no slot refill (`TASK-0005`). Persistent lobby workers exist (`crew/lobby.ts`) and `work.ts`
prefers them, but assignment is still batch-per-wave. With `work.maxWaves: 50`,
`stopOnBlock: false`, and `autonomous: true`, chained waves are the closest available
approximation of a continuous pool.

## 4. Worker crash and attempt accounting

In autonomous mode a worker crash blocks the task (`work.ts:246-250`), and
`attempt_count >= config.work.maxAttemptsPerTask` auto-blocks at ready-selection time
(`work.ts:75-80`). Attempt count is incremented at assignment, including lobby crashes, so infra
failures consume budget (`TASK-0006`). The only local mitigation is the package-default budget
of 5 (`crew/utils/config.ts`), which ADR 0004 adopts.

## 5. Current in-repo surfaces (as of branch `pi-team`, pre-implementation)

- `config/pi-team/crew-config.json` still carries the failed run's serial values:
  `maxAttemptsPerTask: 2`, `maxWaves: 1`, `stopOnBlock: true`.
- `skills/pi-team-lead/SKILL.md` §"Wave transaction and dispatch" mandates
  "autonomous continuation is off", per-wave `HEAD == BASE` transactions, per-wave review via
  `review-wave`, and per-wave commits — the exact loop ADR 0004 replaces.
- `tools/pi-team.mjs` `check` already hard-gates `criticalPathRatio > 0.6`
  (`GATE_CRITICAL_PATH_RATIO`) and oversized critical tasks (`GATE_CRITICAL_TASK_SHARE`), and
  computes waves in `computeWaves()` — wave-width metrics are a small extension of
  `computeMetrics()`. It has `review-wave` but no single-task bundle command and no check
  evidence in manifests. Check admissibility for risk labels is not validated
  (`parseChecks`/task validation only require worker scope + `Worker-safe: yes`).
- `agents/pi-team-reviewer.md` has a review boundary but no negative scope contract, no
  in-scope/out-of-scope finding tagging, and no two-round convergence rule.
- `docs/pi-team-setup.md` §"Execution model" already describes the target behavior (it is ahead
  of the implementation); `docs/team-mode-execution.md` describes the OpenCode role-based
  pipeline and needs only the gate-only-barrier alignment for the shared principle.
- `tests/specs/pi-team-config-spec.sh` and `tests/specs/pi-team-tool-spec.sh` exist and are the
  natural homes for the new assertions.

## 6. Review-concurrency safety

`pi-team review-wave` (and the planned `review-task`) write bundle **snapshots** (diff bytes +
manifest hashes) into a fresh output directory at generation time. Reviewers read the snapshot,
not the live tree, so reviewer subagents running concurrently with the next Crew wave cannot see
torn state. The `HEAD == BASE` invariant check at bundle-generation time still holds because
commits happen only at gates.
