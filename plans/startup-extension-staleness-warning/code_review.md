# Code Review Log

## Open Issues (roll-up — update each pass)

| ID | Severity | Issue | File(s) | Status |
|---|---|---|---|---|
| RN-04 | Critical | Branch refs now fall back to default-branch status when only a same-named tag exists, so deleted/renamed branches are misreported instead of `REF_MISSING` | `nix/modules/pi/check-managed-package-status.mjs`, `tests/spec-fixtures/managed-package-status/manifest.ok.json`, `tests/spec-fixtures/managed-package-status/fake-git`, `tests/specs/managed-package-status-spec.sh` | open |

---

## Review 2026-05-19 (Review 1)

**Plan:** `plans/startup-extension-staleness-warning/plan.md`
**Diff:** `main..HEAD`
**Mode:** full

### Coverage Matrix Compliance

| Behavior | Primary test | Negative/edge | Status |
|----------|-------------|---------------|--------|
| Activation persists authoritative install facts for each managed source | ✅ `tests/specs/managed-package-install-state-spec.sh` + `tests/specs/flake-eval-spec.sh` | ⚠️ Shared-source fan-out and sort order are covered, but there is no behavioral check for activation-time git fact capture or missing materialized-path/error cases | ⚠️ partial |
| Shared checker classifies npm and git sources as `current` / `stale` / `unknown` | ⚠️ `tests/specs/managed-package-status-spec.sh` | ⚠️ npm lookup failure, branch/default drift, timeout/auth/offline, and shared-source dedupe are covered, but tag-pinned git refs are not | ⚠️ partial |
| Manual `check-updates --dry-run` matches startup semantics and stays informational | ✅ `tests/specs/managed-package-status-spec.sh` | ✅ exit-code propagation, grouped results, and npm-only `--update` rewrite behavior are exercised at the script layer | ✅ covered |
| `pi` wrapper checks only interactive launches and exports a launch-owned snapshot path | ✅ `tests/specs/pi-startup-wrapper-spec.sh` | ✅ skip paths, env clearing, helper failure, PATH poisoning, and unique snapshots are exercised | ✅ covered |
| Startup notifier renders stale and unknown distinctly, keeps footer/status summary aligned, uses actionable managed-scope copy, and consumes a snapshot once | ✅ `tests/specs/startup-warning-extension-spec.sh` | ✅ expired/malformed/missing/unowned snapshots, replay prevention, and grouped package rendering are exercised | ✅ covered |
| Startup warning copy, helper output, and docs point users to the supported inspection/apply workflow | ⚠️ `tests/specs/pi-startup-warning-contract-spec.sh` + harness output + worklog `./tests/run-tests.sh all` | ⚠️ Workflow copy is covered, but helper-install verification is source-read only and does not exercise the packaged export | ⚠️ partial |

### Test Adequacy

- Anti-patterns found:
  - `tests/specs/pi-startup-warning-contract-spec.sh:115-126` verifies helper-install wiring by grepping `flake.nix` / `nix/modules/pi/default.nix` rather than exercising the packaged helper. That weak assertion missed the installed `--update` regression below.
- Break-it evidence in worklog:
  - T1: ✅ recorded
  - T2: ✅ recorded
  - T3: ✅ recorded
  - T4: ✅ recorded
  - T5: ✅ recorded
- TODOs without backlog IDs: none
- Reviewer verification:
  - `./tests/run-tests.sh fast`: ✅ pass

### Implementation Findings

#### Blocker
<none>

#### Critical

##### RN-01: Tag-pinned git refs are misclassified as branches
- **Severity:** Critical
- **File(s):** `nix/modules/pi/build-managed-package-install-state.mjs:97-108`, `nix/modules/pi/check-managed-package-status.mjs:454-467`, `tests/specs/managed-package-install-state-spec.sh:93-110`, `tests/specs/managed-package-status-spec.sh:161-175`
- **Problem:** `parseGitRef()` only treats hex commits and `semver:` fragments as `pinned`; every other `#ref` becomes `branch`. That means a managed git spec pinned to a tag like `github:org/pkg#v1.2.3` is stored as `gitRef.kind = "branch"`, and the status engine later looks for `refs/heads/v1.2.3` instead of treating it as a pinned ref and comparing it against the chosen upstream ref. For tagged installs, the checker will incorrectly return `unknown` / `REF_MISSING` instead of the planned `current` / `stale` result.
- **Why it matters:** The plan explicitly requires branch / no-ref / pinned git coverage, including pinned refs/tags. This is core stale-classification behavior on a high-regression-risk matrix row, and it will produce wrong startup/manual warnings for any managed package installed from a tag.
- **Proposed fix:** Preserve tag-vs-branch intent in the install-state manifest (for example by recognizing tag refs as pinned or by storing an explicit ref type), update git classification to resolve pinned tags via tag refs rather than `refs/heads/*`, and add fixture/spec coverage for tag-based current/stale cases in both the manifest helper and status-engine specs.
- **Status:** open

