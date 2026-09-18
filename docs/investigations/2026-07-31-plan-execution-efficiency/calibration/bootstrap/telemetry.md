# Bootstrap calibration telemetry

This record covers the bootstrap mechanics calibration only. It is not one of the three
representative code-change calibrations required for promotion.

## Scope and timing

| Field | Value |
|---|---|
| Calibration base | `fbe3823e6f97029a92db1cfc2ffad9623b90e2c4` |
| Approved plan commit | `74ec345342126a64d9f4b2225c6466509e567392` |
| Wave start | `2026-07-31T23:43:53Z` |
| G1 passed | `2026-08-01T01:26:49Z` |
| Frozen serial estimate | 50 minutes |
| Planned critical path | 20 minutes |
| Planned critical-path ratio | 40% |
| Worker tasks | 3 |
| Worker outcome | T1 done in 2 attempts; T2 done in 2 attempts (second was state-only recovery after provider `429`); T3 done in 1 attempt |
| Cost | unavailable — Crew does not provide trustworthy per-task cost |

The observed elapsed time includes a control-plane correction and review/recovery work, so it is
not a comparable representative-code-run performance measurement.

## G1 integration evidence

The final all-task bundle manifest was generated from the calibration base with `HEAD == BASE`.
Its normalized G1 content digest was:

```text
1e2a9bb5c29327d78cde094490891a8c16ea497f21a56d4cfa8cf0ba9f639af1
```

At that digest, the lead ran K4 successfully:

```text
bash docs/investigations/2026-07-31-plan-execution-efficiency/check-doc-refs.sh
./tests/run-tests.sh fast
./scripts/pi-dev.sh --verify
```

Results:

- `check-doc-refs.sh`: PASS — source citations, SUB reference integrity, and stale claims.
- `run-tests.sh fast`: PASS — all fast repository specs.
- `pi-dev.sh --verify`: PASS — Pi proof-set contract and read-only sandbox verification.

The captured G1 log is external runtime evidence at `/tmp/bootstrap-g1.log` with SHA-256
`2bd3d87eb9aaa11834e36016bfcdb68ba5864b672298abae832b402ae8c97fcc`.

## Review evidence

All three complete path-scoped task bundles received fresh `SHIP` verdicts. Their review record
and final bundle digests are in [`review.md`](review.md). The final G1 digest covers precisely
those T1–T3 declared worker paths; the review, telemetry, and learning records are lead-owned
post-wave evidence and are finalized under the separate final tree-ID gate.

## Promotion boundary

Bootstrap validated the board, worker isolation, recovery, path-scoped review, and G1 mechanics.
It leaves the rollout additive and non-canonical. Promotion remains blocked on three representative
code-change runs with correctness gates passing and median wall-clock at most 60% of frozen serial
estimates.
