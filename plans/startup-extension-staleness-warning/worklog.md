# Startup Extension Staleness Warning — Execution Worklog

## Entry-Point Contract

- **Read this file first** every time you start working on this plan.
- Execute exactly ONE task per sub-agent call. Do not execute multiple tasks.
- Do not add new tasks to the current plan/worklog task list unless the human explicitly changes scope.
- After completing a task: update this file, commit, and stop.
- **Do not start T1 implementation until the Baseline Gate Audit table below has been filled in.** The plan requires baseline gate recording before implementation begins.

## Working Rules

- Strict TDD (Red → Green → Break-it → Verify). No change without a failing test first.
- Git commits are per plan task. Do NOT push until explicitly requested.
- Follow the plan's TDD checklists exactly — do not skip the break-it check.
- Non-blocking follow-up work does **not** go into this plan's task list.
- For this run, there is **no documented repo backlog mechanism** and **no documented repo requirements mechanism**. Follow the explicit policies below instead of inventing one.

## References

- Plan: `./plan.md`
- Approach: `./approach.md`

## Completion Criteria

All of these must be true before the plan is considered complete:
- [ ] All tasks marked done below
- [ ] All new targeted specs pass
- [ ] `./tests/run-tests.sh fast` passes
- [ ] `bash tests/specs/flake-eval-spec.sh` passes after the final packaging changes
- [ ] `./tests/run-tests.sh all` passes, or unchanged unrelated baseline failures are documented under the gate policy
- [ ] All coverage-matrix rows have tests or explicit harness coverage
- [ ] Startup warning copy, README guidance, and `check-updates` behavior all point to the same inspection/apply workflow
- [ ] Final task commit made

## Prerequisites

### Environment Setup
- **Required services:** None documented.
- **Service start/stop commands:** None documented.
- **Required env vars (names only):**
  - `PI_OFFLINE` — used by the optional CLI smoke path in `./tests/run-tests.sh full`
  - `PI_MANAGED_PACKAGE_STARTUP_STATUS_PATH` — feature/runtime handoff env var owned by the wrapper; do not set manually unless a task-specific test harness requires it
- **Runtime / tool prerequisites (documented):**
  - `bash`, `jq`, `node` for `./tests/run-tests.sh fast`
  - `nix`, `pi` installed, `home-manager switch` run at least once for `./tests/run-tests.sh all`
  - functional `pi` CLI for `./tests/run-tests.sh full`
- **Runtime versions:**
  - Nixpkgs input: `nixos-25.05` (from `flake.nix`)
  - Home Manager input: `release-25.05` (from `flake.nix`)
  - Node version: not pinned in repo docs beyond using the flake/dev-shell `nodejs` package
- **Setup command:** No single repo setup command is documented. Use the documented test prerequisites above.

## Baseline Gate Audit

Run all package-wide and repo-wide gates before T1 implementation.

| Command | Scope | Baseline status | Related failures? | Notes |
|---------|-------|-----------------|-------------------|-------|
| `./tests/run-tests.sh fast` | package-wide | ✅ pass (2026-05-19 baseline) | no | Green before T1 changes |
| `./tests/run-tests.sh all` | repo-wide | ✅ pass (2026-05-19 baseline) | no | Green before T1 changes; Pi proof-set printed the existing entrypoint warning but exited 0 |
| `./tests/run-tests.sh full` | repo-wide | ❌ fail (2026-05-19 baseline) | no | Pre-existing optional smoke failure: `pi --help` output unexpected before T1 changes |

- [x] All baseline gates checked before implementation began
- [x] Pre-existing failures documented above

## Testing & Verification

