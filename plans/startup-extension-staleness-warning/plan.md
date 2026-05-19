# Plan: Startup Extension Staleness Warning

**Status:** draft
**Owner:** pi planning agent
**Created:** 2026-05-19
**Related:** `./brief.md`, `./approach.md`, `./approach_review.md`, `./findings/startup-flow.md`, `./findings/plugin-metadata-model.md`, `./findings/git-staleness.md`, `./findings/update-check-current-state.md`, `./findings/testing-strategy.md`, `./findings/warning-ux.md`

---

## Execution Contract
This plan is meant to be **executed** with strict TDD (Red → Green → Break-it → Verify).

No implementation change without a failing test (or an explicitly documented exception).

---

## Change Summary
- **What changes:** The repo gains a repo-owned `pi` launch wrapper, an activation-time managed-package install-state manifest, a shared machine-readable status engine reused by startup and manual update checks, a startup notifier extension that renders stale vs unknown results inside Pi, a corrected/installable `check-updates` helper, and deterministic test coverage for npm/git stale detection plus startup warning delivery.
- **What stays the same:** Pi core is unchanged, managed facade package compilation under `~/.pi/agent/packages` remains the package-loading model, startup stays non-blocking, direct cloned/symlinked resources outside managed `piPackages` remain out of scope, and update/install orchestration is still handled by the existing Home Manager apply flow rather than by this feature.
- **Motivation:** Restore the stale-plugin visibility users lost when this repo started wrapping Pi extensions through generated facades, while keeping warnings accurate for npm and git sources and never blocking normal Pi startup.

## Goals
- [ ] Show a visible in-Pi startup warning when one or more managed `piPackages` sources are confirmed stale.
- [ ] Distinguish confirmed stale sources from `unknown`/undetermined sources without blocking startup.
- [ ] Cover the managed npm and git install types used by this repo, including branch/no-ref/pinned git specs.
- [ ] Make `check-updates --dry-run` the working, supported inspection path backed by the same status logic as startup warnings.
- [ ] Add deterministic tests for manifest generation, stale-status classification, wrapper launch behavior, and notifier rendering.

## Non-goals
- Changing Pi core or upstream package metadata.
- Auto-updating packages or redesigning the broader update workflow.
- Extending stale detection to direct cloned/symlinked installs such as `agent-kit` or `visual-explainer`.
- Adding caching/throttling/history beyond the single-launch snapshot needed for startup notification.
- Performing unrelated cleanup of the wrapper/compiler architecture.

## Related Backlog Items

Items outside this plan's executable scope but relevant for context:
- none in repo backlog today; capture follow-ups during execution for:
  - direct-cloned/symlinked resource staleness coverage
  - warning throttling / bounded cache for repeated launches
  - broader update workflow redesign beyond `check-updates --dry-run` + `home-manager switch`

## Related Requirements

This repo does not currently maintain canonical repo-local requirement IDs for this feature area.

- Actors/personas: N/A
- Use cases: N/A
- Workflows/scenarios: N/A
- Requirement refs: N/A

## Requirement Updates

Approved requirement changes to apply during execution:

| Requirement change | Applied in task | Notes |
|--------------------|-----------------|-------|
| Apply the approved approach scope clarification that v1 stale-warning coverage is limited to managed `piPackages` install types | T5 | User-facing docs and warning text must explicitly say managed packages/plugins so direct cloned installs are not implied as covered |
| Apply the approved manual-workflow contract that startup warnings point to `check-updates --dry-run` for inspection and `home-manager switch --flake ...` for applying changes | T2, T5 | Do not imply that `--update` or startup itself performs git updates |

## Impacted Surface Area
- **Entry points affected:** `pi` CLI startup path, `check-updates` CLI, Home Manager activation, Pi `session_start` extension hook, JSON state under `~/.pi/agent/`
- **Modules/components likely touched:** `flake.nix`, `nix/modules/pi/default.nix`, new helpers under `nix/modules/pi/`, `scripts/check-updates.sh`, new wrapper script under `scripts/`, new startup extension under `nix/modules/pi/extensions/`, `README.md`, `tests/README.md`, `tests/run-tests.sh`, new shell specs and fixtures
- **External contracts affected:** PATH-provided `pi` and `check-updates`, `~/.pi/agent/managed-packages.install-state.json`, `~/.pi/agent/startup-status/<launch-id>.json`, startup env var `PI_MANAGED_PACKAGE_STARTUP_STATUS_PATH`, machine-readable status JSON emitted by the shared checker

## Context
Today this repo installs the upstream `pi` binary directly, generates facade packages under `~/.pi/agent/packages`, and preserves original source provenance only in `meta/source.json`. The current manual checker (`scripts/check-updates.sh`) parses `piPackages` declarations, compares npm versions against the registry, and warns-only for git/local sources; it also defaults to a non-existent declaration path and is not installed for repo users. The design approved in `approach.md` resolves that by adding one repo-owned status engine, a wrapper-triggered per-launch snapshot, and a notifier extension that reads only the current launch snapshot.

The findings establish the key implementation constraints this plan must preserve:
- authoritative stale detection cannot come from facade `package.json` because every facade version is `0.0.0-generated`
- git install roots are npm materializations, not local git repositories
- shared sources such as `pi-ext-leader-key` and `pi-ext-review` must be deduped per source, then fanned back out to package IDs
- the fast shell-spec layer is the canonical deterministic place to exercise stale/current/unknown behavior
- live `all`/`full` tiers are useful packaging/smoke layers but depend on the executor's Nix/Pi/Home Manager environment

