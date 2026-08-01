# Pi Team execution — current state

This investigation's Pi-team rollout is **additive and non-canonical**. It does not change the
canonical process or OpenCode. The validated dependency is **pi-messenger@0.15.0**; its Phase 0
upstream suite passed **408/408** tests.

## Implemented and green

T1–T4 implementation and deployment are green. The completed rollout includes the pinned
package, configuration and `pi-team` profile, deterministic `pi-team` CLI, three Pi-only skills
plus `pi-team-reviewer`, sandbox and active deployment, resource proof, and profile activation.

Operationally, every ephemeral Pi lead calls `pi_messenger` **join before Team actions** (and
before profile activation). The `pi-team` profile has five Team roles: `worker-cheap`,
`worker-std`, `worker-complex`, `worker-visual`, and `worker-visual-complex`; all use the
`pi-team-worker` skill. Terra routes cheap, standard, and visual work; sol routes complex and
visual-complex work. Crew workers implement packets and never commit. The lead records a clean
BASE, then uses `pi-team review-wave` to create complete path-scoped review bundles containing
both tracked and untracked changes; the lead commits each reviewed wave only after its required
integration work is green.

Crew auto-review is disabled. Fresh `pi-team-reviewer` review results are `SHIP`, `NEEDS_WORK`,
or `MAJOR_RETHINK`. Ordinary work has two Crew attempts; exhausted or major-rethink work receives
one fresh sol rescue and a fresh task review. Migration, destructive, auth, and API-contract work
always requires human approval.

## Promotion boundary

Bootstrap proves the mechanics only. It is excluded from the **three representative code-change**
calibration gate and does not count toward promotion. Promotion requires three representative
code runs whose median wall-clock is at most 60% of the frozen serial estimates.

The G1 integration runs only after all three task bundles receive `SHIP`. Its revision is the
normalized write-set content digest and it reruns only when that digest changes; the lead commits
after G1 is green.

## Verification and acceptance

K1 is a smoke check only. T1 acceptance requires a fresh `pi-team-reviewer` `SHIP` over the
complete T1 bundle and packet; that external task-review attestation is recorded in
`calibration/bootstrap/review.md`.

From the committed bootstrap base, the final changed-path allowlist is the three worker files,
`calibration/bootstrap/review.md`, `calibration/bootstrap/telemetry.md`, and
`docs/issues_learnings.md`. The already committed calibration plan is excluded from that base
diff.

## Source notes

`notes/` remains the source of truth for SUB mechanism details and upstream citations; this
summary intentionally does not restate them.

| Note | Scope |
|---|---|
| [`notes/README.md`](notes/README.md) | Constraint index and upstream verification evidence |
| [`notes/board-materialization.md`](notes/board-materialization.md) | Board materialization findings |
| [`notes/crew-execution-model.md`](notes/crew-execution-model.md) | Crew execution-model findings |
| [`notes/review-loop.md`](notes/review-loop.md) | Review-loop findings |
| [`notes/reservations-and-config.md`](notes/reservations-and-config.md) | Reservation and configuration findings |
