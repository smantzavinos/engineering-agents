# Plan Review

## Open Issues (roll-up — update each pass)

| ID | Severity | Issue | Location | Decision required | Status |
|---|---|---|---|---|---|
| RN-01 | Critical | Logic bug: interactive launch whitelist is still undefined | Open Questions / Acceptance checklist / T3 | Yes | open |
| RN-02 | Major | Logic bug: startup-mode timeout/concurrency/expiry defaults are still open | Assumptions / Open Questions / T2 / T3 | Yes | open |
| RN-03 | Major | Logic bug: startup workflow wording could false-green via docs-only coverage | T4 / T5 / Coverage Matrix | No | applied |
| RN-04 | Major | Status-engine/manual-helper contract tests omitted required reason-code, warning-shape, and npm-only update safeguards | T2 / Tooling contract / Coverage Matrix | No | applied |
| RN-05 | Major | Logic bug: wrapper/runtime wiring and startup snapshot contract verification were under-specified | Acceptance checklist / T3 / T4 | No | applied |

## Open Decisions (roll-up — update each pass)

| ID | Decision | Options | Recommendation | Status |
|---|---|---|---|---|
| OD-01 | Which argv forms count as documented interactive launches in v1? | Plain `pi` only; plain `pi` plus an explicit whitelist; broader argv classifier | Pick and enumerate the exact whitelist in the plan, then make every other form an explicit fail-open skip case | Open |
| OD-02 | What startup-mode defaults ship for time budget and freshness? | Concrete per-source/overall/concurrency/expiry defaults; config-driven defaults; defer tuning to implementer | Choose concrete defaults now and keep tests injectable so runtime behavior is predictable | Open |

---

## Review 2026-05-19 (Review 1)

**Plan:** `plans/startup-extension-staleness-warning/plan.md`
**Scope:** full
**Handoff readiness:** No

### Implementer Decisions Remaining
- Exact CLI whitelist of invocation forms that count as interactive launches beyond plain `pi`, plus which forms are explicitly skipped.
- Concrete default per-source timeout, overall startup timeout, concurrency cap, and snapshot freshness/expiry window for startup mode.
- Both decisions change user-visible startup behavior; the launch-whitelist decision also changes the CLI boundary.

### Test Adequacy Assessment
- Coverage matrix complete: Yes
- Negative/edge cases identified for each row: Yes
- Bad-test avoidance addressed in approach.md: Yes
- E2E seed/fixture data confirmed to support scenarios: N/A
- TDD checklists include break-it step for all tasks: Yes

### Issues

#### Blocker
<none>

#### Critical

##### RN-01: Logic bug: interactive launch whitelist is still undefined
- **Severity:** Critical
- **Location:** Open Questions / Acceptance checklist / T3
- **Problem:** The plan now correctly surfaces this as an open question, but it still does not decide which argv forms beyond plain `pi` are treated as supported interactive launches. T3 tests only plain `pi`, `--help`, `list`, and `--version`, while the acceptance checklist and task notes talk about “documented interactive launches” generically.
- **Why it matters:** This is a CLI-boundary decision. Different implementers could legitimately ship materially different behavior for forms like directory-targeted launches or any other argv-bearing interactive entrypoints, which changes who sees the warning and who silently skips it.
- **Fix:** Surface the unresolved choice explicitly in the plan and require a follow-up pass to choose and enumerate the supported v1 launch forms.
- **Decision required:** Yes
- **Status:** open

#### Major

##### RN-02: Logic bug: startup-mode timeout/concurrency/expiry defaults are still open
- **Severity:** Major
- **Location:** Assumptions / Open Questions / T2 / T3
- **Problem:** The plan says timeout/concurrency defaults may be tuned during implementation, and it requires `expiresAt` in the startup snapshot, but it never picks concrete runtime defaults for per-source timeout, overall timeout, concurrency cap, or freshness/expiry window.
- **Why it matters:** Those values directly affect whether users see `stale` vs `unknown`, how much startup latency they incur, and whether a valid snapshot is accepted or ignored. Leaving them open means the implementer still has to make product/UX decisions during execution.
- **Fix:** Surface the missing decision explicitly in the plan. A follow-up pass should choose concrete defaults and add them to the contract/acceptance language while keeping tests injectable.
- **Decision required:** Yes
- **Status:** open