## Constraints
- Implement everything in this repo/wrapper; no Pi core changes.
- Startup must never be blocked by stale checks or by failures while determining status.
- Git installs count as stale when the chosen upstream ref has advanced, even for pinned refs/tags.
- Startup warnings and manual inspection must share one classification engine.
- Use repo-documented verification commands only: `bash tests/specs/*.sh`, `./tests/run-tests.sh fast`, `./tests/run-tests.sh all`, `./tests/run-tests.sh full`.
- Keep noninteractive/script-facing Pi invocations free of warning noise.
- Scope stays within managed `piPackages`; direct cloned installs remain out of scope.

## Assumptions
- Adding small standalone Node/shell helpers under `nix/modules/pi/` and `scripts/` is acceptable if it keeps the activation/wrapper logic testable.
- The startup notifier can be tested deterministically via a harness that simulates Pi's `session_start` context rather than requiring a live interactive TUI.
- A schema-versioned JSON contract is warranted because multiple local consumers will read the install-state and startup-status artifacts.
- Timeout/concurrency defaults may be tuned during implementation, but the contract and tests should make those values injectable so behavior remains deterministic.

## Open Questions

- Which argv patterns beyond plain `pi` are officially treated as documented interactive launches for v1, and which invocation forms must explicitly fail open to skip warnings?
- What default per-source timeout, overall timeout, concurrency cap, and snapshot freshness/expiry window ship in v1 for startup mode?

If execution uncovers an undocumented Pi extension hook limitation that would change where startup warnings are rendered, stop and revisit the approved approach rather than silently changing surfaces.

## Risks & Mitigations

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Install-state metadata omits a field the status engine needs later | high | medium | Lock the manifest schema first with a dedicated fixture spec before wiring the status engine |
| Git stale logic drifts from the approved branch/no-ref/pinned semantics | high | medium | Encode each git spec class as a separate failing fixture case in the status-engine spec |
| Wrapper logic pollutes `pi --help`/`pi list` output or leaks stale env vars across launches | high | medium | Add a dedicated wrapper spec for interactive-vs-noninteractive argv handling and env clearing before packaging the wrapper |
| Startup notifier replays old launch snapshots or cross-talks between concurrent launches | high | medium | Use wrapper-passed per-launch snapshot paths, freshness checks, and consume-once semantics under test |
| User guidance remains contradictory after the feature lands | medium | medium | Make README + helper output + notifier copy all point to the same inspection/apply workflow in the final task |
| Live repo-wide gates fail for unrelated local-environment reasons | medium | medium | Record baseline before T1, use deterministic fast specs as the primary execution gate, and apply the documented unrelated-failure policy below |

## Decisions

| Decision | Options Considered | Chosen | Rationale | Consequences | Revisit If |
|----------|-------------------|--------|-----------|--------------|------------|
| Install-state artifact name | extend `managed-packages.declarations.json`, add new file, embed in compile report | add `~/.pi/agent/managed-packages.install-state.json` | Keeps install facts distinct from compile inputs/output warnings and gives the status engine a stable source of truth | One additional generated artifact to maintain and test | The compiler/report contract later grows a first-class place for installed version/ref facts |
| Shared status engine location | keep all logic in `scripts/check-updates.sh`, new helper under `scripts/`, new helper under `nix/modules/pi/` | new helper `nix/modules/pi/check-managed-package-status.mjs` with thin frontends | Matches the existing compiled-helper pattern and keeps machine-readable logic near other Pi packaging helpers | `check-updates.sh` becomes a frontend instead of the only implementation | The repo later standardizes all helper CLIs under a different directory |
| Startup snapshot contract | shared latest file, timestamp-only latest file, wrapper-passed exact path | wrapper-passed exact path via `PI_MANAGED_PACKAGE_STARTUP_STATUS_PATH` | Prevents cross-launch replay/clobbering and makes notifier ownership explicit | Wrapper and notifier must both honor the same env/file lifecycle | Pi later exposes a safer first-class startup metadata channel |
| Final gate for this plan | `fast`, `all`, `full` | `./tests/run-tests.sh all` with `full` as optional post-plan smoke | `all` is the canonical repo-wide gate in repo docs; `full` only adds help/list smoke and depends on a live Pi CLI environment | Wrapper/help-list cleanliness must be proven by deterministic shell specs, not only by optional live smoke | Repo docs later elevate `full` to the mandatory final gate |
| User-visible covered scope wording | “plugins”, “managed packages”, “all repo installs” | “managed Pi packages/plugins” | Reflects the approved scope clarification and avoids overpromising coverage of direct cloned installs | Docs and startup copy must stay explicit about the boundary | Direct cloned installs are brought into the managed model |

## Tooling / Contract Surface

This plan introduces repo-owned CLI/runtime contracts, so the affected files and warning/status payloads must be treated as versioned interfaces.

