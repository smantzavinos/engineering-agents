# Code Review Log

## Open Issues (roll-up — update each pass)

| ID | Severity | Issue | File(s) | Status |
|---|---|---|---|---|
| RN-01 | Critical | Tag-pinned git specs are misclassified as branches, so tag-based managed packages will report `unknown`/`REF_MISSING` instead of `current`/`stale` | `nix/modules/pi/build-managed-package-install-state.mjs`, `nix/modules/pi/check-managed-package-status.mjs`, `tests/specs/managed-package-install-state-spec.sh`, `tests/specs/managed-package-status-spec.sh` | open |
| RN-02 | Major | The installed `check-updates` wrapper does not preserve `--update` behavior, and the contract test only source-greps the wiring instead of exercising the packaged helper | `flake.nix`, `scripts/check-updates.sh`, `tests/specs/pi-startup-warning-contract-spec.sh` | open |

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