#### Major

##### RN-02: The installed `check-updates` helper breaks `--update`, and the test would not catch it
- **Severity:** Major
- **File(s):** `scripts/check-updates.sh:13-16`, `flake.nix:105-111`, `tests/specs/pi-startup-warning-contract-spec.sh:115-126`
- **Problem:** `scripts/check-updates.sh` defaults `NIX_FILE` to `$(dirname "$0")/../nix/modules/pi/default.nix`. The packaged `check-updates` export in `flake.nix` executes `${self}/scripts/check-updates.sh` from the Nix store without overriding `PI_UPDATE_CHECKER_NIX_FILE`, so the installed helper's `--update` path targets an immutable store copy of `default.nix` instead of a writable user declaration file. The new contract spec does not exercise the packaged helper; it only greps the source wiring, so this shipped regression is currently invisible to tests.
- **Why it matters:** The plan says installed repo users get a working `check-updates` helper and that existing `--update` users keep npm-only rewrite behavior. As implemented, the installed command exposes a public flag that cannot work in its packaged form, and the current test strategy would false-green it.
- **Proposed fix:** Either (a) make the packaged helper explicitly inspection-only and fail fast with a clear message on `--update`, or (b) define/inject a writable declaration-path contract for packaged `--update`. In either case, replace the source-grep assertion with a behavioral test that runs the packaged helper (or inspects the built activation package) so export wiring is actually exercised.
- **Status:** open

#### Minor
<none>

### Suggested Backlog Items

<none>

### Documentation Alignment

| Promised update | Present in diff? | Status |
|----------------|-----------------|--------|
| README documents the managed-package startup-warning workflow and out-of-scope direct clones | Yes | ✅ |
| `tests/README.md` and `tests/run-tests.sh` list the new fast-suite coverage | Yes | ✅ |
| Startup notifier / helper copy points users to `check-updates --dry-run` and `home-manager switch --flake .#<hostname>` | Yes | ✅ |

### Requirements Alignment

Use when the repo maintains requirements or the plan cites requirement IDs.

- Cited requirements still satisfied: N/A
- Approved requirement updates applied: Yes
- Undocumented requirement changes: none identified
- Tests/evidence cite requirements where expected: N/A

### Summary
| ID | Severity | File(s) | Status |
|---|---|---|---|
| RN-01 | Critical | `nix/modules/pi/build-managed-package-install-state.mjs`, `nix/modules/pi/check-managed-package-status.mjs`, `tests/specs/managed-package-install-state-spec.sh`, `tests/specs/managed-package-status-spec.sh` | open |
| RN-02 | Major | `scripts/check-updates.sh`, `flake.nix`, `tests/specs/pi-startup-warning-contract-spec.sh` | open |

### Review Status
- New significant issues: 2
- Suggested backlog items: 0
- Total open significant issues: 2
- Status: NEEDS_FIX

---

## Review 2026-05-19 (Review 2)

**Plan:** `plans/startup-extension-staleness-warning/plan.md`
**Diff:** `main..HEAD`
**Mode:** delta

### Coverage Matrix Compliance

| Behavior | Primary test | Negative/edge | Status |
|----------|-------------|---------------|--------|
| Activation persists authoritative install facts for each managed source | ✅ `tests/specs/managed-package-install-state-spec.sh` + `tests/specs/flake-eval-spec.sh` | ⚠️ Shared-source fan-out, deterministic ordering, and git commit/tag capture are covered, but missing materialized-path / missing-metadata failure cases are still not exercised behaviorally | ⚠️ partial |
| Shared checker classifies npm and git sources as `current` / `stale` / `unknown` | ⚠️ `tests/specs/managed-package-status-spec.sh` | ⚠️ npm lookup failure, branch/default drift, timeout/auth/offline, shared-source dedupe, and semver-like tag refs are covered, but pinned-tag policy now diverges from the approved default-branch rule and non-version tag names still fall back to branch semantics | ⚠️ partial |
| Manual `check-updates --dry-run` matches startup semantics and stays informational | ✅ `tests/specs/managed-package-status-spec.sh` | ✅ exit codes, grouped results, npm-only rewrite behavior, and helper error propagation are exercised | ✅ covered |
| `pi` wrapper checks only interactive launches and exports a launch-owned snapshot path | ✅ `tests/specs/pi-startup-wrapper-spec.sh` | ✅ skip paths, env clearing, helper failure, PATH poisoning, and unique snapshots are exercised | ✅ covered |
| Startup notifier renders stale and unknown distinctly, keeps footer/status summary aligned, uses actionable managed-scope copy, and consumes a snapshot once | ✅ `tests/specs/startup-warning-extension-spec.sh` | ✅ expired/malformed/missing/unowned snapshots, replay prevention, and grouped package rendering are exercised | ✅ covered |
| Startup warning copy, helper output, and docs point users to the supported inspection/apply workflow | ✅ `tests/specs/pi-startup-warning-contract-spec.sh` + harness output + `./tests/run-tests.sh all` | ✅ Packaged helper build/run, startup copy, README wording, and runner/docs integration are now exercised behaviorally | ✅ covered |