### Versioned I/O contract
- `~/.pi/agent/managed-packages.install-state.json` must be a new `schemaVersion: 1` artifact written during activation.
  - Top-level shape: `{ schemaVersion, generatedAt, sources: [...] }`
  - Each `sources[]` entry must include stable fields for `sourceKey`, `packageIds[]`, `source.type`, `source.spec`, `source.installSpec`, `source.packageName`, `materializedPath`, `materializedKey`, and the install facts needed for later comparison (`installedVersion` for npm, `installedCommit` plus ref classification for git).
- `nix/modules/pi/check-managed-package-status.mjs` must emit `schemaVersion: 1` JSON in both `manual` and `startup` modes.
  - Top-level shape: `{ schemaVersion, mode, generatedAt, summary, sources, warnings }`
  - `sources[]` must classify each deduped source as exactly one of `current`, `stale`, or `unknown` and must include sorted `packageIds[]` plus stable machine-readable reason fields when status is `unknown`.
- Startup snapshot files under `~/.pi/agent/startup-status/<launch-id>.json` must reuse the status-engine payload and add launch-scoped metadata (`launchId`, `createdAt`, `expiresAt`).
- `PI_MANAGED_PACKAGE_STARTUP_STATUS_PATH` is the only supported handoff channel from the wrapper to the Pi process. Skipped/noninteractive launches must unset it.
- Schema evolution policy: additive fields may be introduced within v1; removing/renaming fields or changing meanings requires a schema bump plus fixture/spec updates in the same task.

### Exit code policy
- `check-managed-package-status.mjs`
  - `0` = status produced successfully, including cases where some sources are `stale` or `unknown`
  - `2` = environment/dependency/input problem (missing manifest, missing helper binary, unreadable temp dir, unsupported CLI invocation)
  - `3` = malformed contract or internal error
- `check-updates`
  - `0` = inspection output completed successfully, including stale/unknown findings; `--update` completed all requested npm declaration rewrites
  - `1` = bad CLI usage or npm declaration rewrite failure in `--update` mode
  - `2` = dependency/declaration-path/input problem
  - `3` = shared engine contract/internal failure
- `pi` wrapper
  - must `exec` the real Pi binary and return the child exit status whenever possible
  - status-check failures are warning-only and must not change startup availability
  - only failure to invoke the real Pi binary is a wrapper-level hard error

### Warning taxonomy
- Top-level status-engine and startup-snapshot warnings must use the stable object shape `{ code, message, sourceKey?, packageIds?, detail? }`.
- Required run-level warning codes:
  - `PI_PACKAGE_WARN_STATUS_CHECK_SKIPPED` — wrapper intentionally skipped evaluation for this invocation class
  - `PI_PACKAGE_WARN_STATUS_CHECK_FAILED` — startup/manual run fell back because the shared checker could not complete as a whole
  - `PI_PACKAGE_WARN_STARTUP_SNAPSHOT_IGNORED` — notifier ignored a missing, expired, malformed, or unowned snapshot
- Per-source `unknown` results must expose stable `reasonCode` values so manual and startup surfaces can match without parsing prose. Required reasons to cover in tests: `TIMEOUT`, `LOOKUP_FAILED`, `REF_MISSING`, `AUTH_REQUIRED`, `OFFLINE`.
- Legacy `PI_PACKAGE_WARN_GIT_SOURCE_MANUAL_UPDATE` becomes obsolete once the shared engine is authoritative; do not keep two competing machine-readable contracts for git freshness.

### Determinism rules
- `sources[]` must be sorted by `sourceKey` in machine-readable output.
- `packageIds[]` within each source must be sorted lexicographically.
- Manual text output must list stale sources first, then unknown sources, with deterministic package/source ordering inside each section.
- Fast-spec fixtures must inject clocks/IDs so timestamped snapshot output is stable under test.
- Shared-source packages must produce one remote check and one source-level result, then fan out deterministically to the sorted package ID list.

### File / module skeleton
- `nix/modules/pi/build-managed-package-install-state.mjs` — activation-time helper that reads managed declarations + installed materialization state and emits the install-state manifest.
- `nix/modules/pi/check-managed-package-status.mjs` — machine-readable checker used by startup and `check-updates`.
- `scripts/check-updates.sh` — thin frontend for manual inspection (`--dry-run`) and legacy npm-only declaration rewriting (`--update`).
- `scripts/pi-launch-wrapper.sh` — argv classifier, startup snapshot producer, env handoff, and `exec` wrapper around the real Pi binary.
- `nix/modules/pi/extensions/startup-staleness-warning/index.ts` — Pi startup notifier that reads the wrapper-exported snapshot, renders stale vs unknown distinctly, sets footer/status text, and consumes the snapshot once.
- `nix/modules/pi/default.nix` — packages/wires the helper scripts, wrapper, extension install, activation manifest generation, and helper availability in the Home Manager module.
- `flake.nix` — overlay/package wiring for `check-updates` and wrapper assets.
- `tests/specs/managed-package-install-state-spec.sh` — manifest contract regression spec.
- `tests/specs/managed-package-status-spec.sh` — status-engine/manual-frontend regression spec.
- `tests/specs/pi-startup-wrapper-spec.sh` — wrapper argv/snapshot/env regression spec.
- `tests/specs/startup-warning-extension-spec.sh` — notifier rendering/consume-once regression spec.
- `tests/specs/pi-startup-warning-contract-spec.sh` — docs/helper-availability/scope-wording regression spec.

