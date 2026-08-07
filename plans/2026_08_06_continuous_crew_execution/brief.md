# Brief: Bounded review, risk-matched checks, and plan-shape gating for Pi-team mode

**Created:** 2026-08-06
**Revised:** 2026-08-06 (descoped to Phase A after five review passes)
**Level:** standard
**Mode:** sequential

## Intent

Implement the parts of ADR 0004 that this substrate can actually support, so that Pi-team runs
have bounded review, checks matched to risk, and plan shapes gated before execution. Continuous
execution with review overlapping the next wave is deferred to Phase B and gated on upstream
`pi-messenger` primitives, per ADR 0005.

## Motivation

The first non-bootstrap Pi-team production run
(`docs/investigations/2026-08-06-team-mode-throughput-regression/README.md`) was correct and
gate-verified but took ~13 hours against a 115-minute critical path. Worker batches finished in
~3 minutes; the loss was serial plan shape, an unbounded hand-rolled review loop, `bash -n`
checks on destructive tasks, barrier-coupled per-wave commits, and 15 mid-run configuration
mutations. ADR 0004 accepted the corrective direction; nothing has been implemented.

## Goals

- Apply the ADR's Crew configuration values with a regression spec pinning them.
- Bound review to two rounds per task with an enforced negative scope and a **computed effective
  verdict**, so a `NEEDS_WORK` containing no in-scope defect cannot cost a worker round trip.
- Gate risk-labelled tasks on executable checks, verified mechanically by `pi-team check`.
- Report parallelism metrics (mean/max wave width, width-1 share) from `pi-team check`, advisory
  until calibrated across three comparable runs.
- Keep review at the existing wave barrier; commit only at integration gates; never mutate Crew
  configuration mid-run.

## Non-goals

- **Phase B**: review overlapping execution, bundle check-evidence, and any `review-wave`
  change. Five review passes established that these need substrate primitives that do not exist
  (review-aware readiness, a full dispatched-cohort barrier, a completion wake, an authenticated
  evidence producer, structured per-task evidence, a durable plan↔Crew map). ADR 0005 records
  them as upstream asks beside `TASK-0005` and `TASK-0006`.
- Enabling Crew's native `review.enabled`. Confirmed unusable: it diffs committed history only
  (`crew/handlers/review.ts`, `git diff ${baseCommit}..HEAD`) and truncates at 50 KB, while this
  design keeps HEAD unchanged until gate commits.
- Any parallel state store or mirror of Crew board state.
- Changing canonical OpenCode process, requirements, or team policy. The calibration and
  promotion boundary in `docs/investigations/2026-07-31-plan-execution-efficiency/README.md`
  still applies.
- Promoting the provisional parallelism thresholds to hard gates (needs n=3 calibration).

## Constraints

- ADR 0005 requires human approval before dependent tasks execute.
- `dist/` is generated only via `node tools/render-skills.mjs --write`; never hand-edited.
- Verification uses only documented commands: `bash tests/specs/<spec>.sh`,
  `./tests/run-tests.sh fast|all`.
- Canonical requirement edits require human approval; none are anticipated (FR-008/NFR-003
  already cover the relevant behavior).

## Source documents

- `docs/investigations/2026-08-06-team-mode-throughput-regression/README.md` — evidence base.
- `docs/adr/0004-continuous-crew-execution-and-per-task-review.md` — accepted direction.
- `docs/adr/0003-restore-team-mode-throughput-scheduling.md` — amended prior decision.
- `docs/pi-team-setup.md` — operational guide, partially ahead of implementation.
- `docs/investigations/2026-07-31-plan-execution-efficiency/notes/crew-execution-model.md` —
  verified upstream substrate findings.
- `findings/substrate-review-behavior.md` — this plan's additional source-verified findings.
