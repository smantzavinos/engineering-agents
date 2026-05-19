# Approach Review

## Open Issues (roll-up — update each pass)

| ID | Severity | Issue | Section | Status |
|---|---|---|---|---|
| RN-01 | Major | Scope narrowed to managed `piPackages` only without explicit requirement-change handling | Key Decisions / Requirements Alignment | resolved |
| RN-02 | Major | Launch-scoped snapshot contract was not defined safely enough for concurrent or skipped launches | Solution Model / Invariants & Safety Properties | resolved |
| RN-03 | Major | Manual workflow contract left room for contradictory startup-vs-CLI guidance | Components / Key Decisions / Boundary Definitions | resolved |

---

## Review 2026-05-19 (Review 1)

**Approach:** `/home/spiros/code/engineering-agents/plans/startup-extension-staleness-warning/approach.md`
**Brief alignment:** No

### Brief Alignment Check
| Brief Goal/Constraint | Addressed in Approach? | How |
|----------------------|------------------------|-----|
| Startup-time warning for out-of-date plugins | Yes | Wrapper-triggered check plus in-Pi notifier. |
| Non-blocking startup | Yes | Best-effort startup path with timeout/unknown handling. |
| Cover supported install types used by this repo, including git | No | The approach narrowed scope to managed `piPackages` only without recording an approved requirement change. |
| Distinguish stale vs unknown | Yes | Shared checker classified `current`, `stale`, and `unknown`. |
| Tell users what action to take next using the existing workflow | Partially | Startup messages referenced `check-updates`, but the supported operator contract remained ambiguous for git and `unknown` results. |
| No Pi core changes | Yes | Wrapper/module/helper/extension only. |

### Component & Boundary Assessment
- All components identified: No (missing a safe launch-correlation contract between wrapper output and the current Pi session)
- Interactions defined: No
- Boundaries clear to an implementer: No

### Decision Quality
- All approach-level decisions made: No (scope contract, launch correlation, and manual workflow semantics were still under-defined)
- Options and rationale documented: Partially

### Design Tenets & Invariants
- Tenets enforceable (not aspirational): Partially
- Invariants verifiable (testable): Partially
- Deviation protocol actionable: Yes

### Testing Philosophy
- Bad-test avoidance specific to this change: Yes
- Testing boundaries clear: Partially

### Issues

#### Blocker
<none>

#### Critical
<none>

#### Major

##### RN-01: Scope narrowed to managed `piPackages` only without explicit requirement-change handling
- **Severity:** Major
- **Section:** Key Decisions / What Stays / Boundary Definitions / Requirements Alignment / Requirement Change Proposal
- **Problem:** The brief said the warning should cover all supported plugin install types used by this repo, but the approach excluded direct cloned/symlinked installs while still claiming brief alignment and listing no requirement change.
- **Why it matters:** That was a material product-scope decision, not an implementation detail. Planning on top of it risked building the wrong feature.
- **Fix:** Require the approach either to cover the broader brief scope or to record the narrower managed-package contract explicitly as a requirement change needing approval.
- **Status:** open

##### RN-02: Launch-scoped snapshot contract was not defined safely enough for concurrent or skipped launches
- **Severity:** Major
- **Section:** Solution Model / How They Fit Together / Invariants & Safety Properties / Open Questions
- **Problem:** The original design described launch-scoped status state but still implied a fixed shared file, leaving ownership, freshness, skip behavior, and concurrent-launch handling undefined.
- **Why it matters:** Without an explicit per-launch contract, later sessions could replay stale warnings or clobber each other.
- **Fix:** Define how one wrapper run produces exactly one child-consumable snapshot, how skipped launches clear state, and how stale snapshots are ignored or consumed once.
- **Status:** open

##### RN-03: Manual workflow contract left room for contradictory startup-vs-CLI guidance
- **Severity:** Major
- **Section:** Components / Key Decisions / Boundary Definitions / Open Questions
- **Problem:** The approach shared classification logic with `check-updates` but still left the supported operator path, exit behavior, and `--update` semantics ambiguous for git and `unknown` results.
- **Why it matters:** Users could be told at startup that something is stale while the manual command still implied an update path that only really made sense for npm declaration rewrites.
- **Fix:** Promote the supported manual workflow, exit semantics, and safe startup wording to explicit design decisions.
- **Status:** open

#### Minor
<none>

### Changes Applied to Approach
- None.

### Review Status
- Significant issues found: 3
- Status: NEEDS_ANOTHER_PASS

---

## Review 2026-05-19 (Review 2)

**Approach:** `/home/spiros/code/engineering-agents/plans/startup-extension-staleness-warning/approach.md`
**Brief alignment:** Yes (with the managed-`piPackages` scope clarification explicitly recorded in the approach's requirement-change section)

### Brief Alignment Check
| Brief Goal/Constraint | Addressed in Approach? | How |
|----------------------|------------------------|-----|
| Startup-time warning for out-of-date plugins | Yes | Repo-owned `pi` wrapper runs a startup status check and a Pi startup notifier surfaces the result in-session. |
| Non-blocking startup | Yes | Startup mode is explicitly best-effort, time-budgeted, and degrades failures to `unknown` without blocking Pi launch. |
| Cover supported install types used by this repo, including git | Yes | The approach now records the design-time scope clarification that v1 covers the managed `piPackages` model (the install types actually represented in current managed plugin declarations), and it defines git freshness handling in the shared status engine. |
| Distinguish stale vs unknown | Yes | `current` / `stale` / `unknown` are first-class statuses, with stale and unknown rendered separately in the notifier and manual command. |
| Tell users what action to take next using the existing workflow | Yes | Startup warnings point users to `check-updates --dry-run` for inspection and the existing repo/Home Manager apply flow for actually picking up declaration or package changes. |
| No Pi core changes | Yes | All changes stay in the repo wrapper, Home Manager module, helper/status engine, and direct extension installation. |
| Avoid changing the update/install pipeline | Yes | The approach keeps this work at detection/notification scope and treats any retained `--update` behavior as legacy npm declaration rewriting, not a broader workflow redesign. |

### Component & Boundary Assessment
- All components identified: Yes
- Interactions defined: Yes
- Boundaries clear to an implementer: Yes

### Decision Quality
- All approach-level decisions made: Yes (remaining open questions are operational/planning details, not architectural gaps)
- Options and rationale documented: Yes

### Design Tenets & Invariants
- Tenets enforceable (not aspirational): Yes
- Invariants verifiable (testable): Yes
- Deviation protocol actionable: Yes

### Testing Philosophy
- Bad-test avoidance specific to this change: Yes
- Testing boundaries clear: Yes

### Issues

#### Blocker
<none>

#### Critical
<none>

#### Major
<none>

#### Minor
<none>

### Changes Applied to Approach
- None. The updated approach already addressed the prior significant findings, so this pass only records reassessment.

### Review Status
- Significant issues found: 0
- Status: COMPLETE