### Acceptance checklist
- [ ] Activation writes `managed-packages.install-state.json` with `schemaVersion: 1` and the install facts needed for npm and git comparisons.
- [ ] One shared checker produces deterministic `current` / `stale` / `unknown` classifications for manual and startup modes.
- [ ] `check-updates --dry-run` works with the repo's actual declaration path and stays informational for stale findings.
- [ ] The PATH `pi` command is repo-owned, delegates to the injected upstream Pi binary/store path (never recursive PATH lookup), checks only documented interactive launches, and still keeps `--help`/`list` output clean.
- [ ] The notifier reads only `PI_MANAGED_PACKAGE_STARTUP_STATUS_PATH`, ignores expired/malformed/unowned files, and consumes a valid snapshot once.
- [ ] Startup warning copy, helper output, and README wording all point to `check-updates --dry-run` for inspection and `home-manager switch --flake ...` for applying updates, while explicitly saying the warning covers managed packages/plugins.
- [ ] `./tests/run-tests.sh fast` passes.
- [ ] `./tests/run-tests.sh all` passes, or unchanged pre-existing unrelated failures are documented under the gate policy below.

## Work Plan

### Task Graph
| ID | Task | Depends on | Deliverable | Verification | Status |
|---:|---|---|---|---|---|
| T1 | Add the managed-package install-state manifest contract | — | Activation writes `managed-packages.install-state.json` via a tested helper, with deterministic schema, source identity/install fields, and shared-source fan-out | `bash tests/specs/managed-package-install-state-spec.sh`, `bash tests/specs/flake-eval-spec.sh`, `./tests/run-tests.sh fast` | ⬜ |
| T2 | Build the shared status engine and align `check-updates` with it | T1 | One machine-readable checker plus a working `check-updates --dry-run` frontend using the correct declaration path, stable unknown-reason/warning taxonomy, and status schema | `bash tests/specs/managed-package-status-spec.sh`, `./tests/run-tests.sh fast` | ⬜ |
| T3 | Add the repo-owned `pi` launch wrapper and startup snapshot lifecycle | T2 | Wrapper-produced per-launch snapshot files with launch metadata, injected real-binary/helper paths, interactive/noninteractive argv handling, env handoff, and non-blocking fallback behavior | `bash tests/specs/pi-startup-wrapper-spec.sh`, `bash tests/specs/flake-eval-spec.sh`, `./tests/run-tests.sh fast` | ⬜ |
| T4 | Add the Pi startup notifier extension | T3 | Directly installed notifier extension that renders stale vs unknown results, uses actionable managed-scope copy, and consumes only the current launch snapshot | `bash tests/specs/startup-warning-extension-spec.sh`, `bash tests/specs/flake-eval-spec.sh`, `./tests/run-tests.sh fast` | ⬜ |
| T5 | Wire user-facing workflow docs, helper availability, and final contract coverage | T2, T3, T4 | Installed `check-updates` helper, aligned startup/helper/README wording, managed-scope contract coverage, and fast-suite coverage for the new repo contract | `bash tests/specs/pi-startup-warning-contract-spec.sh`, `./tests/run-tests.sh fast`, `./tests/run-tests.sh all` | ⬜ |

### Task Details

#### T1: Add the managed-package install-state manifest contract
**Depends on:** —
**Deliverable:** `nix/modules/pi/build-managed-package-install-state.mjs`, activation wiring in `nix/modules/pi/default.nix` that writes `~/.pi/agent/managed-packages.install-state.json`, fixture data under `tests/spec-fixtures/managed-package-install-state/`, and a dedicated regression spec in `tests/specs/managed-package-install-state-spec.sh` wired into the fast suite. The contract must persist the source identity and install facts the status engine needs later (`packageName`, `installSpec`, `materializedPath`, `materializedKey`, npm installed version, git installed commit/ref class, and sorted `packageIds[]`).
**Requirement refs:** N/A

**Task notes:**
- Lock the manifest schema before adding stale-classification logic.
- Cover deduped shared-source fan-out (`pi-ext-*`-style cases), npm installed-version capture, and git installed-commit/ref capture from activation-time facts.
- Keep local-source behavior explicit: if the current managed runtime excludes local declarations, the manifest should either omit them deterministically or mark them as non-runtime entries in a tested way.

**TDD checklist:**
- [ ] Add a failing shell spec in `tests/specs/managed-package-install-state-spec.sh` using fixtures under `tests/spec-fixtures/managed-package-install-state/` that asserts `schemaVersion: 1`, deterministic `sources[]` ordering, shared-source package fan-out, stable source identity fields (`packageName`, `installSpec`, `materializedPath`, `materializedKey`), npm `installedVersion`, and git `installedCommit` + ref classification are present in the emitted manifest.
- [ ] Update `tests/run-tests.sh` and `tests/README.md` so the new spec is part of the documented fast suite; run `bash tests/specs/managed-package-install-state-spec.sh` — confirm failure.
- [ ] Implement `nix/modules/pi/build-managed-package-install-state.mjs` and wire `nix/modules/pi/default.nix` so activation writes `managed-packages.install-state.json` after installation completes and before startup-time checks depend on it.
- [ ] Re-run `bash tests/specs/managed-package-install-state-spec.sh` — confirm pass.
- [ ] **Break-it check:** temporarily remove one required persisted fact (for example `installedCommit` or sorted `packageIds`) from the helper output, confirm the new spec fails, then restore it.
- [ ] Refactor helper structure/field assembly for clarity without changing the schema.
- [ ] Run task completion gates: `bash tests/specs/flake-eval-spec.sh` and `./tests/run-tests.sh fast`.

