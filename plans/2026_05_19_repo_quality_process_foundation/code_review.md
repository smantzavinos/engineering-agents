# Code Review Log

## Open Issues (roll-up — update each pass)

| ID | Severity | Issue | File(s) | Status |
|---|---|---|---|---|
| RN-01 | Critical | Theme-override collision snapshots still fail the real proof-set contract helper | `tests/scripts/resource-snapshot.mjs`, `tests/specs/proof-set-runtime-spec.sh` | resolved |
| RN-02 | Major | Override-guidance consistency sweep and readiness coverage are incomplete | `docs/orchestration.md`, `agents/README.md`, `agents/AGENTS.md`, `skills/assess-repo/SKILL.md`, `skills/assess-repo/references/agent-configuration.md`, `tests/specs/repo-readiness-docs-spec.sh` | resolved |

---

## Review 2026-05-19 (Review 1)

**Plan:** `plans/2026_05_19_repo_quality_process_foundation/plan.md`
**Diff:** `f7bd65c..da95416` (`task(T1)` through `task(T7)`)
**Mode:** full

### Coverage Matrix Compliance

| Behavior | Primary test | Negative/edge | Status |
|----------|-------------|---------------|--------|
| Root agent entry point routes to the correct repo-specific docs | ✅ `tests/specs/repo-readiness-docs-spec.sh` | ✅ Missing routes / missing anchors are checked | ✅ covered |
| Canonical testing strategy maps commands to standard levels, scope, timing, and prerequisites | ✅ `tests/specs/repo-readiness-docs-spec.sh` | ✅ Missing gate wording / command references are checked | ✅ covered |
| Repo backlog operations are agent-executable with stable IDs and source backlinks | ✅ `tests/specs/repo-readiness-docs-spec.sh` | ✅ Missing operations / source-backlink rules are checked | ✅ covered |
| Repo requirements are durable and citeable with explicit approval boundaries | ✅ `tests/specs/repo-readiness-docs-spec.sh`, `tests/specs/proof-set-runtime-spec.sh` | ✅ Missing ID/citation/approval-boundary hooks are checked | ✅ covered |
| Specialized areas expose local guidance instead of overloading the root doc | ✅ `tests/specs/repo-readiness-docs-spec.sh` | ✅ Missing local guides / anti-pattern sections are checked | ✅ covered |
| Proof-set verification resolves the active Pi module package path and surfaces failures honestly | ⚠️ `tests/specs/proof-set-runtime-spec.sh`, `./tests/run-tests.sh all` | ⚠️ Current+legacy namespaces and env failures are covered, but the new theme-collision path is not verified through `assert-contract.sh` and still fails there | ⚠️ partial |
| Override guidance consistently prefers `agentOverrides` over copied `.pi/agents/*.md` files | ⚠️ `tests/specs/repo-readiness-docs-spec.sh` | ⚠️ `agents/README.md` is checked, but the declared source-of-truth doc `docs/orchestration.md` is not covered and still disagrees with newer repo-local wording | ⚠️ partial |

### Prior Findings Resolution (delta mode only)

Not applicable — first review.

### Test Adequacy

- Anti-patterns found: none
- Break-it evidence in worklog:
  - T1: ✅ recorded
  - T2: ✅ recorded
  - T3: ✅ recorded
  - T4: ✅ recorded
  - T5: ✅ recorded
  - T6: ✅ recorded
  - T7: ✅ recorded
- TODOs without backlog IDs: none
- Reviewer verification run:
  - ✅ `./tests/run-tests.sh fast`
  - ✅ `./tests/run-tests.sh all`
  - ✅ Manual markdown-link resolution check across touched docs
  - ❌ Custom repro showed the theme-collision snapshot still fails the real contract helper (details in RN-01)

### Implementation Findings

#### Blocker
<none>

#### Critical

##### RN-01: Theme-override collision snapshots still fail the real proof-set contract helper
- **Severity:** Critical
- **File(s):** `tests/scripts/resource-snapshot.mjs:426-480`, `tests/specs/proof-set-runtime-spec.sh:471-500`
- **Problem:** T7 added theme-collision handling so proof-set themes stay discoverable and false local-theme warnings are suppressed, but `gatherPackageDiagnostics()` still attaches the collision as a package theme diagnostic whenever the diagnostic path points at the losing package theme path. `assert-contract.sh` rejects any per-package theme diagnostics, so the real helper path still fails for the same collision shape the new runtime spec fabricates.
- **Why it matters:** This leaves `FR-006` only partially implemented. A supported top-level theme override can still make `tests/test-fast.sh` / `./tests/run-tests.sh all` fail depending on the collision diagnostic shape, which undercuts the plan's goal of trustworthy proof-set verification.
- **Evidence:** I reproduced this by generating a snapshot with the same fake collision layout used by `write_fake_theme_override_pi_module` and then running `bash tests/scripts/assert-contract.sh --fixture <fixture> --snapshot <snapshot>`. The snapshot contained `proofSet[0].diagnostics.themes[0]`, and the helper failed with `Package beta has unexpected theme diagnostics`.
- **Proposed fix:** Filter proof-set theme-collision bookkeeping out of per-package diagnostics (or otherwise normalize that case so it does not violate the helper contract), then extend `tests/specs/proof-set-runtime-spec.sh` to run `assert-contract.sh` against the collision snapshot so the real helper path is covered.
- **Status:** open

