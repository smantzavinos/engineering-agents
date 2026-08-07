# Approach: Continuous Crew execution and per-task review

**Created:** 2026-08-06
**Related:** `./brief.md`, `./findings/substrate-review-behavior.md`,
`docs/adr/0004-continuous-crew-execution-and-per-task-review.md`

## Shape of the change

Six surfaces change, preceded by one human-approved decision record (ADR 0005) that records the
Phase A/B split and amends ADR 0004 where five review passes proved it wrong. No upstream
`pi-messenger` change; no canonical process/requirements change.

```text
ADR 0005 (human-approved amendment + Phase A/B split)
   │
   ├─ config: crew-config.json → ADR values, pinned by spec
   ├─ tool:   pi-team.mjs → parallelism metrics/warnings + GATE_RISK_CHECK  (check only)
   ├─ agent:  pi-team-reviewer.md → negative scope, tagged findings, two-round rule
   ├─ skills: pi-team-plan → ownership decomposition, check admissibility, board exclusions
   │          pi-team-lead → bounded review, effective verdict, gate-only commits
   ├─ docs:   team-mode-execution.md, pi-team-setup.md alignment
   └─ dist:   regenerated render output

Deferred to Phase B (upstream-gated): review overlap, bundle evidence, any review-wave change.
```

## Key structural decisions

### D-A: Review at the wave barrier (Phase A); overlap deferred (Phase B)

Crew computes readiness from worker-declared `done`. There is no public action that writes review
state, so the lead cannot make Crew wait on an external verdict. Five review passes established
that every attempt to overlap review with execution required a substrate primitive that does not
exist — review-aware readiness, a full dispatched-cohort barrier (lobby assignments are
fire-and-forget), an event-driven completion wake, an authenticated evidence producer, structured
per-task check evidence, and a durable plan-ID↔Crew-ID map.

Phase A therefore keeps the **existing wave barrier**: review the completed wave before
dispatching the next. This is the status quo mechanically, so it introduces no new failure mode,
and it is where the improvements land — bounded rounds, enforced scope, and a computed effective
verdict. Phase B (overlap, holding only where a dependent is immediately ready) is recorded in
ADR 0005 with its upstream asks.

The measured justification: perfect scheduling was worth **1.8×** (205 → 115 min) against an
observed ~13h run. Review and verification dominated. Phase A attacks the dominant terms.

### D-B: Crew native review stays disabled

It reviews committed history only and truncates at 50 KB (findings §2); this design keeps HEAD
frozen until gate commits, so the native reviewer would see nothing. `review.enabled: false`
stands. Crew still owns the board, dispatch, retry lifecycle, and risk approval; the lead adds
review only.

### D-C: Commits happen only at integration gates

ADR 0004's "commits are per reviewed task or per gate" is narrowed to **per gate**. Per-task
commits would move HEAD while sibling bundles still assume `HEAD == BASE`. Gates are already
barriers, so committing there adds no synchronization cost.

### D-D: Bundle evidence is deferred to Phase B

ADR 0004 asks that `review-wave` bundles embed the worker's check command, exit code, and staged
status. **No authenticated producer exists**: `TaskEvidence` carries only `commits`/`tests`/`prs`
(`crew/types.ts:30-34`), `work` returns no per-worker check output, spawned and lobby workers
receive randomly generated agent names, and `task.progress` checks neither assignment nor status,
so any registered agent can write any task's log.

Revisions 2–5 tried a worker-written record, board-derived provenance, and a lead rerun at a
quiescent boundary; each failed against source reality. Phase A therefore carries **no** bundle
evidence rather than evidence a reviewer cannot rely on, and ADR 0005 records this consequence as
**amended and deferred**, not satisfied. No parallel state store is introduced — ADR 0003 records
that this repo's last duplicated store "drifted from reality".

Negative scope is still enforced, by the two layers that need no new evidence:
1. The reviewer contract forbids requiring files outside the write set, evidence absent from the
   bundle, or live-host evidence in an offline review, and mandates `IN-SCOPE:`/`OUT-OF-SCOPE:`
   tags on every finding.
2. The lead recomputes scope from the write set, reclassifies findings regardless of the
   reviewer's tag, routes out-of-scope findings to backlog without a worker round trip, and
   downgrades a `NEEDS_WORK` with zero surviving in-scope findings to `SHIP`. The effective
   verdict is computed, not trusted.
3. Two-round cap with reviewer rotation. Retries reuse Crew's `task.reset`.

### D-E: Executable-check admissibility is compiler-verified

`pi-team check` adds `GATE_RISK_CHECK` for any task with a risk label: the check command's
first pipeline stage must not be a syntax-only or presence-only tool (`bash -n`, `sh -n`,
`rg`, `grep`); the command must invoke an existing regular file in the repo; and the invoked
script must emit assertion totals per the repo spec-runner idiom. Mechanics prove "a real
counted-assertion spec runs"; semantic sufficiency remains a plan-review responsibility, stated
explicitly in `skills/pi-team-plan`.

### D-F: Parallelism metrics ship advisory

`check` reports mean wave width, max wave width, and width-1 wave share, warning (exit 0) at
provisional thresholds (mean < workers/2; width-1 share > 40%). Hard-gating from one run would
repeat ADR 0004's own epistemic error. Acceptance criteria for promotion to hard gates (three
comparable runs) live in the calibration record under the 2026-07-31 investigation, routed —
not duplicated — from ADR 0005. Existing hard gates (`GATE_CRITICAL_PATH_RATIO`,
`GATE_CRITICAL_TASK_SHARE`) are unchanged.

### D-G: Sequential execution for this plan

This plan changes the team-mode substrate itself; executing it in team mode would dogfood a
known-broken loop, and its first task is a human-gated ADR that ADR 0004 itself says must stay
off any Crew board. The schema-1 plan shape and check metrics are still exercised in T2's
fixtures (dogfood by test rather than by run).

### D-H: No tooling change beyond `check`

Every proposed `review-wave` change — a per-task bundle command, evidence flags, a quiescence
guard — existed to serve Phase B mechanics. With Phase B deferred, `review-wave` and
`init-board` are untouched, and `tools/pi-team.mjs` gains only parallelism metrics/warnings and
`GATE_RISK_CHECK`.

## What is explicitly preserved

Disjoint write-set ownership, lead-owned Git, integration gates as commit precondition, fresh
independent review for destructive work, human approval on risk labels, the rescue path, Crew's
ownership of board/dispatch/retry/approval, and the `review-wave` and `init-board` commands,
which are untouched.

## Falsifier

If a subsequent comparable run with bounded review, enforced scope, and risk-matched checks
**still** shows unbounded review cost or wall-clock many multiples of the critical path, then
the diagnosis in the regression investigation was wrong and the residual bottleneck lies
elsewhere — most likely lead-turn orchestration latency. That must be raised immediately as a
critical discovery, and would make Phase B's upstream primitives a prerequisite for team mode
rather than an optimization.

Conversely, if Phase A brings review cost down without the overlap machinery, that is evidence
the five-round pursuit of continuous execution was chasing the minor term — which the
investigation's own 1.8× scheduling ceiling already suggested.