### Prior Findings Resolution (delta mode only)

| ID | Prior status | Current status | Evidence |
|----|-------------|----------------|----------|
| RN-01 | open | ✅ resolved | Commit `d289d66` adds tag fixtures/assertions in `tests/specs/managed-package-install-state-spec.sh:122-135` and `tests/specs/managed-package-status-spec.sh:161-170`, and semver-like tag refs now persist as `gitRef.kind = "pinned"` instead of degrading immediately to `branch`. |
| RN-02 | open | ✅ resolved | Commit `72c82f9` adds workspace declaration-path resolution and writable-target guarding in `scripts/check-updates.sh:66-113`, and `tests/specs/pi-startup-warning-contract-spec.sh:135-159` now builds and runs the packaged helper in `--update` mode instead of source-grepping wiring. |

### Test Adequacy

- Anti-patterns found: none in the delta. The previous source-grep helper-install check has been replaced with a behavioral packaged-helper test.
- Break-it evidence in worklog:
  - T1: ✅ recorded
  - T2: ✅ recorded
  - T3: ✅ recorded
  - T4: ✅ recorded
  - T5: ✅ recorded
- TODOs without backlog IDs: none
- Reviewer verification:
  - `bash tests/specs/managed-package-install-state-spec.sh`: ✅ pass
  - `bash tests/specs/managed-package-status-spec.sh`: ✅ pass
  - `bash tests/specs/pi-startup-warning-contract-spec.sh`: ✅ pass
  - `./tests/run-tests.sh fast`: ✅ pass
  - `./tests/run-tests.sh all`: ✅ pass

### Implementation Findings

#### Blocker
<none>

#### Critical

##### RN-03: Pinned-tag handling no longer matches the approved stale-policy contract, and tag detection is still incomplete
- **Severity:** Critical
- **File(s):** `nix/modules/pi/build-managed-package-install-state.mjs:101-132`, `nix/modules/pi/check-managed-package-status.mjs:178-195`, `nix/modules/pi/check-managed-package-status.mjs:461-476`, `tests/specs/managed-package-install-state-spec.sh:122-135`, `tests/specs/managed-package-status-spec.sh:161-170`
- **Problem:** The approved approach/plan sets pinned commit **and** pinned tag specs to compare against default-branch `HEAD`, so pinned installs still warn when upstream advances. The new implementation instead special-cases `gitRef.refType == "tag"` to track `refs/tags/<tag>` in `resolveTrackedGitRef()`, and the new status spec asserts that `src-009-git-tag-current` is `current` when the tag still points at the installed commit even though the fixture remote `HEAD` is a different commit. That underreports stale tag-pinned installs relative to the approved policy. Separately, `parseGitRef()` only recognizes semver-shaped tags via `looksLikeTagRef()`, so arbitrary tag names (for example `#stable-release`) still degrade to `branch` and reproduce the original `REF_MISSING` path; I reproduced that with a synthesized manifest against the fake git fixture during review.
- **Why it matters:** This is core domain behavior on the plan's highest-risk coverage row. A managed package pinned to a tag can now be reported `current` after the default branch advances, and non-version tag names still fail to classify as tags at all. Startup/manual warnings therefore remain inaccurate for part of the promised git/tag coverage.
- **Proposed fix:** Restore the approved policy by tracking pinned commits and pinned tags against default-branch `HEAD` (or explicitly update the approved plan/approach if product intent changed), while still preserving manifest metadata that the install spec was tag-pinned. Expand fixtures/specs to cover both default-branch advancement for a tag-pinned install and non-semver tag names so classification no longer depends on a version-shaped tag heuristic.
- **Status:** open

#### Major
<none>

#### Minor
<none>

### Suggested Backlog Items