**Verification scope:**
- Fast feedback: `bash tests/specs/managed-package-install-state-spec.sh` — scope: touched-files
- Packaging gate: `bash tests/specs/flake-eval-spec.sh` — scope: package-wide
- Task completion gate: `./tests/run-tests.sh fast` — scope: package-wide

---

#### T2: Build the shared status engine and align `check-updates` with it
**Depends on:** T1
**Deliverable:** `nix/modules/pi/check-managed-package-status.mjs`, updated `scripts/check-updates.sh`, any needed fixture commands/data under `tests/spec-fixtures/managed-package-status/`, and `tests/specs/managed-package-status-spec.sh` wired into the fast suite.
**Requirement refs:** N/A

**Task notes:**
- The shared checker is the only place allowed to decide `current` / `stale` / `unknown`.
- Manual mode must stay informational: stale/unknown findings return exit 0, while actual tool/config failures use non-zero exits.
- Git semantics must explicitly cover: no ref → default branch head; branch ref → that branch head; pinned commit/tag → compare against the chosen upstream ref per the approved approach.

**TDD checklist:**
- [ ] Add a failing shell spec in `tests/specs/managed-package-status-spec.sh` with fixture manifests and fake `npm`/`git` executables under `tests/spec-fixtures/managed-package-status/` asserting: npm current/stale/lookup failure; git no-ref stale/current; git branch stale/current; pinned git stale when upstream advances; missing/deleted ref → `unknown`; timeout/auth/offline failures → `unknown` with stable `reasonCode` values (`TIMEOUT`, `LOOKUP_FAILED`, `REF_MISSING`, `AUTH_REQUIRED`, `OFFLINE`); top-level warning objects keep the `{ code, message, sourceKey?, packageIds?, detail? }` shape; one grouped result for shared sources; deterministic JSON/text ordering; exit 2 for missing/unreadable manifest/input problems; exit 0 for stale/unknown results in manual mode; and `--update` remains npm-only rather than rewriting git/local declarations.
- [ ] Extend `tests/run-tests.sh` and `tests/README.md` to include the new spec; run `bash tests/specs/managed-package-status-spec.sh` — confirm failure.
- [ ] Implement `nix/modules/pi/check-managed-package-status.mjs` to read `managed-packages.install-state.json`, perform deduped npm/git comparisons, emit the `schemaVersion: 1` JSON/text contract, and expose injectable time-budget/concurrency settings for deterministic testing.
- [ ] Update `scripts/check-updates.sh` to call the shared engine for `--dry-run`/default mode, to use the repo's actual declaration path, and to preserve `--update` as an explicit npm-only declaration rewrite path rather than a git/unknown updater.
- [ ] Re-run `bash tests/specs/managed-package-status-spec.sh` — confirm pass.
- [ ] **Break-it check:** temporarily change the pinned-git comparison rule (for example treat an advanced default branch as current for a pinned ref), confirm the spec fails, then restore it.
- [ ] Refactor summary formatting / helper composition while keeping the machine-readable schema stable.
- [ ] Run task completion gate: `./tests/run-tests.sh fast`.

**Verification scope:**
- Fast feedback: `bash tests/specs/managed-package-status-spec.sh` — scope: touched-files
- Task completion gate: `./tests/run-tests.sh fast` — scope: package-wide

---

#### T3: Add the repo-owned `pi` launch wrapper and startup snapshot lifecycle
**Depends on:** T2
**Deliverable:** `scripts/pi-launch-wrapper.sh`, wrapper/home-package wiring in `nix/modules/pi/default.nix` and `flake.nix`, fixture/harness data under `tests/spec-fixtures/pi-startup-wrapper/`, and a dedicated wrapper regression spec in `tests/specs/pi-startup-wrapper-spec.sh`.
**Requirement refs:** N/A

**Task notes:**
- The wrapper must classify supported interactive launches, run the shared checker only for those launches, and fail open to “skip warning” for everything else.
- The wrapper must delegate to injected absolute paths for the real Pi binary, Node runtime, and shared checker helper so PATH shadowing cannot recurse back into the wrapper.
- Snapshot creation must be atomic and per-launch. Skipped launches must clear `PI_MANAGED_PACKAGE_STARTUP_STATUS_PATH` so Pi cannot consume stale state.
- Wrapper failures in the status path are warning-only; failure to start the real Pi binary is the only hard failure.