#### Major

##### RN-02: Override-guidance consistency sweep and readiness coverage are incomplete
- **Severity:** Major
- **File(s):** `docs/orchestration.md:565-662`, `agents/README.md:72`, `agents/AGENTS.md:19-20`, `skills/assess-repo/SKILL.md:73-75,340-345,404-405,483`, `skills/assess-repo/references/agent-configuration.md:3,15-28`, `tests/specs/repo-readiness-docs-spec.sh`
- **Problem:** The new repo-local docs now describe the override path as `.pi/settings.json` → `subagents.agentOverrides`, but other repo docs and skill references still describe the configuration more loosely as plain `agentOverrides` in `.pi/settings.json`. The plan's coverage matrix explicitly named `docs/orchestration.md` as a source of truth for this behavior, yet the readiness spec only checks `agents/README.md`/`agents/AGENTS.md` and never verifies the orchestration doc or assess-repo guidance.
- **Why it matters:** The current-plan consistency sweep is incomplete: contributors can still encounter conflicting instructions about the exact override location, and the new readiness coverage would not catch drift in one of the plan-declared source documents.
- **Proposed fix:** Align the override wording across `docs/orchestration.md`, the assess-repo skill/reference docs, and the new repo-local guides around one canonical `.pi/settings.json` path; then extend `tests/specs/repo-readiness-docs-spec.sh` to cover the declared source-of-truth doc(s) for override guidance.
- **Status:** open

#### Minor
<none>

### Suggested Backlog Items

<none>

### Documentation Alignment

| Promised update | Present in diff? | Status |
|----------------|-----------------|--------|
| Root routing + canonical repo docs | Yes | ✅ |
| Testing strategy made canonical in `AGENTS.md` / `tests/README.md` | Yes | ✅ |
| Backlog + requirements + operational-memory docs added and cross-linked | Yes | ✅ |
| Override-guidance cleanup across the declared source docs | Partial | ❌ |
| Proof-set namespace support and explicit environment-failure handling | Yes | ✅ |

### Requirements Alignment

- Cited requirements still satisfied: No — `FR-006` remains open because the new theme-collision path still fails the real proof-set helper in the reproduced collision shape above.
- Approved requirement updates applied: Yes
- Undocumented requirement changes: none
- Tests/evidence cite requirements where expected: Yes

### Summary
| ID | Severity | File(s) | Status |
|---|---|---|---|
| RN-01 | Critical | `tests/scripts/resource-snapshot.mjs`, `tests/specs/proof-set-runtime-spec.sh` | open |
| RN-02 | Major | `docs/orchestration.md`, `agents/README.md`, `agents/AGENTS.md`, `skills/assess-repo/SKILL.md`, `skills/assess-repo/references/agent-configuration.md`, `tests/specs/repo-readiness-docs-spec.sh` | open |

### Review Status
- New significant issues: 2
- Suggested backlog items: 0
- Total open significant issues: 2
- Status: NEEDS_FIX

Code Review Summary:
- Coverage matrix: 5/7 rows covered
- New issues: 0 Blocker, 1 Critical, 1 Major
- Prior issues resolved: 0
- Suggested backlog items: 0
- Total open significant issues: 2
- Status: NEEDS_FIX

---

## Review 2026-05-19 (Review 2)

**Plan:** `plans/2026_05_19_repo_quality_process_foundation/plan.md`
**Diff:** `da95416..3205f05` (`fix(review): address proof-set collision and override guidance consistency`)
**Mode:** delta (full branch context from Review 1 retained)

### Coverage Matrix Compliance