#### Make packaged-helper contract tests current-system aware
- **Kind:** hardening
- **Origin:** review-finding
- **Suggested priority:** P2
- **Rationale:** `tests/specs/pi-startup-warning-contract-spec.sh:135` hardcodes `packages.x86_64-linux.check-updates`, even though `flake.nix` advertises multiple supported systems. Using the host system dynamically would avoid false failures when the fast suite is run on Darwin or aarch64 hosts.
- **Acceptance:** Build the `check-updates` package for the current Nix system in the contract spec instead of hardcoding `x86_64-linux`, and keep the packaged-helper behavioral assertions unchanged.

### Documentation Alignment

| Promised update | Present in diff? | Status |
|----------------|-----------------|--------|
| README documents the managed-package startup-warning workflow and out-of-scope direct clones | Yes | ✅ |
| `tests/README.md` and `tests/run-tests.sh` list the new fast-suite coverage | Yes | ✅ |
| Startup notifier / helper copy points users to `check-updates --dry-run` and `home-manager switch --flake .#<hostname>` | Yes | ✅ |

### Requirements Alignment

Use when the repo maintains requirements or the plan cites requirement IDs.

- Cited requirements still satisfied: N/A
- Approved requirement updates applied: Yes
- Undocumented requirement changes: pinned-tag stale semantics now diverge from the approved approach/plan contract (tracked as RN-03)
- Tests/evidence cite requirements where expected: N/A

### Summary
| ID | Severity | File(s) | Status |
|---|---|---|---|
| RN-03 | Critical | `nix/modules/pi/build-managed-package-install-state.mjs`, `nix/modules/pi/check-managed-package-status.mjs`, `tests/specs/managed-package-install-state-spec.sh`, `tests/specs/managed-package-status-spec.sh` | open |

### Review Status
- New significant issues: 1
- Suggested backlog items: 1
- Total open significant issues: 1
- Status: NEEDS_FIX

---

## Review 2026-05-19 (Review 3)

**Plan:** `plans/startup-extension-staleness-warning/plan.md`
**Diff:** `main..HEAD`
**Mode:** delta

### Coverage Matrix Compliance

| Behavior | Primary test | Negative/edge | Status |
|----------|-------------|---------------|--------|
| Activation persists authoritative install facts for each managed source | ✅ `tests/specs/managed-package-install-state-spec.sh` + `tests/specs/flake-eval-spec.sh` | ⚠️ Shared-source fan-out, deterministic ordering, and git commit/tag capture are covered, but missing materialized-path / missing-metadata failure cases are still not exercised behaviorally | ⚠️ partial |
| Shared checker classifies npm and git sources as `current` / `stale` / `unknown` | ⚠️ `tests/specs/managed-package-status-spec.sh` | ⚠️ npm lookup failure, branch/default drift, timeout/auth/offline, shared-source dedupe, and pinned-tag default-branch policy are covered, but branch deletion now misclassifies when a same-named tag remains on the remote | ⚠️ partial |
| Manual `check-updates --dry-run` matches startup semantics and stays informational | ✅ `tests/specs/managed-package-status-spec.sh` | ✅ exit codes, grouped results, npm-only rewrite behavior, and helper error propagation are exercised | ✅ covered |
| `pi` wrapper checks only interactive launches and exports a launch-owned snapshot path | ✅ `tests/specs/pi-startup-wrapper-spec.sh` | ✅ skip paths, env clearing, helper failure, PATH poisoning, and unique snapshots are exercised | ✅ covered |
| Startup notifier renders stale and unknown distinctly, keeps footer/status summary aligned, uses actionable managed-scope copy, and consumes a snapshot once | ✅ `tests/specs/startup-warning-extension-spec.sh` | ✅ expired/malformed/missing/unowned snapshots, replay prevention, and grouped package rendering are exercised | ✅ covered |
| Startup warning copy, helper output, and docs point users to the supported inspection/apply workflow | ✅ `tests/specs/pi-startup-warning-contract-spec.sh` + harness output + `./tests/run-tests.sh all` | ✅ Packaged helper build/run, startup copy, README wording, and runner/docs integration are exercised behaviorally | ✅ covered |

### Prior Findings Resolution (delta mode only)

| ID | Prior status | Current status | Evidence |
|----|-------------|----------------|----------|
| RN-03 | open | ✅ resolved | Commit `6aa4a21` updates `nix/modules/pi/build-managed-package-install-state.mjs:117-152,192-216` to honor persisted `requestedRefType` metadata, and `nix/modules/pi/check-managed-package-status.mjs:478-515` now tracks pinned tags against default-branch `HEAD` while the refreshed install-state/status specs cover both versioned and non-version tag pins. |

