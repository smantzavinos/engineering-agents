# Plan Review

## Open Issues (roll-up — update each pass)

| ID | Severity | Issue | Location | Decision required | Status |
|---|---|---|---|---|---|
| RN-01 | Critical | Logic bug: interactive launch whitelist is still undefined | Open Questions / Acceptance checklist / T3 | Yes | open |
| RN-02 | Major | Logic bug: startup-mode timeout/concurrency/expiry defaults are still open | Assumptions / Open Questions / T2 / T3 | Yes | open |
| RN-03 | Major | Logic bug: startup workflow wording could false-green via docs-only coverage | T4 / T5 / Coverage Matrix | No | applied |
| RN-04 | Major | Status-engine/manual-helper contract tests omitted required reason-code, warning-shape, and npm-only update safeguards | T2 / Tooling contract / Coverage Matrix | No | applied |
| RN-05 | Major | Logic bug: wrapper/runtime wiring and startup snapshot contract verification were under-specified | Acceptance checklist / T3 / T4 | No | applied |
| RN-06 | Major | Logic bug: warning taxonomy required skip/ignored warning payloads that conflict with silent no-op paths | Warning taxonomy / Acceptance checklist / T3 / T4 | No | applied |
| RN-07 | Major | Logic bug: notifier footer/status summary behavior lacked concrete verification | Acceptance checklist / T4 / Coverage Matrix | No | applied |
| RN-08 | Major | Logic bug: wrapper PATH-shadowing guard for Node/helper resolution was not concretely tested | Acceptance checklist / T3 / Coverage Matrix | No | applied |
| RN-09 | Major | Logic bug: whole-run status-check failure contract is still contradictory | Exit code policy / Warning taxonomy / T2 / T3 / T4 | Yes | open |

## Open Decisions (roll-up — update each pass)

| ID | Decision | Options | Recommendation | Status |
|---|---|---|---|---|
| OD-01 | Which argv forms count as documented interactive launches in v1? | Plain `pi` only; plain `pi` plus an explicit whitelist; broader argv classifier | Pick and enumerate the exact whitelist in the plan, then make every other form an explicit fail-open skip case | Open |
| OD-02 | What startup-mode defaults ship for time budget and freshness? | Concrete per-source/overall/concurrency/expiry defaults; config-driven defaults; defer tuning to implementer | Choose concrete defaults now and keep tests injectable so runtime behavior is predictable | Open |
| OD-03 | What should startup/manual surfaces do when the shared checker fails as a whole? | Wrapper/manual frontend synthesize degraded fallback output; startup fallback only with manual hard error; silent startup skip + manual hard error | Assign fallback responsibility explicitly per surface and align warning code, exit status, snapshot behavior, and notifier/manual UX around that choice | Open |

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

---

## Review 2026-05-19 (Review 2)

**Plan:** `plans/startup-extension-staleness-warning/plan.md`
**Scope:** delta
**Handoff readiness:** No

### Implementer Decisions Remaining
- Exact CLI whitelist of invocation forms that count as interactive launches beyond plain `pi`, plus which forms are explicitly skipped.
- Concrete default per-source timeout, overall startup timeout, concurrency cap, and snapshot freshness/expiry window for startup mode.
- Exact fallback behavior when the shared checker cannot produce a whole-run result: which layer synthesizes the fallback, whether startup writes a degraded snapshot or stays silent, and what `check-updates` prints/exits with in that path.
- All three decisions change user-visible startup/manual behavior; the launch-whitelist and whole-run failure choices also touch CLI/TUI contracts.

### Test Adequacy Assessment
- Coverage matrix complete: No (whole-run status-check failure fallback still lacks an explicit mapped behavior/test row)
- Negative/edge cases identified for each row: No (whole-run checker failure still lacks explicit fallback verification)
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
- **Problem:** Review 1 left this as an explicit open question, and Review 2 still finds no chosen v1 whitelist. The plan continues to speak about “documented interactive launches” while only testing plain `pi`, `--help`, `list`, and `--version`.
- **Why it matters:** This remains a CLI-boundary decision. Different implementers could still ship materially different warning coverage for argv-bearing launches, creating churn in both wrapper behavior and tests.
- **Fix:** Choose and enumerate the exact supported interactive launch forms in the plan, then make every other form an explicit fail-open skip case.
- **Decision required:** Yes
- **Status:** open

#### Major

##### RN-02: Logic bug: startup-mode timeout/concurrency/expiry defaults are still open
- **Severity:** Major
- **Location:** Assumptions / Open Questions / T2 / T3
- **Problem:** Review 2 still finds no concrete per-source timeout, overall timeout, concurrency cap, or snapshot freshness/expiry default in the plan.
- **Why it matters:** Those values still determine startup latency, `unknown` frequency, and whether notifier freshness checks accept or ignore a snapshot. Leaving them open pushes product behavior decisions into implementation.
- **Fix:** Choose concrete v1 defaults in the plan and add them to the contract/acceptance language while keeping the values injectable in tests.
- **Decision required:** Yes
- **Status:** open