| Behavior | Primary test | Negative/edge | Status |
|----------|-------------|---------------|--------|
| Root agent entry point routes to the correct repo-specific docs | ✅ `tests/specs/repo-readiness-docs-spec.sh` | ✅ Missing routes / missing anchors are checked | ✅ covered |
| Canonical testing strategy maps commands to standard levels, scope, timing, and prerequisites | ✅ `tests/specs/repo-readiness-docs-spec.sh` | ✅ Missing gate wording / command references are checked | ✅ covered |
| Repo backlog operations are agent-executable with stable IDs and source backlinks | ✅ `tests/specs/repo-readiness-docs-spec.sh` | ✅ Missing operations / source-backlink rules are checked | ✅ covered |
| Repo requirements are durable and citeable with explicit approval boundaries | ✅ `tests/specs/repo-readiness-docs-spec.sh`, `tests/specs/proof-set-runtime-spec.sh` | ✅ Missing ID/citation/approval-boundary hooks are checked | ✅ covered |
| Specialized areas expose local guidance instead of overloading the root doc | ✅ `tests/specs/repo-readiness-docs-spec.sh` | ✅ Missing local guides / anti-pattern sections are checked | ✅ covered |
| Proof-set verification resolves the active Pi module package path and surfaces failures honestly | ✅ `tests/specs/proof-set-runtime-spec.sh`, `tests/scripts/assert-contract.sh`, `./tests/run-tests.sh all` | ✅ Current+legacy namespaces, explicit env failure, top-level theme collision, and real helper-path assertion are covered | ✅ covered |
| Override guidance consistently prefers `agentOverrides` over copied `.pi/agents/*.md` files | ✅ `tests/specs/repo-readiness-docs-spec.sh` | ✅ Readiness coverage now checks `docs/orchestration.md`, `agents/README.md`, and assess-repo guidance for the canonical `.pi/settings.json` → `subagents.agentOverrides` wording | ✅ covered |

### Prior Findings Resolution (delta mode only)

| ID | Prior status | Current status | Evidence |
|----|-------------|----------------|----------|
| RN-01 | open | ✅ resolved | `tests/scripts/resource-snapshot.mjs` now suppresses top-level-winner theme collisions from per-package diagnostics, and `tests/specs/proof-set-runtime-spec.sh` exercises the collision snapshot through `tests/scripts/assert-contract.sh`; verified with `bash tests/specs/proof-set-runtime-spec.sh` and `./tests/run-tests.sh all`. |
| RN-02 | open | ✅ resolved | `docs/orchestration.md`, `skills/assess-repo/SKILL.md`, and `skills/assess-repo/references/agent-configuration.md` now use the canonical `.pi/settings.json` → `subagents.agentOverrides` wording, and `tests/specs/repo-readiness-docs-spec.sh` asserts those docs directly. |

### Test Adequacy

- Anti-patterns found: none
- Break-it evidence in worklog:
  - T1: ✅ recorded
  - T2: ✅ recorded
  - T3: ✅ recorded
  - T4: ✅ recorded
  - T5: ✅ recorded
  - T6: ✅ recorded
  - T7: ✅ recorded
- TODOs without backlog IDs: none
- Reviewer verification run:
  - ✅ `bash tests/specs/proof-set-runtime-spec.sh`
  - ✅ `bash tests/specs/repo-readiness-docs-spec.sh`
  - ✅ `./tests/run-tests.sh fast`
  - ✅ `./tests/run-tests.sh all`

### Implementation Findings

#### Blocker
<none>

#### Critical
<none>

#### Major
<none>

#### Minor
<none>

### Suggested Backlog Items

<none>

### Documentation Alignment

| Promised update | Present in diff? | Status |
|----------------|-----------------|--------|
| Root routing + canonical repo docs | Yes | ✅ |
| Testing strategy made canonical in `AGENTS.md` / `tests/README.md` | Yes | ✅ |
| Backlog + requirements + operational-memory docs added and cross-linked | Yes | ✅ |
| Override-guidance cleanup across the declared source docs | Yes | ✅ |
| Proof-set namespace support and explicit environment-failure handling | Yes | ✅ |

### Requirements Alignment

- Cited requirements still satisfied: Yes
- Approved requirement updates applied: Yes
- Undocumented requirement changes: none
- Tests/evidence cite requirements where expected: Yes

### Summary
| ID | Severity | File(s) | Status |
|---|---|---|---|
| RN-01 | Critical | `tests/scripts/resource-snapshot.mjs`, `tests/specs/proof-set-runtime-spec.sh` | resolved |
| RN-02 | Major | `docs/orchestration.md`, `agents/README.md`, `agents/AGENTS.md`, `skills/assess-repo/SKILL.md`, `skills/assess-repo/references/agent-configuration.md`, `tests/specs/repo-readiness-docs-spec.sh` | resolved |

### Review Status
- New significant issues: 0
- Prior issues resolved: 2
- Suggested backlog items: 0
- Total open significant issues: 0
- Status: COMPLETE

Code Review Summary:
- Coverage matrix: 7/7 rows covered
- New issues: 0 Blocker, 0 Critical, 0 Major
- Prior issues resolved: 2
- Suggested backlog items: 0
- Total open significant issues: 0
- Status: COMPLETE