### Commands
| Command | Scope | When to run | What it checks |
|---------|-------|-------------|----------------|
| `bash tests/specs/managed-package-install-state-spec.sh` | touched-files | During TDD loops for T1 | The install-state manifest schema and persisted install facts are correct and deterministic |
| `bash tests/specs/managed-package-status-spec.sh` | touched-files | During TDD loops for T2 | npm/git stale classification, grouped-source fan-out, startup-mode default budgets, and manual-mode exit semantics match the contract |
| `bash tests/specs/pi-startup-wrapper-spec.sh` | touched-files | During TDD loops for T3 | Wrapper argv whitelist, absolute-path runtime/helper handoff, env handoff, snapshot lifecycle, and fail-open no-snapshot startup behavior are correct |
| `bash tests/specs/startup-warning-extension-spec.sh` | touched-files | During TDD loops for T4 | The notifier renders stale/unknown distinctly, keeps footer/status summary in sync, and ignores, expires, or consumes snapshots correctly |
| `bash tests/specs/pi-startup-warning-contract-spec.sh` | touched-files | During TDD loops for T5 | Helper availability, user guidance, managed-scope wording, and runner docs stay aligned |
| `bash tests/specs/flake-eval-spec.sh` | package-wide | Before task completion for tasks touching Nix/module packaging | The Home Manager module still instantiates/builds with the new helper, wrapper, and extension wiring |
| `./tests/run-tests.sh fast` | package-wide | Before each task completion | The repo-local shell-spec suite remains green after each task |
| `./tests/run-tests.sh all` | repo-wide | Before plan completion | Flake evaluation + proof-set verification still work after the full feature wiring lands |
| `./tests/run-tests.sh full` | repo-wide | Optional post-plan smoke | The live CLI help/list smoke still behaves in an environment with a functional Pi CLI |

### Gate Policy
- **Policy:** `allow-scoped-completion`
- **If a broader gate fails for unrelated reasons:**
  1. Compare against the baseline audit above.
  2. If the failure was already present before this plan's implementation, document it in `Unrelated Gate Failures Log`.
  3. Completion still requires all of the following:
     - all new targeted specs pass
     - `./tests/run-tests.sh fast` stays green
     - `bash tests/specs/flake-eval-spec.sh` passes after packaging changes
     - `./tests/run-tests.sh all` shows no **new** failures attributable to this plan
  4. If the failing broader gate is related to the current task or makes attribution unclear, stop and resolve before marking the task/plan complete.

### Why the Gate Commands Matter
The fast feedback commands prove the touched behavior under development, but they do **not** prove that repo wiring, package registration, test-runner integration, or Nix/Home Manager packaging still work together.

The package-wide and repo-wide gates catch issues that task-level fast-feedback misses:
- regressions in untouched repo-local specs
- missing spec-runner wiring or docs/test-runner drift
- Home Manager / flake evaluation failures after helper, wrapper, or extension wiring changes
- missing installed assets, broken module exports, or contract drift across scripts, Nix modules, and tests
- repo-wide proof-set or CLI-surface regressions that only appear outside the touched fixture/spec

Always run the documented gate command(s) before marking a task complete, even if the touched-file spec passes.

### Unrelated Gate Failures Log
| Date | Command | Failure | Related to current task? | Action |
|------|---------|---------|--------------------------|--------|
| 2026-05-19 | `./tests/run-tests.sh full` | `pi --help` output unexpected during optional CLI smoke baseline | no | Recorded as pre-existing baseline failure; not blocking T1 under `allow-scoped-completion` |

- If a task-specific test fails: fix before marking the task complete.

## Backlog Capture Policy

- **Repo backlog:** No repo task-tracking/backlog mechanism is documented for this repository.
- **Create item procedure:** None documented. Do **not** invent a backlog store or ID system during this run.
- **Stable ID/reference format:** None documented.
- **Default non-critical follow-up status:** N/A.
- **Default origin for execution follow-ups:** N/A.
- **Critical/current-plan-affecting discoveries:** stop and ask whether to fix now, re-plan, or capture externally.
- **This run:** proceed without backlog capture. If a non-critical follow-up is discovered, mention it in the execution notes only after informing the user/orchestrator; do not create a repo backlog item.

## Backlog Items Created

None — backlog capture is not documented for this repo and is not being used in this run.

## Requirement Changes

The plan includes approved requirement-oriented changes, but **no canonical repo requirements mechanism is documented**.

- **Repo requirements:** None documented.
- **Approved requirement updates from plan:**
  - Apply the approved approach scope clarification that v1 stale-warning coverage is limited to managed `piPackages` install types.
  - Apply the approved manual-workflow contract that startup warnings point to `check-updates --dry-run` for inspection and `home-manager switch --flake ...` for applying changes.
- **Applied requirement updates:**
  - T2: `check-updates` now treats `--dry-run`/default as the supported inspection path, directs users to `home-manager switch --flake ...` for applying changes, and keeps `--update` explicitly npm-only.
  - T4: startup notifier copy now explicitly says the warning covers managed packages/plugins and points users to `check-updates --dry-run` for inspection plus `home-manager switch --flake ...` for applying changes.
