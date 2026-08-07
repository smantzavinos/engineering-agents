# Plan: Bounded review, risk-matched checks, and plan-shape gating for Pi-team mode

**Status:** approved (revision 6 — descoped after Reviews 1–5)
**Owner:** pi planning agent (sequential execution)
**Created:** 2026-08-06
**Revised:** 2026-08-06 (R1–R5; descoped to Phase A after Review 5's non-convergence finding)
**Related:** `./brief.md`, `./approach.md`, `./execution-model.md`,
`./findings/substrate-review-behavior.md`, `./plan_review.md`,
`docs/adr/0004-continuous-crew-execution-and-per-task-review.md`,
`docs/investigations/2026-08-06-team-mode-throughput-regression/README.md`

---

## Execution Contract
This plan is meant to be **executed** with strict TDD (Red → Green → Break-it → Verify).

No implementation change without a failing test (or an explicitly documented exception). The
only documented exception is the `dist/` regeneration step in T7, whose gate is
`skill-render-spec.sh`; the generator is not modified. T1 (ADR authoring) is gated by explicit
human acceptance.

---

## Scope decision: Phase A only

Five adversarial review passes put **every blocker in one place** — the runtime dispatch/review
interleaving. Everything else produced only specification tightening:

| Surface | Blockers across R1–R5 |
|---|---|
| Runtime dispatch/review interleaving (continuous overlap, evidence capture, quiescence) | 5 of 5 rounds |
| Config, reviewer contract, plan skill, docs, closure, `check` metrics, `GATE_RISK_CHECK` | none |

The five blockers were all the same defect wearing different clothes: the loop needed a
substrate primitive that does not exist (review-aware readiness, an authenticated evidence
producer, a durable plan↔Crew map, a full-cohort barrier, a completion wake). This plan
therefore implements **Phase A** — everything that needs no missing primitive — and records
Phase B as an upstream-gated follow-up.

This is consistent with the measured evidence: the regression investigation ranks plan shape,
review protocol, and check strength as the dominant costs, and caps perfect scheduling at
**1.8×** against an observed ~13h run. Phase A attacks the dominant terms.

**Phase B (not in this plan):** continuous dispatch with review overlapping the next wave.
Requires awaiting the full dispatched cohort including lobby assignments, review-state-aware
readiness, and an event-driven completion wake. Recorded in ADR 0005 as upstream asks beside
`TASK-0005`/`TASK-0006`.

---

## Change Summary
- **What changes:** Crew config adopts the ADR's continuous values; `pi-team check` reports
  parallelism metrics as warnings and rejects inadmissible risk-task checks; the reviewer agent
  gains a negative scope contract, tagged findings, and a two-round convergence rule; the plan
  skill requires file-ownership decomposition and admissible risk checks; the lead skill keeps
  its existing per-wave barrier but gains bounded two-round review, a computed effective
  verdict, reviewer rotation, gate-only commits, and a prohibition on mid-run config mutation;
  docs and `dist/` follow. ADR 0005 records the amendments and the Phase B boundary.
- **What stays the same:** `tools/pi-team.mjs`'s `review-wave` command entirely; the wave
  barrier; disjoint write-set ownership; lead-owned Git; integration gates; fresh independent
  review for destructive work; human approval on risk labels; the rescue path; Crew ownership of
  board, dispatch, retry, and approval; Crew `review.enabled: false`; upstream `pi-messenger`;
  canonical OpenCode process/requirements; the calibration/promotion boundary.
- **Motivation:** The next comparable run should show bounded review rounds per task, no
  out-of-scope worker round trips, no `bash -n` on destructive work, plan shapes rejected before
  execution when they cannot parallelize, and no mid-run configuration mutation.

## Goals
- [ ] ADR 0005 accepted, recording the Phase A/B split and amending ADR 0004 where revision
      proved it wrong.
- [ ] `config/pi-team/crew-config.json` carries `maxWaves: 50`, `stopOnBlock: false`,
      `maxAttemptsPerTask: 5`, `review.enabled: false`, `workers: 4`, pinned by spec.
- [ ] `pi-team check` reports `meanWaveWidth`/`maxWaveWidth`/`widthOneShare` as versioned
      warnings (exit 0) and rejects inadmissible risk-task checks via `GATE_RISK_CHECK`
      (exit 1).
- [ ] `agents/pi-team-reviewer.md` carries the negative scope contract, mandatory
      `IN-SCOPE:`/`OUT-OF-SCOPE:` tags, and the two-round convergence rule.
- [ ] `skills/pi-team-lead` bounds review to two rounds with a computed effective verdict,
      rotates reviewers, commits only at gates, and forbids mid-run config mutation.
- [ ] `skills/pi-team-plan` requires file-ownership decomposition, excludes human-gated evidence
      tasks, and mirrors the check-admissibility rules.
- [ ] Docs describe the implemented model; `dist/` regenerated.

## Non-goals
- **Phase B**: continuous dispatch with review overlap, boundary evidence capture, quiescence
  guards, and any new `review-wave` flag or bundle command.
- Upstream `pi-messenger` changes (`TASK-0005`, `TASK-0006`, plus the Phase B asks in ADR 0005).
- Enabling Crew native review — structurally unusable here (findings §2).
- Any parallel state store or mirror of Crew board state.
- Hard-gating the new parallelism thresholds (needs n=3 calibration).
- Canonical requirement edits (none anticipated; escalate if review disagrees).

## Related Backlog Items
- `TASK-0005`, `TASK-0006` — existing upstream asks.
- New in T8: a calibration backlog item for the parallelism thresholds after the next comparable
  run, backlinked to this plan and ADR 0005.

## Related Requirements
- Requirement refs: FR-008, NFR-003 (behavior under change); FR-002, OPR-001 (existing citations
  in touched specs, retained). Actors/use cases/workflows: N/A.

## Requirement Updates

| Requirement change | Applied in task | Notes |
|--------------------|-----------------|-------|
| none | — | Escalate if review finds FR-008/NFR-003 no longer covers the barrier model |

## Impacted Surface Area
- **Entry points affected:** `pi-team check` output only. `review-wave` is untouched.
- **Modules/components touched:** `docs/adr/0005-*.md`, `docs/adr/README.md`,
  `config/pi-team/crew-config.json`, `tools/pi-team.mjs`, `agents/pi-team-reviewer.md`,
  `skills/pi-team-lead/SKILL.md`, `skills/pi-team-plan/SKILL.md` (+
  `references/plan-contract.md`), `docs/team-mode-execution.md`, `docs/pi-team-setup.md`,
  `dist/`, `tests/specs/pi-team-config-spec.sh`, `tests/specs/pi-team-tool-spec.sh`,
  `tests/specs/skill-content-spec.sh`, `tests/specs/repo-readiness-docs-spec.sh`, fixtures.
- **External contracts affected:** `check --json` gains an additive `warnings` collection and
  three `metrics` fields. Nothing else changes; no existing invocation or consumer breaks.

## Context
`./execution-model.md` describes the implemented planning and execution loop with a worked
example. `./findings/substrate-review-behavior.md` records source-verified substrate behavior;
`./plan_review.md` records five review passes, including the evidence for the Phase A/B split.

The dominant costs in the failed run were: a serial plan shape that no gate rejected
(`criticalPathRatio 0.56`, mean wave width 1.71); an unbounded review loop (14 rounds, three
`NEEDS_WORK` verdicts containing no code defect); `bash -n` as the check on the two `destructive`
tasks (46% of all attempts); and 15 mid-run config mutations. Phase A addresses all four.

## Constraints
- ADR 0005 (T1) requires human approval before T3 and T6 start.
- `dist/` only via `node tools/render-skills.mjs --write` (T7); never hand-edited.
- Documented verification commands only; record baseline failures before touched gates; only new
  failures block.
- Follow `.llm/process_docs_rules.txt` and the per-directory `AGENTS.md` files.
- Route calibration criteria to the 2026-07-31 investigation directory and follow-ups to
  `docs/backlog.md`; do not create second canonical sources.

## Assumptions
- `tests/specs/pi-team-tool-spec.sh` can host fixture-driven assertions for diagnostics and
  warnings (it already exercises `check`/`init-board`/`review-wave`).
- The repo assertion-total idiom is **verified to exist**: specs print
  `Results: N passed, M failed` (confirmed in `pi-team-config-spec.sh`, `skill-content-spec.sh`).
- `skill-content-spec.sh:298` already covers `agents/pi-team-reviewer.md`.
- Reviewer rotation is "round 2 uses a different model than round 1"; exact models follow the
  active repo profile.

## CLI Contract Mini-Spec (binding on T3)

A versioned CLI/JSON boundary — contract, not implementer discretion.

### `check --json` additive output
- New top-level `warnings: []`, **separate from** `diagnostics`, never affecting exit code,
  present on **every** JSON output including validation and I/O failures (empty when none).
- Warning objects match the diagnostic shape `{ code, message, location }`.
- Codes: `WARN_MEAN_WAVE_WIDTH` (mean < 2.0), `WARN_WIDTH_ONE_SHARE` (share > 40%).
- Sorted by the existing `diagnosticCompare` ordering for determinism.
- New `metrics` fields `meanWaveWidth`, `maxWaveWidth`, `widthOneShare`, computed from the
  existing `computeWaves` result.
- Human output prints warnings to stderr as `WARN_*: message (section:row:field)`.
- Exit policy unchanged: `0` valid, `1` gate/validation failure, `2` I/O or argument failure.
  Warnings alone never produce a non-zero exit.

### `GATE_RISK_CHECK` admissible command grammar
Applies only to tasks with a non-empty `Risk labels` cell. The `Command` cell is **tokenized,
not shell-parsed**:
- Split on single ASCII spaces. Any occurrence of `"`, `'`, `\`, `|`, `<`, `>`, `&`, `;`, `$`,
  backtick, `(`, `)`, or a `VAR=` prefix ⇒ reject, reason `unsupported command form`.
- Path resolution: if token 0 ∈ {`bash`, `sh`, `node`} then token 1 is the path; otherwise
  token 0 is the path. Remaining tokens are arguments, must contain no metacharacter from that
  list, and are otherwise unconstrained.
- **Rejected**, `syntax-only or presence-only check`: token 0 ∈ {`rg`, `grep`, `test`}, or
  tokens 0-1 form `bash -n` / `sh -n`.
- **Rejected**, `check script not found`: the path does not resolve to an existing regular file.
  A leading `./` is stripped first; the path is then repo-relative and walked with the same lstat
  symlink policy as `validateWritePath`, rejecting a symlinked final component.
  (`validateWritePath` itself rejects `.` segments, so this is a separate resolver sharing its
  symlink policy, not a reuse.)
- **Rejected**, `no assertion totals`: the invoked script lacks the repo assertion-total idiom
  (a `Results: ... passed` emission).
- All produce `GATE_RISK_CHECK` at exit 1 with the reason in the message.

**`review-wave` is not modified by this plan.** No new flags, no manifest changes, no evidence
transport. Those are Phase B.

## Open Questions

| Question | Resolution |
|----------|------------|
| Who runs review, and when? | The lead, at the existing wave barrier, before dispatching the next wave. Review overlap is Phase B |
| Should Crew native review replace the lead loop? | No — it diffs committed history only and truncates at 50 KB (findings §2). Crew still owns board, dispatch, retry, approval |
| How is negative scope enforced? | Reviewer contract tags every finding; the lead recomputes scope from the write set and derives an effective verdict; out-of-scope findings go to backlog, never to a worker retry |
| What makes a risk-task check executable? | `GATE_RISK_CHECK` per the grammar above; semantic sufficiency stays with plan review |
| Calibrated thresholds? | Advisory warnings only; promotion to hard gates needs three comparable runs recorded in the 2026-07-31 calibration directory |
| Is bundle evidence carried? | Not in Phase A. ADR 0005 **amends** ADR 0004's worker-evidence consequence: no authenticated producer exists, so the consequence is deferred to Phase B rather than faked |

## Risks & Mitigations

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Barrier review leaves throughput on the table | med | high (accepted) | Measured ceiling for scheduling is 1.8×; the dominant costs are addressed. Phase B recorded with concrete upstream asks |
| Reviewers still demand evidence the bundle lacks | med | med | Reviewer contract explicitly forbids requiring evidence absent from the bundle and mandates tagging; the lead discards out-of-scope findings without a worker round trip |
| `GATE_RISK_CHECK` grammar rejects legitimate checks or admits gamed ones | med | med | Explicit accept/reject grammar with per-branch fixtures (T3); semantic sufficiency assigned to plan review (T5) |
| Lead skill prose is disobeyed at runtime | med | med | Config spec-pinned (T2); `check` refuses inadmissible plans (T3); text assertions on the lead contract (T6); telemetry exposes violations |
| Serial plans still pass `check` | med | med (accepted) | Thresholds advisory until calibrated; T5 requires reviewing metrics against pool size before approval |
| Phase B never lands, leaving the model permanently barriered | low | med | Acceptable: Phase A is independently valuable and the barrier is the status quo, not a regression |

## Decisions

| Decision | Options Considered | Chosen | Rationale | Consequences | Revisit If |
|----------|-------------------|--------|-----------|--------------|------------|
| Scope | full ADR 0004; Phase A only | **Phase A only** | 5 of 5 review rounds put every blocker in the runtime interleaving; nothing else blocked once | Review overlap deferred; ADR 0004 partially amended | Upstream ships the Phase B primitives |
| Review timing | overlap next wave; existing wave barrier | **existing wave barrier** | Overlap requires primitives that do not exist; the barrier is already the status quo | No new dispatch mechanism, no quiescence proof needed | Phase B lands |
| Bundle evidence | worker record; lead rerun; none in Phase A | **none in Phase A** | No authenticated producer exists; a partial state is evidence reviewers cannot rely on | ADR 0004's worker-evidence consequence is amended, not satisfied | Upstream authenticates producers |
| `review-wave` | extend; leave alone | **leave alone** | Every proposed extension depended on Phase B mechanics | Tool change reduces to `check` only | Phase B lands |
| Crew native review | enable; keep disabled | **keep disabled** | Diffs committed history only; 50 KB truncation | Lead owns the bounded protocol | Upstream reviews uncommitted diffs |
| Commit granularity | per reviewed task; per gate | **per gate only** | Per-task commits break sibling `HEAD == BASE` | ADR 0004 wording narrowed | — |
| Advisory output shape | reuse diagnostics; separate warnings | **separate `warnings`** | Keeps exit-code semantics unambiguous | Additive JSON field on all outputs | Thresholds promote to hard gates |
| Plan execution mode | team; sequential | **sequential** | Changes the team substrate itself; T1 is human-gated | — | — |

## Work Plan

### Task Graph
| ID | Task | Depends on | Touched files | Est (min) | Deliverable | Verification | Status |
|---:|---|---|---|---:|---|---|---|
| T1 | Author ADR 0005; human approval | — | `docs/adr/0005-*.md`, `docs/adr/README.md` | 25 | Accepted ADR with the Phase A/B split | Human approval; `bash tests/specs/repo-readiness-docs-spec.sh` | ⬜ |
| T2 | Apply and pin Crew config values | — | `config/pi-team/crew-config.json`, `tests/specs/pi-team-config-spec.sh` | 10 | ADR values live and spec-pinned | `bash tests/specs/pi-team-config-spec.sh` | ⬜ |
| T3 | `pi-team check`: metrics/warnings + `GATE_RISK_CHECK` | T1 | `tools/pi-team.mjs`, `tests/specs/pi-team-tool-spec.sh`, fixtures | 30 | CLI mini-spec implemented | `bash tests/specs/pi-team-tool-spec.sh` | ⬜ |
| T4 | Reviewer agent contract | — | `agents/pi-team-reviewer.md`, `tests/specs/skill-content-spec.sh` | 15 | Negative scope, tagged findings, two-round rule | `bash tests/specs/skill-content-spec.sh` | ⬜ |
| T5 | Plan skill: ownership decomposition + check admissibility | — | `skills/pi-team-plan/`, `tests/specs/skill-content-spec.sh` | 20 | Updated planning contract | `bash tests/specs/skill-content-spec.sh` | ⬜ |
| T6 | Lead skill: bounded review, effective verdict, gate-only commits | T1, T4 | `skills/pi-team-lead/`, `tests/specs/skill-content-spec.sh` | 25 | Review discipline on the existing barrier flow | `bash tests/specs/skill-content-spec.sh` | ⬜ |
| T7 | Docs alignment + `dist/` regeneration | T5, T6 | `docs/team-mode-execution.md`, `docs/pi-team-setup.md`, `tests/specs/repo-readiness-docs-spec.sh`, `dist/` | 20 | Docs match `./execution-model.md`; dist regenerated | `bash tests/specs/repo-readiness-docs-spec.sh`; `bash tests/specs/skill-render-spec.sh` | ⬜ |
| T8 | Final gate + closure | T2, T3, T7 | `docs/backlog.md`, `tests/specs/repo-readiness-docs-spec.sh`, plan artifacts | 10 | Green final gate; calibration backlog item | `./tests/run-tests.sh all` vs recorded baseline | ⬜ |

**Shared test files, stated honestly.** `tests/specs/skill-content-spec.sh` is edited by T4, T5,
and T6, and `tests/specs/repo-readiness-docs-spec.sh` by T7 and T8. Sequential execution
serializes these and each task's assertions are scoped to its own subject strings. A team-mode
write-set gate would reject the overlap — one reason this plan is sequential.

**Dogfood parallelism metrics.** Depth-0 = {T1,T2,T4,T5}; depth-1 = {T3,T6}; then T7, T8.

| Metric | Value |
|---|---|
| wave widths | 4, 2, 1, 1 |
| mean wave width | 8 / 4 = **2.0** |
| max wave width | **4** |
| width-1 share | 2 / 4 = **50%** |
| serial estimate | 25+10+30+15+20+25+20+10 = **155 min** |
| critical path | T1(25) → T6(25) → T7(20) → T8(10) = **80 min** |
| critical-path ratio | 80 / 155 = **0.52** |

Descoping improved the shape: mean width rose 1.6 → 2.0 and the ratio fell 0.75 → 0.52, which
would pass the existing 0.6 hard gate. It still trips the proposed `WARN_WIDTH_ONE_SHARE`
advisory at 50%, which is honest for an 8-task plan with a documentation tail.

**Boundary statement:** this is a standard sequential plan, not a schema-1 Crew board plan, so
`pi-team check` cannot run against it. These figures are advisory arithmetic; the board gate is
exercised by T3's fixtures.

### Task Details

#### T1: Author ADR 0005 and obtain human approval
**Depends on:** — · **Est:** 25 min
**Touched files:** `docs/adr/0005-*.md`, `docs/adr/README.md`
**Deliverable:** Accepted ADR recording:
1. **Phase A/B split.** ADR 0004's "review is a pipeline stage, not a barrier" is **not
   implementable** on this substrate today. Enumerate the six missing primitives found across
   five review passes: review-state-aware readiness; an authenticated evidence producer;
   structured per-task check evidence; a durable plan-ID↔Crew-ID map; a full dispatched-cohort
   barrier (lobby assignments are fire-and-forget); an event-driven completion wake.
2. **Amendments to ADR 0004**, stated as amendments rather than satisfactions:
   - the `review-wave` worker-evidence consequence is **deferred to Phase B**, because no
     authenticated producer exists (`TaskEvidence` is `commits`/`tests`/`prs`; worker agent
     names are randomly generated; `task.progress` is unauthenticated);
   - commits are **per gate only**, narrowing "per reviewed task or per gate".
3. **Retained and implemented now:** bounded two-round review, negative scope contract,
   reviewer rotation, risk-matched checks, plan-shape gating, human-gated evidence tasks off the
   board, and the attempt-budget default.
4. **Phase B upstream asks** recorded beside `TASK-0005`/`TASK-0006`.
5. Advisory thresholds with n=3 promotion criteria routed to the 2026-07-31 calibration
   directory.
Status `Accepted` only after human approval.
**Requirement refs:** FR-008, NFR-003

**TDD checklist (gated by human acceptance):**
- [ ] Draft ADR 0005 per `docs/adr/README.md`; `Amends: ADR 0004`
- [ ] Add the index entry to `docs/adr/README.md`
- [ ] Run `bash tests/specs/repo-readiness-docs-spec.sh` — confirm no broken routes/anchors
- [ ] **Stop: present to the human; do not start T3 or T6 until Status is Accepted**
- [ ] Task gate: `./tests/run-tests.sh fast`

---

#### T2: Apply and pin the ADR Crew configuration values
**Depends on:** — · **Est:** 10 min
**Touched files:** `config/pi-team/crew-config.json`, `tests/specs/pi-team-config-spec.sh`
**Deliverable:** `work.maxWaves: 50`, `work.stopOnBlock: false`, `work.maxAttemptsPerTask: 5`;
unchanged and asserted: `concurrency.workers: 4`, `review.enabled: false`,
`review.maxIterations: 2`, `dependencies: "strict"`, `coordination: "minimal"`,
`artifacts.enabled: true`. Autonomous chaining still applies — the lead reviews at each wave
boundary before continuing.
**Requirement refs:** NFR-003 (added alongside existing FR-002, OPR-001)

**TDD checklist:**
- [ ] Add failing assertions for the three new values plus regression assertions for the
      unchanged ones; add `Requirement: NFR-003` to the header
- [ ] Run `bash tests/specs/pi-team-config-spec.sh` — confirm failure
- [ ] Edit `config/pi-team/crew-config.json`
- [ ] Re-run — confirm pass
- [ ] **Break-it:** set `maxWaves` back to `1` → spec fails; restore
- [ ] Task gate: `./tests/run-tests.sh fast`

---

#### T3: `pi-team check` — metrics/warnings and `GATE_RISK_CHECK`
**Depends on:** T1 · **Est:** 30 min
**Touched files:** `tools/pi-team.mjs`, `tests/specs/pi-team-tool-spec.sh`, fixtures
**Deliverable:** Implement the CLI Contract Mini-Spec exactly: metrics plus the separate
`warnings` collection on every JSON output, and `GATE_RISK_CHECK` with the tokenizer and four
rejection reasons. **`review-wave` and `init-board` are not touched.**
**Requirement refs:** FR-008, NFR-003 (added alongside FR-002, OPR-001)

**TDD checklist:**
- [ ] Add failing spec cases: (a) fixture plan → exact `meanWaveWidth`/`maxWaveWidth`/
      `widthOneShare`; (b) warnings emitted in `warnings`, absent from `diagnostics`, exit 0,
      deterministic order, `warnings: []` present on a validation-failure output and on an I/O
      failure output; (c) each `GATE_RISK_CHECK` rejection — `bash -n`, metacharacter/quoted
      form, missing file, symlinked final component, script without assertion totals — exit 1
      with the reason in the message; (d) admissible forms accepted (`bash <spec>`, `./<spec>`,
      `node <script>`, trailing args); (e) non-risk task with `bash -n` unaffected;
      (f) regression: the full existing `review-wave` and `init-board` case set passes
      unchanged; add `Requirement: FR-008, NFR-003` to the header
- [ ] Run `bash tests/specs/pi-team-tool-spec.sh` — confirm the new cases fail
- [ ] Implement: metrics in `computeMetrics`; warnings threaded through `result()`/`printCheck`;
      tokenizer and admissibility resolver in the check-validation pass
- [ ] Re-run — confirm pass
- [ ] **Break-it:** invert the denylist so `bash -n` is admitted → case (c) fails; restore. Then
      emit warnings into `diagnostics` → case (b) fails; restore
- [ ] Task gate: `./tests/run-tests.sh fast`

---

#### T4: Reviewer agent contract
**Depends on:** — · **Est:** 15 min
**Touched files:** `agents/pi-team-reviewer.md`, `tests/specs/skill-content-spec.sh`
**Deliverable:** Adds an explicit **negative scope** section — may not require files outside the
write set, evidence absent from the bundle, or live-host evidence in an offline review;
mandatory finding tags, every finding line beginning `IN-SCOPE:<repo-path>` or
`OUT-OF-SCOPE:<reason>`; and the two-round convergence rule (round 1: blocking, in-scope,
write-set-actionable defects only; round 2: verify fixes and raise regressions only; anything
further is a backlog recommendation, never a third round). Verdict enum and read-only rules
unchanged.
**Requirement refs:** FR-008

**TDD checklist:**
- [ ] Extend the existing reviewer assertion at `tests/specs/skill-content-spec.sh:298` with
      failing assertions for the negative-scope heading, both tag literals, and the two-round
      rule
- [ ] Run `bash tests/specs/skill-content-spec.sh` — confirm failure
- [ ] Edit `agents/pi-team-reviewer.md` (respect `agents/AGENTS.md`)
- [ ] Re-run — confirm pass
- [ ] **Break-it:** remove the `OUT-OF-SCOPE:` tag requirement → fails; restore
- [ ] Task gate: `./tests/run-tests.sh fast`

---

#### T5: Plan skill — ownership decomposition, board exclusions, check admissibility
**Depends on:** — · **Est:** 20 min
**Touched files:** `skills/pi-team-plan/SKILL.md`,
`skills/pi-team-plan/references/plan-contract.md`, `tests/specs/skill-content-spec.sh`
**Deliverable:** Requires decomposition by **file ownership**, not narrative phase (each task
named by the files it owns; wide waves preferred; the reported `check` metrics and warnings
reviewed against pool size before approval); exclusion of human-gated operator-evidence tasks
from the board; risk-check admissibility mirroring the `GATE_RISK_CHECK` grammar, with the
explicit statement that mechanical admissibility never proves semantic sufficiency — that
remains a fresh-semantic-review responsibility.
**Requirement refs:** FR-008

**TDD checklist:**
- [ ] Add failing `skill-content-spec.sh` assertions scoped to `pi-team-plan` strings: file
      ownership decomposition, board exclusion, admissibility rules, "mechanical ≠ semantic"
- [ ] Run the spec — confirm failure
- [ ] Edit the skill (respect `skills/AGENTS.md`; no `compatibility:` line; do not touch `dist/`)
- [ ] Re-run — confirm pass
- [ ] **Break-it:** delete the board-exclusion paragraph → fails; restore
- [ ] Task gate: `./tests/run-tests.sh fast`

---

#### T6: Lead skill — bounded review, effective verdict, gate-only commits
**Depends on:** T1, T4 · **Est:** 25 min
**Touched files:** `skills/pi-team-lead/SKILL.md`, `tests/specs/skill-content-spec.sh`
**Deliverable:** The existing wave-transaction and dispatch structure is **retained**. Revise
§"Review, retries, and rescue" and §"Integration and commit" to add:
1. **Bounded rounds.** Round 1 admits blocking, in-scope, write-set-actionable defects only;
   round 2 verifies those fixes and may raise regressions only, using a **different reviewer
   model**; there is no round 3 — further findings become backlog items. Retries use Crew's
   `task.reset`.
2. **Computed effective verdict.** Every finding must carry an `IN-SCOPE:`/`OUT-OF-SCOPE:` tag.
   The lead recomputes scope from the task's write set, reclassifies any finding whose path
   falls outside it regardless of the reviewer's tag, routes out-of-scope findings to
   `docs/backlog.md` without a worker round trip, and downgrades a `NEEDS_WORK` with zero
   surviving in-scope findings to `SHIP` plus backlog entries.
3. **Reviewer rotation** between rounds.
4. **Gate-only commits.** Commit only after the affected integration group's gate is green,
   staged by explicit write-set paths. Per-task commits are prohibited.
5. **No mid-run configuration mutation.** If the config is wrong, stop the run, fix it, restart.
6. **Phase B pointer.** A short note that review overlap and boundary evidence capture are
   deferred to Phase B per ADR 0005, so a future reader does not reintroduce them ad hoc.
Preflight, materialization, dispatch, and rescue sections are otherwise unchanged.
**Requirement refs:** FR-008, NFR-003

**TDD checklist:**
- [ ] Add failing `skill-content-spec.sh` assertions scoped to the lead skill: contains the
      two-round rule, the `IN-SCOPE:`/`OUT-OF-SCOPE:` filter, the effective-verdict downgrade,
      reviewer rotation, the gate-only commit rule, and the mid-run mutation prohibition
- [ ] Run the spec — confirm failure
- [ ] Revise the lead skill sections
- [ ] Re-run — confirm pass
- [ ] **Break-it:** remove the effective-verdict downgrade sentence → fails; restore
- [ ] Confirm no statement contradicts `./execution-model.md`
- [ ] Task gate: `./tests/run-tests.sh fast`

---

#### T7: Docs alignment and `dist/` regeneration
**Depends on:** T5, T6 · **Est:** 20 min
**Touched files:** `docs/team-mode-execution.md`, `docs/pi-team-setup.md`,
`tests/specs/repo-readiness-docs-spec.sh`, `dist/`
**Deliverable:** `docs/pi-team-setup.md` §"Execution model" is corrected — it currently
describes the un-implemented continuous model — to the implemented barrier model with bounded
review, and states the Phase B boundary. `docs/team-mode-execution.md` states the shared
principle in its wave/coordination sections, routing to ADR 0005 rather than forking policy.
`dist/` regenerated via `node tools/render-skills.mjs --write`; no hand edits.
**Requirement refs:** FR-008

**TDD checklist (`dist/` regeneration is the one documented exception):**
- [ ] Add failing `repo-readiness-docs-spec.sh` assertions for the required statements in both
      docs (bounded review; gate-only commits; Phase B boundary)
- [ ] Run the spec — confirm failure
- [ ] Edit both docs (follow `.llm/process_docs_rules.txt`)
- [ ] Re-run — confirm pass
- [ ] **Break-it:** delete the Phase B boundary sentence from `docs/pi-team-setup.md` → fails;
      restore
- [ ] Run `node tools/render-skills.mjs --write`; run `bash tests/specs/skill-render-spec.sh`
- [ ] **Break-it (dist):** hand-edit one rendered `dist/` file → render spec fails; regenerate
- [ ] Task gate: `./tests/run-tests.sh fast`

---

#### T8: Final gate and closure
**Depends on:** T2, T3, T7 · **Est:** 10 min
**Touched files:** `docs/backlog.md`, `tests/specs/repo-readiness-docs-spec.sh`, plan artifacts
**Deliverable:** Green final gate against the recorded baseline; a calibration backlog item with
a stable `TASK-XXXX` ID and a backlink to this plan and ADR 0005; completion criteria checked.
**Requirement refs:** OPR-001

**TDD checklist:**
- [ ] Add a failing `repo-readiness-docs-spec.sh` assertion that the backlog contains a
      calibration item with a stable `TASK-XXXX` ID and a backlink to this plan
- [ ] Run the spec — confirm failure
- [ ] Add the calibration backlog item to `docs/backlog.md` per its contract
- [ ] Re-run — confirm pass
- [ ] **Break-it:** remove the backlink from the new backlog item → assertion fails; restore
- [ ] Compare `./tests/run-tests.sh all` against the baseline recorded before T1 — only new
      failures block
- [ ] Verify completion criteria; update `state.json`; confirm no canonical requirement was
      edited without approval

---

## Behavior / Coverage Matrix

| Behavior | Source of truth | Primary test layer | Negative/edge cases | Needs E2E? | Regression risk |
|----------|----------------|-------------------|---------------------|------------|-----------------|
| Crew config carries continuous values | `crew-config.json` | `pi-team-config-spec.sh` | drifted/mutated values fail | no | high |
| `check` reports wave-width metrics as warnings | `pi-team.mjs` | tool-spec fixtures | serial fixture warns at exit 0; warnings absent from `diagnostics`; `warnings: []` on failure and I/O outputs; deterministic order | no | med |
| `GATE_RISK_CHECK` rejects inadmissible risk checks | `pi-team.mjs` | tool-spec fixtures | `bash -n`; metacharacter form; missing file; symlinked component; no assertion totals; admissible forms accepted; non-risk task unaffected | no | high |
| `review-wave`/`init-board` unchanged | `pi-team.mjs` | full existing case set | — | no | high |
| Reviewer contract text | `agents/pi-team-reviewer.md` | `skill-content-spec.sh` | tag/rule removal fails | no | med |
| Plan/lead skill contract text | `skills/pi-team-*` | `skill-content-spec.sh` | removed effective-verdict rule fails | no | med |
| Docs state the implemented model | docs | `repo-readiness-docs-spec.sh` | sentence deletion fails | no | med |
| Calibration backlog item exists with backlink | `docs/backlog.md` | `repo-readiness-docs-spec.sh` | removed backlink fails | no | low |
| `dist/` matches canonical skills | `dist/` | `skill-render-spec.sh` | hand edit fails | no | med |
| Bounded review actually converges in two rounds | lead skill procedure | **runtime, not unit-testable here** | — | yes (next run) | med |

**Known coverage limit:** the review protocol is a *procedure in a skill*, not code in this repo.
Text assertions prove the instructions are present and consistent; they cannot prove runtime
obedience. Runtime proof comes from the next run's telemetry, which the T8 calibration backlog
item captures. Unlike the Phase B mechanics, nothing here can silently corrupt state if
disobeyed — the failure mode is a longer review, not a torn snapshot or a premature dispatch.

## Baseline Gate Audit

| Command | Scope | Baseline status | Related failures? | Notes |
|---------|-------|-----------------|-------------------|-------|
| `./tests/run-tests.sh fast` | package-wide | ✅ pass (2026-08-06, branch `pi-team`) | no | recorded during planning |
| `bash tests/specs/repo-readiness-docs-spec.sh` | touched-files | ✅ 303 passed, 0 failed | no | recorded during planning |
| `./tests/run-tests.sh all` | repo-wide | ⬜ record immediately before T1 | — | requires nix/pi/HM per `docs/testing-strategy.md` |

### Gate policy for this plan
**Policy:** block-on-global-gate
**Rationale:** All touched surfaces are covered by the fast suite; the final `all` gate must be
clean relative to its recorded baseline. Only new failures block.

## Verification Plan

| Command | Scope | When | What it proves |
|---------|-------|------|----------------|
| `bash tests/specs/pi-team-config-spec.sh` | touched-files | T2 | config values pinned |
| `bash tests/specs/pi-team-tool-spec.sh` | touched-files | T3 | metrics, warnings, gate grammar, no regression in untouched commands |
| `bash tests/specs/skill-content-spec.sh` | touched-files | T4/T5/T6 | contract text present and consistent |
| `bash tests/specs/repo-readiness-docs-spec.sh` | touched-files | T1/T7/T8 | routes, canonical docs, required statements, backlog item |
| `bash tests/specs/skill-render-spec.sh` | touched-files | T7 | dist matches canonical skills |
| `./tests/run-tests.sh fast` | package-wide | every task completion | no cross-contract drift |
| `./tests/run-tests.sh all` | repo-wide | before completion | repo-wide integrity vs baseline |

### Completion Criteria
- [ ] All tasks done; ADR 0005 Status is Accepted (human)
- [ ] All task gates green; final gate green vs recorded baseline
- [ ] Every coverage-matrix row except the runtime row has passing tests
- [ ] Calibration backlog item exists with backlink
- [ ] No hand edits under `dist/`; no canonical requirement edited without approval

## Compatibility & Migration
- **Backwards compatibility:** `review-wave`, `init-board`, the schema-1 plan grammar, and
  `check --json`'s existing fields are unchanged. `check --json` gains additive fields only.
- **Forwards compatibility:** advisory warnings promote to hard gates without a schema change;
  Phase B can add manifest fields additively later.
- **Migration steps:** deployed installs pick up skills only after render (T7) and redeploy
  (`home-manager switch`); do not start a production Pi-team run mid-plan.
- **Rollback strategy:** every surface is a tracked file; revert the commits. Config revert is
  guarded by its spec, so spec and source revert together.

---

## Implementation Notes (update during execution)

### Progress Log
- 2026-08-06: Plan created; approach and substrate findings recorded; baselines green.
- 2026-08-06: Revisions 2–5 responded to Reviews 1–4. Each replaced the prior load-bearing
  mechanism after source inspection invalidated it: worker evidence record → unauthenticated
  progress records → quiet boundary → lobby prohibition plus quiescence guard. Along the way a
  proposed lead-owned run ledger was rejected (it mirrored Crew state, and ADR 0003 records that
  this repo's last duplicated store "drifted from reality"), and `review-task` was removed.
- 2026-08-06: **Revision 6 — descoped to Phase A.** Review 5 assessed the plan as NOT
  CONVERGING. The decisive evidence: all five rounds put every blocker in the runtime
  dispatch/review interleaving, while config, reviewer contract, plan skill, docs, closure, and
  the `check` metrics/gate never blocked once. Removed continuous overlap, the conditional hold,
  boundary evidence capture, `--evidence`, `--require-quiescent`, and every `review-wave`
  change; retained the existing wave barrier and added review discipline to it. ADR 0005 now
  records the Phase A/B split and **amends** ADR 0004's worker-evidence consequence rather than
  claiming it satisfied (RN-16). T8 gained its missing break-it step (RN-14). RN-15 is moot: no
  optional flags are added, so `parseOptions` is untouched. Tasks stay T1–T8; metrics improved
  to mean width 2.0 and ratio 0.52.

### Evidence Ledger
- 2026-08-06: `crew_continue` steer returns lead turns per boundary — `index.ts`; native review
  diffs committed history only — `crew/handlers/review.ts` (`git diff ${baseCommit}..HEAD`,
  50 KB truncation).
- 2026-08-06: `TaskEvidence` is `commits`/`tests`/`prs` only (`crew/types.ts:30-34`); no public
  action writes `review_count`/`last_review`; lobby-assigned tasks are excluded from
  `remainingTasks` and therefore from `succeeded` (`work.ts:173`); spawned and lobby workers
  receive randomly generated agent names and `task.progress` checks neither assignment nor
  status, so worker authorship cannot be authenticated.
- 2026-08-06: lobby workers write `<crewDir>/lobby-<id>.alive` at spawn and unlink it on exit
  (`crew/lobby.ts:119`, `:178`), so lobby presence **is** filesystem-observable. Recorded for
  Phase B; unused in Phase A.

### Deviations
- none yet

### Issues Encountered
- none yet

### Follow-ups
- none yet (the calibration backlog item is created by T8)