**TDD checklist:**
- [ ] Add a failing shell spec in `tests/specs/pi-startup-wrapper-spec.sh` using fake real-Pi and fake status-engine commands under `tests/spec-fixtures/pi-startup-wrapper/` that asserts: plain `pi` launches create a unique snapshot containing `schemaVersion: 1`, `mode: "startup"`, `launchId`, `createdAt`, and `expiresAt`, and export `PI_MANAGED_PACKAGE_STARTUP_STATUS_PATH`; the wrapper execs the injected real-Pi path rather than rediscovering `pi` on PATH; `pi --help`, `pi list`, and `pi --version` skip checks and clear the env var; status-engine failure still execs the real Pi; and repeated launches do not reuse a fixed snapshot path.
- [ ] Extend `tests/run-tests.sh` and `tests/README.md` so the wrapper spec is in the documented fast suite; run `bash tests/specs/pi-startup-wrapper-spec.sh` — confirm failure.
- [ ] Implement `scripts/pi-launch-wrapper.sh` and update `nix/modules/pi/default.nix` / `flake.nix` so the PATH `pi` command is the repo-owned wrapper that delegates to the injected real upstream Pi binary/store path, invokes the shared checker through injected absolute runtime/helper paths, writes snapshots under `~/.pi/agent/startup-status/`, and clears the startup-status env var on skipped launches.
- [ ] Re-run `bash tests/specs/pi-startup-wrapper-spec.sh` — confirm pass.
- [ ] **Break-it check:** temporarily switch the wrapper back to a fixed shared snapshot file or stop unsetting `PI_MANAGED_PACKAGE_STARTUP_STATUS_PATH` on a skipped invocation, confirm the spec fails, then restore it.
- [ ] Refactor argv classification and snapshot-path assembly for readability without broadening the supported invocation surface beyond what the plan documents.
- [ ] Run task completion gates: `bash tests/specs/flake-eval-spec.sh` and `./tests/run-tests.sh fast`.

**Verification scope:**
- Fast feedback: `bash tests/specs/pi-startup-wrapper-spec.sh` — scope: touched-files
- Packaging gate: `bash tests/specs/flake-eval-spec.sh` — scope: package-wide
- Task completion gate: `./tests/run-tests.sh fast` — scope: package-wide

---

#### T4: Add the Pi startup notifier extension
**Depends on:** T3
**Deliverable:** `nix/modules/pi/extensions/startup-staleness-warning/index.ts`, module wiring in `nix/modules/pi/default.nix` to install it directly under `~/.pi/agent/extensions/`, fixture data under `tests/spec-fixtures/startup-warning-extension/`, any small test harness needed under `tests/scripts/`, and `tests/specs/startup-warning-extension-spec.sh`.
**Requirement refs:** N/A

**Task notes:**
- The notifier must read only the wrapper-exported snapshot path.
- It must validate ownership/freshness, distinguish stale vs unknown in rendered copy, point users to `check-updates --dry-run` for inspection and `home-manager switch --flake ...` for apply while explicitly saying the warning covers managed packages/plugins, set a status/footer summary while problems exist, and consume the snapshot once.
- It must not perform network calls or compute staleness itself.

**TDD checklist:**
- [ ] Add a failing spec in `tests/specs/startup-warning-extension-spec.sh` with prepared snapshot fixtures under `tests/spec-fixtures/startup-warning-extension/` and a small harness under `tests/scripts/` that simulates `session_start` and asserts: `ctx.ui.notify(...)` is called for stale/unknown results, stale and unknown sections are rendered distinctly, grouped package IDs are shown deterministically, the rendered copy says managed packages/plugins and points to `check-updates --dry-run` plus `home-manager switch --flake ...`, missing/expired/malformed snapshots are ignored with no replay, a consumed snapshot is not shown again, and a snapshot matching the shared startup-status contract is accepted without per-test translation glue.
- [ ] Extend `tests/run-tests.sh` and `tests/README.md` so the new spec is part of the documented fast suite; run `bash tests/specs/startup-warning-extension-spec.sh` — confirm failure.
- [ ] Implement `nix/modules/pi/extensions/startup-staleness-warning/index.ts` and update `nix/modules/pi/default.nix` to install the extension directly into the Pi agent extension directory.
- [ ] Re-run `bash tests/specs/startup-warning-extension-spec.sh` — confirm pass.
- [ ] **Break-it check:** temporarily collapse stale and unknown into one message or bypass the freshness/consume-once check, confirm the spec fails, then restore it.
- [ ] Refactor notifier formatting/helpers while keeping the snapshot contract and user-visible category split intact.
- [ ] Run task completion gates: `bash tests/specs/flake-eval-spec.sh` and `./tests/run-tests.sh fast`.

**Verification scope:**
- Fast feedback: `bash tests/specs/startup-warning-extension-spec.sh` — scope: touched-files
- Packaging gate: `bash tests/specs/flake-eval-spec.sh` — scope: package-wide
- Task completion gate: `./tests/run-tests.sh fast` — scope: package-wide

---

#### T5: Wire user-facing workflow docs, helper availability, and final contract coverage
**Depends on:** T2, T3, T4
**Deliverable:** module/flake wiring that installs the packaged `check-updates` helper for repo users, `README.md` + `tests/README.md` updates documenting the supported inspection/apply workflow and managed-scope wording, and a new fast-suite contract spec `tests/specs/pi-startup-warning-contract-spec.sh` covering helper availability, scope wording, and runner integration.
**Requirement refs:** N/A

**Task notes:**
- This task applies the approved scope wording and manual-workflow wording from the approach.
- The new docs/specs must ensure the feature does not ship with contradictory guidance: startup warns, `check-updates --dry-run` inspects, `home-manager switch --flake ...` applies. The contract check must read actual startup-warning copy/harness output in addition to README text so docs-only fixes cannot false-green.
- Keep direct-cloned installs explicitly out of scope in user-facing text.