- **Requirement-change approval source:** `./plan.md` → `Requirement Updates`
- **Requirement IDs/reference format:** None documented.
- **Test requirement citation format:** None documented.

Execution rules for requirement-related work in this plan:
- Apply only the approved wording/behavior changes already authorized by `plan.md`.
- Do **not** invent requirement IDs or edit a non-existent canonical requirements store.
- If execution reveals a missing, unclear, or conflicting requirement that affects correctness, scope, safety, user guidance, or verification, stop and ask before changing behavior or docs beyond what the plan already approved.

## Task Queue (copied from plan)

| ID | Task | Depends on | Deliverable | Verification | Status |
|---:|------|------------|-------------|--------------|--------|
| T1 | Add the managed-package install-state manifest contract | — | Activation writes `managed-packages.install-state.json` via a tested helper, with deterministic schema, source identity/install fields, and shared-source fan-out | `bash tests/specs/managed-package-install-state-spec.sh`, `bash tests/specs/flake-eval-spec.sh`, `./tests/run-tests.sh fast` | ✅ |
| T2 | Build the shared status engine and align `check-updates` with it | T1 | One machine-readable checker plus a working `check-updates --dry-run` frontend using the correct declaration path, fixed startup defaults, stable unknown-reason/warning taxonomy, and explicit manual exit semantics | `bash tests/specs/managed-package-status-spec.sh`, `./tests/run-tests.sh fast` | ✅ |
| T3 | Add the repo-owned `pi` launch wrapper and startup snapshot lifecycle | T2 | Wrapper-produced per-launch snapshot files with launch metadata, injected real-binary/helper paths, interactive/noninteractive argv handling, env handoff, and non-blocking no-snapshot fail-open behavior | `bash tests/specs/pi-startup-wrapper-spec.sh`, `bash tests/specs/flake-eval-spec.sh`, `./tests/run-tests.sh fast` | ✅ |
| T4 | Add the Pi startup notifier extension | T3 | Directly installed notifier extension that renders stale vs unknown results, keeps footer/status summary in sync while startup problems exist, uses actionable managed-scope copy, and consumes only the current launch snapshot | `bash tests/specs/startup-warning-extension-spec.sh`, `bash tests/specs/flake-eval-spec.sh`, `./tests/run-tests.sh fast` | ✅ |
| T5 | Wire user-facing workflow docs, helper availability, and final contract coverage | T2, T3, T4 | Installed `check-updates` helper, aligned startup/helper/README wording, managed-scope contract coverage, and fast-suite coverage for the new repo contract | `bash tests/specs/pi-startup-warning-contract-spec.sh`, `./tests/run-tests.sh fast`, `./tests/run-tests.sh all` | ⬜ |

## Task Status

- [x] T1: Add the managed-package install-state manifest contract
- [x] T2: Build the shared status engine and align `check-updates` with it
- [x] T3: Add the repo-owned `pi` launch wrapper and startup snapshot lifecycle
- [x] T4: Add the Pi startup notifier extension
- [ ] T5: Wire user-facing workflow docs, helper availability, and final contract coverage

## Decisions / Constraints Discovered (append-only)

- None yet. Use `./plan.md` as the source of truth for current constraints and decisions until execution adds entries here.

## NEXT STEP

T5 — Wire user-facing workflow docs, helper availability, and final contract coverage.

Read `plan.md` § `T5: Wire user-facing workflow docs, helper availability, and final contract coverage` for the full deliverable, task notes, TDD checklist, break-it requirement, and verification scope.

After completing T5:
1. Update the task evidence in this file.
2. Mark T5 done above and update the Task Queue status.
3. Update Completion Criteria / NEXT STEP for plan completion.
4. Append to the execution log below.
5. Commit: `task(T5): wire startup warning docs and final contract coverage`

## Execution Log

- 2026-05-19 — T1 completed.
  - Baseline audit recorded before implementation: `./tests/run-tests.sh fast` ✅, `./tests/run-tests.sh all` ✅, `./tests/run-tests.sh full` ❌ (`pi --help` smoke failure; pre-existing and unrelated to T1).
  - Red: added `tests/specs/managed-package-install-state-spec.sh`, fixtures under `tests/spec-fixtures/managed-package-install-state/`, and fast-suite/docs wiring; confirmed initial failure because `nix/modules/pi/build-managed-package-install-state.mjs` did not exist.
  - Green: implemented `nix/modules/pi/build-managed-package-install-state.mjs`; updated `nix/modules/pi/default.nix` to preserve richer managed-package declarations, persist git install metadata, and write `~/.pi/agent/managed-packages.install-state.json` during activation.
  - Break-it: temporarily removed persisted `installedCommit` from git source output, re-ran `bash tests/specs/managed-package-install-state-spec.sh`, confirmed failure, then restored the field.
  - Verification: `bash tests/specs/managed-package-install-state-spec.sh` ✅, `bash tests/specs/flake-eval-spec.sh` ✅, `./tests/run-tests.sh fast` ✅.
  - Backlog items created: none (repo backlog mechanism not documented).
  - Requirement changes applied: none in T1.
