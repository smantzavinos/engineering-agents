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
| `./tests/run-tests.sh fast` | package-wide | ⏳ not yet recorded | TBD | Required pre-T1 baseline for the deterministic repo-local suite |
| `./tests/run-tests.sh all` | repo-wide | ⏳ not yet recorded | TBD | Required pre-T1 baseline for flake eval + proof-set verification |
| `./tests/run-tests.sh full` | repo-wide | ⏳ not yet recorded | TBD | Optional smoke; record when the executor's environment has a functional Pi CLI |

- [ ] All baseline gates checked before implementation began
- [ ] Pre-existing failures documented above

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
| _none yet_ |  |  |  |  |

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
- **Applied requirement updates:** None yet.
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
| T1 | Add the managed-package install-state manifest contract | — | Activation writes `managed-packages.install-state.json` via a tested helper, with deterministic schema, source identity/install fields, and shared-source fan-out | `bash tests/specs/managed-package-install-state-spec.sh`, `bash tests/specs/flake-eval-spec.sh`, `./tests/run-tests.sh fast` | ⬜ |
| T2 | Build the shared status engine and align `check-updates` with it | T1 | One machine-readable checker plus a working `check-updates --dry-run` frontend using the correct declaration path, fixed startup defaults, stable unknown-reason/warning taxonomy, and explicit manual exit semantics | `bash tests/specs/managed-package-status-spec.sh`, `./tests/run-tests.sh fast` | ⬜ |
| T3 | Add the repo-owned `pi` launch wrapper and startup snapshot lifecycle | T2 | Wrapper-produced per-launch snapshot files with launch metadata, injected real-binary/helper paths, interactive/noninteractive argv handling, env handoff, and non-blocking no-snapshot fail-open behavior | `bash tests/specs/pi-startup-wrapper-spec.sh`, `bash tests/specs/flake-eval-spec.sh`, `./tests/run-tests.sh fast` | ⬜ |
| T4 | Add the Pi startup notifier extension | T3 | Directly installed notifier extension that renders stale vs unknown results, keeps footer/status summary in sync while startup problems exist, uses actionable managed-scope copy, and consumes only the current launch snapshot | `bash tests/specs/startup-warning-extension-spec.sh`, `bash tests/specs/flake-eval-spec.sh`, `./tests/run-tests.sh fast` | ⬜ |
| T5 | Wire user-facing workflow docs, helper availability, and final contract coverage | T2, T3, T4 | Installed `check-updates` helper, aligned startup/helper/README wording, managed-scope contract coverage, and fast-suite coverage for the new repo contract | `bash tests/specs/pi-startup-warning-contract-spec.sh`, `./tests/run-tests.sh fast`, `./tests/run-tests.sh all` | ⬜ |

## Task Status

- [ ] T1: Add the managed-package install-state manifest contract
- [ ] T2: Build the shared status engine and align `check-updates` with it
- [ ] T3: Add the repo-owned `pi` launch wrapper and startup snapshot lifecycle
- [ ] T4: Add the Pi startup notifier extension
- [ ] T5: Wire user-facing workflow docs, helper availability, and final contract coverage

## Decisions / Constraints Discovered (append-only)

- None yet. Use `./plan.md` as the source of truth for current constraints and decisions until execution adds entries here.

## NEXT STEP

**Preflight required:** Run and record the Baseline Gate Audit commands above before implementation.

**Current Task after baseline:** T1 — Add the managed-package install-state manifest contract

Read `plan.md` § `T1: Add the managed-package install-state manifest contract` for the full deliverable, task notes, TDD checklist, break-it requirement, and verification scope.

After completing T1:
1. Update the baseline/task evidence in this file.
2. Mark T1 done above and update the Task Queue status.
3. Set NEXT STEP to T2.
4. Append to the execution log below.
5. Commit: `task(T1): add the managed-package install-state manifest contract`

## Execution Log

_No execution yet._