**TDD checklist:**
- [ ] Add a failing contract/doc spec in `tests/specs/pi-startup-warning-contract-spec.sh` asserting: the Pi module installs a working `check-updates` helper for repo users; the startup notifier output/harness, `check-updates` user-facing output/help, and `README.md` all align on `check-updates --dry-run` plus `home-manager switch --flake .#<hostname>` as separate inspection/apply steps; the wording says the startup warning covers managed packages/plugins; and `tests/run-tests.sh`/`tests/README.md` list the new manifest/status/wrapper/notifier specs.
- [ ] Update `tests/run-tests.sh` and `tests/README.md` as needed so the new contract spec is part of the documented fast suite; run `bash tests/specs/pi-startup-warning-contract-spec.sh` — confirm failure.
- [ ] Implement the remaining wiring in `nix/modules/pi/default.nix` and `flake.nix` so `check-updates` is installed for repo users, then update `README.md`, `tests/README.md`, and any remaining startup/helper copy to document the supported workflow and scope boundary consistently.
- [ ] Re-run `bash tests/specs/pi-startup-warning-contract-spec.sh` — confirm pass.
- [ ] **Break-it check:** temporarily remove the helper from module installation or revert the README workflow text to imply `--update`/all installs are covered, confirm the spec fails, then restore it.
- [ ] Refactor wording for brevity/consistency across README, helper output, and test docs.
- [ ] Run task completion gate: `./tests/run-tests.sh fast`.
- [ ] Run plan final gate: `./tests/run-tests.sh all`.

**Verification scope:**
- Fast feedback: `bash tests/specs/pi-startup-warning-contract-spec.sh` — scope: touched-files
- Task completion gate: `./tests/run-tests.sh fast` — scope: package-wide
- Final gate: `./tests/run-tests.sh all` — scope: repo-wide

---

## Behavior / Coverage Matrix

| Behavior | Source of truth | Primary test layer | Negative/edge cases | Needs E2E? | Regression risk |
|----------|----------------|-------------------|---------------------|------------|-----------------|
| Activation persists authoritative install facts for each managed source | `nix/modules/pi/build-managed-package-install-state.mjs` + `nix/modules/pi/default.nix` | fixture-driven shell spec | shared-source fan-out, missing materialized path, omitted git commit/ref facts, deterministic sort order | no — the manifest helper can be exercised offline with fixtures and flake-eval packaging checks | high |
| Shared checker classifies npm and git sources as `current` / `stale` / `unknown` | `nix/modules/pi/check-managed-package-status.mjs` | fixture-driven shell spec | npm lookup failure, branch missing, default-branch drift, pinned commit drift, timeout/offline/auth failures, shared-source dedupe | no — deterministic fake `npm`/`git` seams are preferred over live network tests | high |
| Manual `check-updates --dry-run` matches startup semantics and stays informational | `scripts/check-updates.sh` + shared checker | shell spec | stale findings still exit 0, `--update` limited to npm declarations, wrong declaration path, grouped git results | no — shell spec can assert exit codes and output contracts directly | high |
| `pi` wrapper checks only interactive launches and exports a launch-owned snapshot path | `scripts/pi-launch-wrapper.sh` | shell spec | `--help`/`list`/`--version` skipped, checker failure falls open, env var cleared on skip, concurrent launches get distinct snapshot paths | no — fake real-Pi and fake checker processes are sufficient | high |
| Startup notifier renders stale and unknown distinctly, uses actionable managed-scope copy, and consumes a snapshot once | `nix/modules/pi/extensions/startup-staleness-warning/index.ts` | harnessed integration spec | expired snapshot, malformed JSON, missing file, wrong schema version, repeated session using the same snapshot, grouped package IDs, copy drift from the supported inspection/apply workflow | no — a `session_start` harness is a better deterministic seam than live TUI automation | high |
| Startup warning copy, helper output, and docs point users to the supported inspection/apply workflow | `nix/modules/pi/extensions/startup-staleness-warning/index.ts`, `scripts/check-updates.sh`, `README.md`, `tests/README.md`, `nix/modules/pi/default.nix`, `flake.nix` | shell spec + harnessed integration + repo-wide gate | helper not installed, startup copy drifts from helper/README wording, docs imply direct-clone coverage, helper/docs imply `--update` applies git updates, stale test-runner docs | no — notifier harness output, helper output, and docs can be asserted directly, with `all` as the repo-wide packaging gate | medium |

## Bad-test avoidance

The new tests in this plan must not be satisfiable by file-exists checks or by reading source text without exercising behavior.

The plan requires:
- fixture-driven specs that run the manifest helper, shared checker, wrapper, and notifier harness with realistic local inputs
- explicit exit-code assertions for `check-updates` and helper CLIs
- dedicated assertions for stable ordering, grouped-source fan-out, and stale-vs-unknown separation
- `bash tests/specs/flake-eval-spec.sh` and `./tests/run-tests.sh all` to prove the Nix/Home Manager packaging still instantiates after helper/wrapper/extension wiring

Insufficient tests for this plan include checking only that a new JSON file exists, checking only that the wrapper file is executable, or asserting only one literal warning string without validating the underlying classification/state contract.

## Baseline Gate Audit

Execution must record these baseline results before T1 implementation begins.

