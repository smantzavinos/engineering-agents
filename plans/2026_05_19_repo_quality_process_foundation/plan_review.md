## Open Issues (roll-up — update each pass)

| ID | Severity | Issue | Location | Decision required | Status |
|---|---|---|---|---|---|
| RN-01 | Major | Logic bug: T5 could run before the requirements system and backlog-linked AGENTS routing were established | Task graph / T5 | No | applied |
| RN-02 | Major | Logic bug: T4 could modify or cite the proof-set runtime spec before T2 created that spec and tooling contract | Task graph / T4 | No | applied |
| RN-03 | Major | Logic bug: the baseline gate policy contradicted the task ordering by requiring global-gate repair before work intentionally scheduled ahead of T2 | Baseline Gate Audit / task graph | No | applied |

## Open Decisions (roll-up — update each pass)

| ID | Decision | Options | Recommendation | Status |
|---|---|---|---|---|
| none | none | n/a | n/a | closed |

---

## Review 2026-05-19 (Review 1)

**Plan:** `plans/2026_05_19_repo_quality_process_foundation/plan.md`
**Scope:** full
**Handoff readiness:** No

### Implementer Decisions Remaining
- None after this review pass.

### Test Adequacy Assessment
- Coverage matrix complete: Yes
- Negative/edge cases identified for each row: Yes
- Bad-test avoidance addressed in approach.md: No
- Bad-test avoidance addressed in plan.md: Yes
- E2E seed/fixture data confirmed to support scenarios: N/A
- TDD checklists include break-it step for all tasks: Yes

### Issues

#### Blocker
none

#### Critical
none

#### Major

##### RN-01: Logic bug: T5 sequencing allowed a dependency gap
- **Severity:** Major
- **Location:** `Task Graph`, `T5: Add specialized-area guidance and .llm instructions`
- **Problem:** T5 originally depended only on T1 and T2, but the task updates root `AGENTS.md`, references requirement IDs "from T4 once established," and relies on the repo requirements/backlog routing being in place. That allowed T5 to execute before T4, creating both a dependency contradiction and a same-file sequencing hazard on `AGENTS.md`.
- **Why it matters:** An implementer could legally execute T5 before the requirements system exists, forcing an extra design decision about placeholder requirement refs and risking churn/conflicts in root routing. That violates the plan's goal of handoff-ready execution without new design choices.
- **Fix:** Updated T5 to depend on `T2, T4` in both the task graph and the task detail section.
- **Decision required:** No
- **Status:** applied

#### Minor
none

### Summary
| ID | Severity | Location | Decision required | Status |
|---|---|---|---|---|
| RN-01 | Major | Task graph / T5 | No | applied |

### Changes Applied to Plan
- Changed T5 dependency in the task graph from `T1, T2` to `T2, T4`.
- Changed the T5 task-detail dependency line from `T1, T2` to `T2, T4`.

### Review Status
- Significant issues found: 1
- Status: NEEDS_ANOTHER_PASS

---

## Review 2026-05-19 (Review 2)

**Plan:** `plans/2026_05_19_repo_quality_process_foundation/plan.md`
**Scope:** delta
**Handoff readiness:** No

### Implementer Decisions Remaining
- None after this review pass.

### Test Adequacy Assessment
- Coverage matrix complete: Yes
- Negative/edge cases identified for each row: Yes
- Bad-test avoidance addressed in approach.md: No
- Bad-test avoidance addressed in plan.md: Yes
- E2E seed/fixture data confirmed to support scenarios: N/A
- TDD checklists include break-it step for all tasks: Yes

### Issues

#### Blocker
none

#### Critical
none

#### Major

##### RN-02: Logic bug: T4 sequencing skipped the proof-set spec dependency
- **Severity:** Major
- **Location:** `Task Graph`, `T4: Establish lightweight requirements system`
- **Problem:** T4 originally depended on `T1, T3` but its checklist explicitly adds assertions to `tests/specs/proof-set-runtime-spec.sh` and applies requirement citations to that spec. That file and its surrounding tooling contract are introduced in T2, so T4 could execute before the proof-set runtime spec existed.
- **Why it matters:** An implementer could reach T4 and be forced to either invent a temporary file shape, skip the cited requirement-citation work, or silently reorder tasks. That is a task-graph contradiction and leaves execution dependent on an unstated decision.
- **Fix:** Updated T4 to depend on `T1, T2, T3` in both the task graph and the task detail section.
- **Decision required:** No
- **Status:** applied