##### RN-03: Logic bug: startup workflow wording could false-green via docs-only coverage
- **Severity:** Major
- **Location:** T4 / T5 / Coverage Matrix
- **Problem:** The original plan required startup warnings to direct users to the supported inspection/apply workflow, but the task checklists primarily tested docs/helper availability. That left a false-green path where README text could be corrected while the actual notifier copy still implied the wrong scope or workflow.
- **Why it matters:** The user-facing contract lives in the startup warning itself, not just in docs. Shipping mismatched notifier/helper/README wording would recreate the contradictory-guidance problem the approach was trying to prevent.
- **Fix:** Updated T4, T5, the acceptance checklist, and the coverage matrix so notifier copy, helper output, and README wording must align on managed-scope language plus `check-updates --dry-run` / `home-manager switch` guidance.
- **Decision required:** No
- **Status:** applied

##### RN-04: Status-engine/manual-helper contract tests omitted required reason-code, warning-shape, and npm-only update safeguards
- **Severity:** Major
- **Location:** T2 / Tooling contract / Coverage Matrix
- **Problem:** The plan's tooling contract required stable unknown reason codes, warning-object shape, specific exit behaviors, and npm-only `--update` semantics, but the T2 checklist did not require tests for those behaviors.
- **Why it matters:** The implementation could satisfy the prior checklist while still breaking the advertised contract for manual/startup consumers or reintroducing contradictory `--update` behavior.
- **Fix:** Updated T2 so the spec must cover all required unknown reason codes, warning object shape, missing-manifest/input exit 2 behavior, and the guard that `--update` stays npm-only.
- **Decision required:** No
- **Status:** applied

##### RN-05: Logic bug: wrapper/runtime wiring and startup snapshot contract verification were under-specified
- **Severity:** Major
- **Location:** Acceptance checklist / T3 / T4
- **Problem:** The original wrapper task did not require an absolute-path handoff to the real Pi binary/helper runtime, and it did not require tests for the launch metadata fields or notifier consumption of a contract-faithful startup snapshot.
- **Why it matters:** The wrapper could recurse into itself via PATH resolution, or the wrapper and notifier could drift on snapshot shape while separate task-local tests still passed.
- **Fix:** Updated the acceptance checklist and T3/T4 details so the wrapper must use injected absolute paths, wrapper specs must assert launch metadata fields, and notifier coverage must accept a snapshot matching the shared startup-status contract without ad hoc translation glue.
- **Decision required:** No
- **Status:** applied

#### Minor
<none>

### Summary
| ID | Severity | Location | Decision required | Status |
|---|---|---|---|---|
| RN-01 | Critical | Open Questions / Acceptance checklist / T3 | Yes | open |
| RN-02 | Major | Assumptions / Open Questions / T2 / T3 | Yes | open |
| RN-03 | Major | T4 / T5 / Coverage Matrix | No | applied |
| RN-04 | Major | T2 / Tooling contract / Coverage Matrix | No | applied |
| RN-05 | Major | Acceptance checklist / T3 / T4 | No | applied |

### Changes Applied to Plan
- Surfaced the still-open CLI launch-whitelist and startup timing/freshness questions in `Open Questions`.
- Tightened T1 manifest-contract coverage to require the source identity/install fields the status engine depends on.
- Tightened T2 status-engine/manual-helper coverage for required reason codes, warning shape, missing-input exit behavior, and npm-only `--update` safeguards.
- Tightened T3 wrapper requirements around injected absolute runtime paths and launch snapshot metadata.
- Tightened T4/T5 coverage so notifier copy, helper output, and README guidance must align, and the notifier must accept a contract-faithful startup snapshot.

### Review Status
- Significant issues found: 5
- Status: NEEDS_ANOTHER_PASS