| Command | Scope | Baseline status | Related failures? | Notes |
|---------|-------|-----------------|-------------------|-------|
| `./tests/run-tests.sh fast` | package-wide | ⏳ not yet recorded | TBD | Required pre-T1 baseline for the deterministic repo-local suite |
| `./tests/run-tests.sh all` | repo-wide | ⏳ not yet recorded | TBD | Required pre-T1 baseline for flake eval + proof-set verification |
| `./tests/run-tests.sh full` | repo-wide | ⏳ not yet recorded | TBD | Record when the executor's environment has a functional Pi CLI; this is optional smoke, not the primary final gate |

### Gate policy for this plan
**Policy:** allow-scoped-completion
**Rationale:** `all` and especially `full` depend on the executor's live Nix/Pi/Home Manager environment. This plan adds deterministic fast specs for the touched stale-warning surface and uses `./tests/run-tests.sh all` as the intended final gate, but execution should not be forced to repair unrelated pre-existing live-environment failures discovered during the baseline. If the baseline already contains unrelated failures, completion requires: (1) all new targeted specs pass, (2) `./tests/run-tests.sh fast` stays green, (3) `bash tests/specs/flake-eval-spec.sh` passes after packaging changes, and (4) `./tests/run-tests.sh all` shows no new failures attributable to this plan.

## Verification Plan

### Commands
| Command | Scope | When | What it proves |
|---------|-------|------|----------------|
| `bash tests/specs/managed-package-install-state-spec.sh` | touched-files | During TDD loops for T1 | The install-state manifest schema and persisted install facts are correct and deterministic |
| `bash tests/specs/managed-package-status-spec.sh` | touched-files | During TDD loops for T2 | npm/git stale classification, grouped-source fan-out, and manual-mode exit semantics match the contract |
| `bash tests/specs/pi-startup-wrapper-spec.sh` | touched-files | During TDD loops for T3 | Wrapper argv classification, env handoff, snapshot lifecycle, and fail-open startup behavior are correct |
| `bash tests/specs/startup-warning-extension-spec.sh` | touched-files | During TDD loops for T4 | The notifier renders stale/unknown distinctly and ignores or consumes snapshots correctly |
| `bash tests/specs/pi-startup-warning-contract-spec.sh` | touched-files | During TDD loops for T5 | Helper availability, user guidance, managed-scope wording, and runner docs stay aligned |
| `bash tests/specs/flake-eval-spec.sh` | package-wide | Before task completion for tasks touching Nix/module packaging | The Home Manager module still instantiates/builds with the new helper, wrapper, and extension wiring |
| `./tests/run-tests.sh fast` | package-wide | Before each task completion | The repo-local shell-spec suite remains green after each task |
| `./tests/run-tests.sh all` | repo-wide | Before plan completion | Flake evaluation + proof-set verification still work after the full feature wiring lands |
| `./tests/run-tests.sh full` | repo-wide | Optional post-plan smoke | The live CLI help/list smoke still behaves in an environment with a functional Pi CLI |

### Completion Criteria
- [ ] All tasks marked done
- [ ] All new targeted specs pass
- [ ] `./tests/run-tests.sh fast` passes
- [ ] `bash tests/specs/flake-eval-spec.sh` passes after the final packaging changes
- [ ] `./tests/run-tests.sh all` passes, or unchanged unrelated baseline failures are documented under the gate policy
- [ ] All coverage-matrix rows have tests or explicit harness coverage
- [ ] Startup warning copy, README guidance, and `check-updates` behavior all point to the same inspection/apply workflow

## Compatibility & Migration (if applicable)

- **Backwards compatibility:** Existing managed facades, compile reports, and Pi core behavior remain intact. Noninteractive `pi` invocations must remain warning-free. Existing `check-updates --update` users keep the npm declaration rewrite behavior, but the supported inspection path becomes `--dry-run`/default.
- **Forwards compatibility:** Consumers of the new JSON artifacts must ignore additive fields in `schemaVersion: 1`. The notifier must treat missing/expired snapshots as no-op conditions so old files do not break future launches.
- **Migration steps:** Apply the Home Manager config to install the wrapper/helper/extension, let activation generate the install-state manifest, then allow subsequent interactive launches to create/consume per-launch startup snapshots.
- **Rollback strategy:** Remove the wrapper/helper/extension wiring and fall back to the upstream `pi` binary; stale install-state and startup-status files may remain on disk but must be safe to ignore/delete.

---

## Implementation Notes (update during execution)

### Progress Log
- 2026-05-19: Plan created from brief, approved approach, approach review, and findings covering startup flow, metadata model, git semantics, testing strategy, update-check current state, and warning UX.

### Evidence Ledger
- 2026-05-19: Startup-flow constraints captured — evidence: `findings/startup-flow.md`
- 2026-05-19: Managed metadata/install facts gap captured — evidence: `findings/plugin-metadata-model.md`
- 2026-05-19: Git stale semantics and command constraints captured — evidence: `findings/git-staleness.md`
- 2026-05-19: Existing `check-updates` limitations captured — evidence: `findings/update-check-current-state.md`
- 2026-05-19: Verification layers and canonical commands captured — evidence: `findings/testing-strategy.md`, `tests/README.md`
- 2026-05-19: User-facing workflow and warning-surface constraints captured — evidence: `findings/warning-ux.md`

### Deviations
- none yet

### Issues Encountered
- none yet

### Follow-ups

Do not add new executable tasks here. Capture accepted follow-ups in the repo backlog and reference their stable IDs.

- none yet