- 2026-05-19 — T2 completed.
  - Red: added `tests/specs/managed-package-status-spec.sh`, fixtures under `tests/spec-fixtures/managed-package-status/`, and fast-suite/docs wiring; confirmed initial failure because `nix/modules/pi/check-managed-package-status.mjs` did not exist.
  - Green: implemented `nix/modules/pi/check-managed-package-status.mjs` with shared npm/git stale classification, fixed startup defaults, timeout/unknown taxonomy, JSON/text output, and grouped-source handling; updated `scripts/check-updates.sh` to use the shared checker for inspection while keeping `--update` npm-only.
  - Break-it: temporarily changed pinned git sources to compare against the installed commit instead of the chosen upstream ref, re-ran `bash tests/specs/managed-package-status-spec.sh`, confirmed failure, then restored the default-branch comparison rule.
  - Verification: `bash tests/specs/managed-package-status-spec.sh` ✅, `./tests/run-tests.sh fast` ✅.
  - Backlog items created: none (repo backlog mechanism not documented).
  - Requirement changes applied: manual inspection/apply workflow now points to `check-updates --dry-run` for inspection and `home-manager switch --flake ...` as the apply step; `--update` remains npm-only.
- 2026-05-19 — T3 completed.
  - Red: added `tests/specs/pi-startup-wrapper-spec.sh`, fixtures under `tests/spec-fixtures/pi-startup-wrapper/`, and fast-suite/docs wiring; confirmed initial failure because `scripts/pi-launch-wrapper.sh` did not exist.
  - Green: implemented `scripts/pi-launch-wrapper.sh`; added flake packaging for a repo-owned `pi` wrapper that injects absolute real-Pi/node/helper paths; and updated `nix/modules/pi/default.nix` to install the wrapper ahead of the upstream Pi package.
  - Break-it: temporarily stopped clearing `PI_MANAGED_PACKAGE_STARTUP_STATUS_PATH` on argv-bearing launches, re-ran `bash tests/specs/pi-startup-wrapper-spec.sh`, confirmed failure, then restored the skip-path env clearing.
  - Verification: `bash tests/specs/pi-startup-wrapper-spec.sh` ✅, `bash tests/specs/flake-eval-spec.sh` ✅, `./tests/run-tests.sh fast` ✅.
  - Backlog items created: none (repo backlog mechanism not documented).
  - Requirement changes applied: none in T3.
- 2026-05-19 — T4 completed.
  - Red: added `tests/specs/startup-warning-extension-spec.sh`, harness `tests/scripts/run-startup-warning-extension.mjs`, fixtures under `tests/spec-fixtures/startup-warning-extension/`, and fast-suite/docs wiring; confirmed initial failure because `nix/modules/pi/extensions/startup-staleness-warning/index.ts` did not exist.
  - Green: implemented `nix/modules/pi/extensions/startup-staleness-warning/index.ts`; updated `nix/modules/pi/default.nix` to install the repo-owned notifier directly under `~/.pi/agent/extensions/`; and added deterministic notifier coverage for stale/unknown rendering, status summary behavior, freshness checks, owned-path validation, and consume-once handling.
  - Break-it: temporarily collapsed the unknown section into the stale section, re-ran `bash tests/specs/startup-warning-extension-spec.sh`, confirmed failure, then restored the distinct stale-vs-unknown rendering.
  - Verification: `bash tests/specs/startup-warning-extension-spec.sh` ✅, `bash tests/specs/flake-eval-spec.sh` ✅, `./tests/run-tests.sh fast` ✅.
  - Backlog items created: none (repo backlog mechanism not documented).
  - Requirement changes applied: startup notifier copy now explicitly says managed packages/plugins and points users to `check-updates --dry-run` for inspection plus `home-manager switch --flake ...` for applying changes.