##### RN-06: Logic bug: warning taxonomy required skip/ignored warning payloads that conflict with silent no-op paths
- **Severity:** Major
- **Location:** Warning taxonomy / Acceptance checklist / T3 / T4
- **Problem:** The plan still required warning codes for intentionally skipped wrapper invocations and for ignored/malformed startup snapshots, even though the same plan requires skipped invocations to stay noise-free and malformed/missing snapshots cannot reliably carry structured warning payloads.
- **Why it matters:** That contradiction would force implementers either to pollute noninteractive output or invent warning payloads for files that are supposed to be ignored as invalid.
- **Fix:** Removed the impossible skip/ignored warning requirements and clarified that those paths are silent no-ops rather than part of the emitted warning contract.
- **Decision required:** No
- **Status:** applied

##### RN-07: Logic bug: notifier footer/status summary behavior lacked concrete verification
- **Severity:** Major
- **Location:** Acceptance checklist / T4 / Coverage Matrix
- **Problem:** The approach, file skeleton, and task notes required the notifier to keep a footer/status summary in sync with stale/unknown problems, but the plan's verification only proved `ctx.ui.notify(...)` behavior.
- **Why it matters:** An implementer could have skipped the persistent status/footer behavior and still satisfied the previous checklist, leaving part of the approved UX unproven.
- **Fix:** Updated the acceptance checklist, T4 deliverable/checklist, coverage matrix, and verification plan to require explicit footer/status-summary assertions and cleanup behavior when snapshots are ignored.
- **Decision required:** No
- **Status:** applied

##### RN-08: Logic bug: wrapper PATH-shadowing guard for Node/helper resolution was not concretely tested
- **Severity:** Major
- **Location:** Acceptance checklist / T3 / Coverage Matrix
- **Problem:** The plan said the wrapper must use injected absolute paths for the real Pi binary, Node runtime, and checker helper, but the wrapper spec only proved the real Pi path and could still false-green if `node` or the checker were rediscovered from PATH.
- **Why it matters:** That would leave the recursion/shadowing risk unresolved in the very area the approach was trying to harden.
- **Fix:** Updated the acceptance checklist, T3 checklist, coverage matrix, and verification plan so the wrapper spec must prove the checker/runtime are invoked through injected absolute paths rather than PATH lookup.
- **Decision required:** No
- **Status:** applied

##### RN-09: Logic bug: whole-run status-check failure contract is still contradictory
- **Severity:** Major
- **Location:** Exit code policy / Warning taxonomy / T2 / T3 / T4
- **Problem:** The plan still requires `PI_PACKAGE_WARN_STATUS_CHECK_FAILED` for startup/manual fallback, but it also says the shared checker/manual helper return exit 2/3 on dependency or internal failures, and no task specifies which layer synthesizes fallback JSON/text or whether startup should emit a degraded snapshot versus staying silent.
- **Why it matters:** Different implementers could legitimately ship incompatible behavior here: silent startup failure, a degraded startup snapshot, a manual hard error with no fallback text, or divergent startup/manual semantics. That is a contract-level ambiguity across CLI/TUI surfaces.
- **Fix:** Pick one explicit whole-run failure policy per surface, then update T2/T3/T4 so the responsible layer, exit status, snapshot behavior, warning code emission, and notifier/manual UX are all tested together.
- **Decision required:** Yes
- **Status:** open

#### Minor
<none>

### Summary
| ID | Severity | Location | Decision required | Status |
|---|---|---|---|---|
| RN-01 | Critical | Open Questions / Acceptance checklist / T3 | Yes | open |
| RN-02 | Major | Assumptions / Open Questions / T2 / T3 | Yes | open |
| RN-06 | Major | Warning taxonomy / Acceptance checklist / T3 / T4 | No | applied |
| RN-07 | Major | Acceptance checklist / T4 / Coverage Matrix | No | applied |
| RN-08 | Major | Acceptance checklist / T3 / Coverage Matrix | No | applied |
| RN-09 | Major | Exit code policy / Warning taxonomy / T2 / T3 / T4 | Yes | open |

### Changes Applied to Plan
- Aligned the requirement-update table so startup warning scope/workflow wording is traced to T4 as well as the existing doc/helper tasks.
- Removed impossible skip/ignored warning-code requirements and clarified those paths are silent no-op conditions.
- Tightened T3 acceptance/checklist/coverage/verification so the wrapper must prove absolute-path Node/helper handoff instead of only the real Pi binary handoff.
- Tightened T4 acceptance/checklist/coverage/verification so the notifier must keep footer/status summary behavior in sync with the warning state and clear stale status when snapshots are ignored.

### Review Status
- Significant issues found: 6
- Status: NEEDS_ANOTHER_PASS