### Test Adequacy

- Anti-patterns found: none in the delta.
- Break-it evidence in worklog:
  - T1: ✅ recorded
  - T2: ✅ recorded
  - T3: ✅ recorded
  - T4: ✅ recorded
  - T5: ✅ recorded
- TODOs without backlog IDs: none
- Reviewer verification:
  - `bash tests/specs/managed-package-install-state-spec.sh`: ✅ pass
  - `bash tests/specs/managed-package-status-spec.sh`: ✅ pass
  - `bash tests/specs/pi-startup-warning-contract-spec.sh`: ✅ pass
  - `./tests/run-tests.sh fast`: ✅ pass
  - `./tests/run-tests.sh all`: ✅ pass

### Implementation Findings

#### Blocker
<none>

#### Critical

##### RN-04: Missing branch refs are now misreported when a same-named tag still exists
- **Severity:** Critical
- **File(s):** `nix/modules/pi/check-managed-package-status.mjs:478-515`, `tests/spec-fixtures/managed-package-status/manifest.ok.json:217-231`, `tests/spec-fixtures/managed-package-status/fake-git:79-85`, `tests/specs/managed-package-status-spec.sh:161-198`
- **Problem:** The new branch handling in `resolveTrackedGitRef()` falls back to `resolveDefaultTrackedGitRef()` whenever a branch ref is missing but a tag with the same name exists. That means a manifest entry that explicitly says `gitRef.kind == "branch"` no longer honors the plan's `missing/deleted ref → unknown` rule. The current fixture demonstrates the regression directly: `src-014-git-tag-nonversion-stale` declares `gitRef.kind = "branch"` / `value = "stable"`, the fake remote advertises only `refs/tags/stable` plus default-branch `HEAD`, and the checker now reports the source as `stale` against `refs/heads/main` instead of `unknown` / `REF_MISSING`.
- **Why it matters:** This is core stale-classification behavior on the highest-risk matrix row. Real branch installs can legitimately end up in this state if a branch is deleted or renamed while a same-named release tag remains. Startup/manual warnings would underreport a broken branch-tracking configuration as an ordinary stale result, and the new status spec now codifies that incorrect behavior.
- **Proposed fix:** Remove the branch→tag fallback so branch specs always return `REF_MISSING` when `refs/heads/<branch>` is absent. Keep non-version tag coverage by representing those installs as pinned tags in the manifest/status fixtures (which the install-state helper now supports), and add a dedicated regression case asserting that a deleted branch with a same-named tag remains `unknown`.
- **Status:** open

#### Major
<none>

#### Minor
<none>

### Suggested Backlog Items

#### Make packaged-helper contract tests current-system aware
- **Kind:** hardening
- **Origin:** review-finding
- **Suggested priority:** P2
- **Rationale:** `tests/specs/pi-startup-warning-contract-spec.sh:115` still hardcodes `packages.x86_64-linux.check-updates`, even though `flake.nix` advertises multiple supported systems. Using the host system dynamically would avoid false failures when the fast suite is run on Darwin or aarch64 hosts.
- **Acceptance:** Build the `check-updates` package for the current Nix system in the contract spec instead of hardcoding `x86_64-linux`, and keep the packaged-helper behavioral assertions unchanged.

### Documentation Alignment

| Promised update | Present in diff? | Status |
|----------------|-----------------|--------|
| README documents the managed-package startup-warning workflow and out-of-scope direct clones | Yes | ✅ |
| `tests/README.md` and `tests/run-tests.sh` list the new fast-suite coverage | Yes | ✅ |
| Startup notifier / helper copy points users to `check-updates --dry-run` and `home-manager switch --flake .#<hostname>` | Yes | ✅ |

### Requirements Alignment

Use when the repo maintains requirements or the plan cites requirement IDs.

- Cited requirements still satisfied: N/A
- Approved requirement updates applied: Yes
- Undocumented requirement changes: branch-missing handling now diverges from the approved `missing/deleted ref → unknown` contract (tracked as RN-04)
- Tests/evidence cite requirements where expected: N/A

### Summary
| ID | Severity | File(s) | Status |
|---|---|---|---|
| RN-04 | Critical | `nix/modules/pi/check-managed-package-status.mjs`, `tests/spec-fixtures/managed-package-status/manifest.ok.json`, `tests/spec-fixtures/managed-package-status/fake-git`, `tests/specs/managed-package-status-spec.sh` | open |

### Review Status
- New significant issues: 1
- Suggested backlog items: 1
- Total open significant issues: 1
- Status: NEEDS_FIX
