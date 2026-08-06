# ADR 0004: Continuous Crew execution and per-task review

Status: Accepted

Date: 2026-08-06

Requirement refs: FR-008, NFR-003

Amends: ADR 0003 (the throughput control plane stands; it is extended to the Pi-team Crew substrate)

## Context

ADR 0003 established that "waves are commit checkpoints, not scheduling barriers; ready work is
pulled forward." That principle was written for the role-based team board and was never carried
into the additive Pi-team Crew substrate described in `docs/pi-team-setup.md`.

The first non-bootstrap Pi-team production run regressed to strict barrier waves. Measured
evidence is in `docs/investigations/2026-08-06-team-mode-throughput-regression/README.md`:
worker batches finished in about three minutes, while the run took roughly 13 hours against a
115-minute critical path. Mean wave width was 1.71 against a pool of 4, review consumed 14
unbounded rounds, the two `destructive` tasks were verified by `bash -n` and absorbed 46% of all
attempts, and the lead mutated Crew configuration 15 times to work around infra crashes consuming
the attempt budget.

Three separable causes were confirmed:

1. **Plan shape.** `pi-team check` reported `criticalPathRatio: 0.56` and no gate rejected it.
2. **Barrier coupling.** Per-wave diff review plus per-wave lead commit requires a frozen HEAD,
   so the barrier existed to serve review and Git, not scheduling.
3. **Substrate.** `crew/handlers/work.ts` awaits the entire batch; there is no slot refill.
   Persistent lobby workers exist, but dispatch is batch-synchronous.

Evidence basis is one production run. The direction is accepted; numeric thresholds are
provisional until calibration.

## Decision

Retain the quality control plane proven by the run — disjoint write-set ownership, lead-owned
Git, integration gates as the commit precondition, fresh independent review for destructive work,
and human approval on risk labels. Change the execution control plane:

- **Continuous execution is the default.** Crew runs with `work.maxWaves: 50`,
  `work.stopOnBlock: false`, and `autonomous: true`. Single-wave manual mode is reserved for
  tasks carrying an approval-gated risk label.
- **Review is a pipeline stage, not a barrier.** A completed task is reviewed against its own
  write set while other tasks continue. Write sets are disjoint by construction, so
  `git diff -- <write set>` needs no frozen HEAD.
- **Barriers exist only at integration gates.** Gate commands test merged state and remain true
  synchronization points. Task boundaries do not.
- **Commits are per reviewed task or per gate**, always staged by explicit write-set paths, and
  always lead-owned.
- **Review is bounded to two rounds per task.** Round 1 admits blocking, in-scope, write-set
  actionable defects only. Round 2 verifies those fixes and may raise regressions only. Anything
  further becomes a backlog item, never another round.
- **Reviewers receive an explicit negative scope.** They may not require files outside the write
  set, evidence absent from the bundle format, or live-host evidence in an offline review. Each
  finding is tagged in-scope or out-of-scope; the lead discards out-of-scope findings without a
  worker round trip.
- **Reviewer identity rotates between rounds** (different model or role prompt) to avoid a
  single reviewer re-deriving one objection class with escalating confidence.
- **Check strength must match risk.** Any task labelled `destructive` or `migration` requires an
  executable check that runs its own fixtures and reports assertion totals. `bash -n` and
  presence-only `rg` assertions are not admissible checks for those tasks.
- **Plans are gated on parallelism.** `pi-team check` reports and flags `criticalPathRatio`,
  maximum wave width, and the share of width-1 waves, and decomposition is expected to be by
  file ownership rather than narrative phase.
- **Human-gated evidence tasks are excluded from the Crew board.** Operator evidence records that
  cannot execute without a live host are tracked as plan steps, not Crew tasks.
- **Infra failures do not consume the attempt budget.** `work.maxAttemptsPerTask` returns to the
  package default of 5, and lobby-worker crashes are treated as retryable infrastructure events.

## Consequences

- `config/pi-team/crew-config.json` changes to `maxWaves: 50`, `stopOnBlock: false`,
  `maxAttemptsPerTask: 5`; `review.enabled` stays false because the lead runs the bounded
  two-round protocol with fresh `pi-team-reviewer` attestations.
- `skills/pi-team-lead` must replace the wave-transaction loop with continuous dispatch,
  per-task review, and gate-scoped barriers, and must stop treating a wave as the review unit.
- `skills/pi-team-plan` must decompose by file ownership, exclude human-gated evidence tasks,
  and refuse `bash -n` as the check for risk-labelled tasks.
- `agents/pi-team-reviewer.md` must carry the negative scope contract, the in-scope/out-of-scope
  finding classification, and the two-round convergence rule.
- `tools/pi-team.mjs` gains parallelism reporting for `check` and should embed the worker's check
  command, exit code, and staged-path status into `review-wave` bundles so reviewers stop
  demanding evidence the format cannot carry.
- `docs/pi-team-setup.md` and `docs/team-mode-execution.md` are updated to describe continuous
  execution and gate-only barriers.
- Slot-refill dispatch inside a batch and infra-versus-genuine attempt accounting remain upstream
  asks against `pi-messenger`; they are tracked as `TASK-0005` and `TASK-0006`. Until available,
  chained autonomous waves plus a 5-attempt budget approximate them.
- Promotion still requires the calibration gate in
  `docs/investigations/2026-07-31-plan-execution-efficiency/README.md`. This ADR sets direction;
  it does not by itself promote Pi-team to canonical process.
- Deployed installs consume these skills through generated `dist/` output; changes take effect
  only after render and redeploy.