#### Minor
none

### Summary
| ID | Severity | Location | Decision required | Status |
|---|---|---|---|---|
| RN-02 | Major | Task graph / T4 | No | applied |

### Changes Applied to Plan
- Changed T4 dependency in the task graph from `T1, T3` to `T1, T2, T3`.
- Changed the T4 task-detail dependency line from `T1, T3` to `T1, T2, T3`.

### Review Status
- Significant issues found: 1
- Status: NEEDS_ANOTHER_PASS

---

## Review 2026-05-19 (Review 3)

**Plan:** `plans/2026_05_19_repo_quality_process_foundation/plan.md`
**Scope:** delta
**Handoff readiness:** No

### Implementer Decisions Remaining
- None after this review pass.

### Test Adequacy Assessment
- Coverage matrix complete: Yes
- Negative/edge cases identified for each row: Yes
- Bad-test avoidance addressed in approach.md: No
- Bad-test avoidance addressed in plan.md: Yes
- E2E seed/fixture data confirmed to support scenarios: N/A
- TDD checklists include break-it step for all tasks: Yes

### Issues

#### Blocker
none

#### Critical
none

#### Major

##### RN-03: Logic bug: baseline gate policy conflicted with the intended task sequence
- **Severity:** Major
- **Location:** `Decisions`, `Baseline Gate Audit`, task ordering around `T1`/`T2`/`T3`
- **Problem:** The plan said `block-on-global-gate`, which means pre-existing repo-wide failures must be resolved before continuing implementation. But the task graph intentionally allowed work such as T1 and T3 before T2 repaired the ambiguous `./tests/run-tests.sh all` gate.
- **Why it matters:** An implementer would face a contradiction between the stated gate policy and the planned execution order. They would have to guess whether to stop all work until T2 was done, silently reorder tasks, or ignore the policy text.
- **Fix:** Changed the chosen global-gate policy and baseline-gate policy to `allow-scoped-completion`, with explicit rationale that T2 repairs the repo-wide gate early while `./tests/run-tests.sh fast` remains the reliable task gate and `./tests/run-tests.sh all` is still required before plan completion.
- **Decision required:** No
- **Status:** applied

#### Minor
none

### Summary
| ID | Severity | Location | Decision required | Status |
|---|---|---|---|---|
| RN-03 | Major | Baseline Gate Audit / task ordering | No | applied |

### Changes Applied to Plan
- Changed the `Global gate policy` decision row from `block-on-global-gate` to `allow-scoped-completion` with rationale consistent with the planned sequencing.
- Changed the `Gate policy for this plan` section from `block-on-global-gate` to `allow-scoped-completion` and clarified that `fast` is the reliable task gate until T2 repairs `all`.

### Review Status
- Significant issues found: 1
- Status: NEEDS_ANOTHER_PASS

---

## Review 2026-05-19 (Review 4)

**Plan:** `plans/2026_05_19_repo_quality_process_foundation/plan.md`
**Scope:** delta
**Handoff readiness:** Yes

### Implementer Decisions Remaining
- None.

### Test Adequacy Assessment
- Coverage matrix complete: Yes
- Negative/edge cases identified for each row: Yes
- Bad-test avoidance addressed in approach.md: No
- Bad-test avoidance addressed in plan.md: Yes
- E2E seed/fixture data confirmed to support scenarios: N/A
- TDD checklists include break-it step for all tasks: Yes

### Issues

#### Blocker
none

#### Critical
none

#### Major
none

#### Minor
none

### Summary
| ID | Severity | Location | Decision required | Status |
|---|---|---|---|---|
| none | none | n/a | No | n/a |

### Changes Applied to Plan
- none

### Review Status
- Significant issues found: 0
- Status: COMPLETE
