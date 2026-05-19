# Testing strategy for wrapper/plugin update warning behavior

**Created:** 2026-05-19
**Topic:** Existing test infrastructure and non-network test seams for stale-plugin startup warnings
**Plan:** plans/startup-extension-staleness-warning/brief.md

## Summary
The repo already has three distinct testing layers that matter for this work: fast repo-local shell specs, Nix activation-package builds, and live Pi verification/smoke tests. The fast layer is the most relevant for deterministic stale-status testing because it already uses fixture files, temporary directories, explicit exit-code assertions, and JSON shape checks without requiring Pi, Home Manager, or external services (`tests/run-tests.sh:36-58`, `tests/specs/compiler-contract-spec.sh:22-85`).

For update-related behavior specifically, the most useful existing seam is `scripts/check-updates.sh`, which already supports dependency injection through environment variables for the declaration file, npm binary, and Python binary (`scripts/check-updates.sh:14-17`). That means npm-backed stale and failure cases can be exercised without live registry access by supplying a fixture declaration file and a fake `npm` executable. Git-backed stale detection is not covered today: the current script only emits a manual-update warning for git sources and does not inspect remotes (`scripts/check-updates.sh:402-406`). Live Pi tests can verify that warnings are surfaced during startup, but the current live tests operate against the active `~/.pi` state and are therefore better suited as an integration/smoke layer than as the primary stale/unknown-status logic test (`tests/test-fast.sh:25-46`, `tests/run-tests.sh:81-118`).

## Findings

### The existing suite is intentionally split between deterministic local specs and live installed-state verification
The documented test tiers are: repo-local specs, flake eval, Pi proof-set, and CLI smoke (`tests/README.md:5-10`). The main runner reflects that split: `fast` runs only repo-local specs, `all` adds flake evaluation and proof-set verification, and `full` adds CLI smoke (`tests/run-tests.sh:36-58`, `tests/run-tests.sh:123-139`).

This matters for startup warning work because only the repo-local layer is isolated from the user's real Pi installation and external environment. The live proof-set requires Pi to be installed and `home-manager switch` to have been run already (`tests/README.md:7-10`, `tests/test-fast.sh:1-8`).

### Shell-based fixture tests are the dominant existing pattern for wrapper/backend logic
`tests/specs/compiler-contract-spec.sh` shows the repo's main pattern for backend-style testing:
- create a temporary working directory (`tests/specs/compiler-contract-spec.sh:14-15`),
- invoke a real script/helper with fixture input (`tests/specs/compiler-contract-spec.sh:22-33`),
- assert exit status and stderr/stdout text (`tests/specs/compiler-contract-spec.sh:36-72`), and
- assert output structure with `jq` (`tests/specs/compiler-contract-spec.sh:74-244`).

The compiler spec is also fully offline. It feeds JSON fixtures from `tests/spec-fixtures/compiler/` into `nix/modules/pi/compile-managed-packages.mjs` and verifies deterministic JSON output, generated files, symlink structure, and negative cases such as malformed declarations and missing resources (`tests/specs/compiler-contract-spec.sh:88-244`).

That same fixture-driven shell pattern is the closest existing precedent for testing wrapper/plugin update warning logic in this repo.

### There is fixture scaffolding for update-checker inputs, but no automated spec currently consumes it
The test docs list `tests/spec-fixtures/update-checker/` as a fixture area (`tests/README.md:60-64`). The directory currently contains a single sample declaration file with one npm package, one git package, and one local package (`tests/spec-fixtures/update-checker/pi.nix.sample:1-32`).

However, the test runner's explicit spec list does not include any update-checker spec (`tests/run-tests.sh:40-44`), and the only direct automated assertions around `check-updates.sh` in the current suite are that the file exists and is executable (`tests/specs/pi-module-content-spec.sh:78-83`). In other words, the repo already has fixture input for update-checking, but it does not yet have behavioral coverage for that script.

### The current update-checker already exposes non-network injection points for npm-backed stale and failure cases
`scripts/check-updates.sh` accepts environment overrides for:
- the declarations file: `PI_UPDATE_CHECKER_NIX_FILE`
- the npm executable: `PI_UPDATE_CHECKER_NPM_BIN`
- the Python executable: `PI_UPDATE_CHECKER_PYTHON_BIN`
- interactive prompting: `PI_UPDATE_CHECKER_ASSUME_YES`
(`scripts/check-updates.sh:14-17`).

The script parses the declaration file locally (`scripts/check-updates.sh:57-191`) and, for npm sources, shells out only to `"$NPM_BIN" view "$package_name" version` (`scripts/check-updates.sh:391-399`). Observable consequences:
- A test can point `PI_UPDATE_CHECKER_NIX_FILE` at `tests/spec-fixtures/update-checker/pi.nix.sample` or another temp fixture.
- A test double for `PI_UPDATE_CHECKER_NPM_BIN` can deterministically return a newer version, the same version, or an empty result.
- An empty `npm view` result is already treated as a failure path by the script (`scripts/check-updates.sh:393-396`).

Because those behaviors are driven entirely by local files and a replaceable command path, npm-backed stale and "could not determine" cases can be exercised without touching the live npm registry.

### Git sources are present in both runtime configuration and fixtures, but no current automated path computes git staleness
The managed Pi configuration includes multiple git-backed packages, including `pi-subagents`, `pi-hooks`, `pi-ext-leader-key`, `pi-ext-review`, and `pi-gitnexus` (`nix/modules/pi/default.nix:21-37`, `nix/modules/pi/default.nix:142-169`, `nix/modules/pi/default.nix:212-219`). The sample update-checker fixture also includes a git package entry (`tests/spec-fixtures/update-checker/pi.nix.sample:13-20`).

At install time, git packages are handled in `installPiExtensions` by uninstalling any existing copy and reinstalling from the configured `installSpec` (`nix/modules/pi/default.nix:612-624`). At check time, `scripts/check-updates.sh` does not query git remotes; it only prints a manual-update warning for git sources (`scripts/check-updates.sh:402-403`).

So the repo has git package declarations and git install behavior, but it does not currently have a test seam or implementation path for "git source is stale" versus "could not determine git status." Any automated test for those states would need to target new wrapper logic rather than reuse existing `check-updates.sh` behavior as-is.

### Live proof-set and CLI smoke tests can verify surfaced warnings, but they are not isolated enough to be the primary stale-logic tests
The live proof-set test reads the active `~/.pi/agent/settings.json`, requires it to be a writable regular file, then generates a snapshot from the live Pi installation (`tests/test-fast.sh:25-46`). It validates resolved package facades and source roots from the current machine state (`tests/test-fast.sh:54-73`).

The CLI smoke layer similarly invokes the real `pi` binary with `PI_OFFLINE=1`, capturing `stdout` and `stderr` from `pi --help` and `pi list` (`tests/run-tests.sh:81-118`). This is the existing mechanism closest to checking whether a startup warning is visible during an actual Pi invocation.

Those layers are useful for final integration coverage, but they are coupled to the active Pi install and home directory. They are not fixture-isolated the way `compiler-contract-spec.sh` is.

### The proof-set snapshot tooling already has a pattern for warning-code plumbing from local artifacts
`tests/scripts/resource-snapshot.mjs` defines an allowlist of warning codes and rejects unknown codes when rendering a snapshot (`tests/scripts/resource-snapshot.mjs:13-19`, `tests/scripts/resource-snapshot.mjs:699-702`). It also reads warnings from the local `managed-packages.report.json` file in the Pi agent directory and merges them into snapshot warnings (`tests/scripts/resource-snapshot.mjs:476-493`, `tests/scripts/resource-snapshot.mjs:690-696`).

The repo already stores snapshot fixtures that model warning output, for example `tests/spec-fixtures/resource-snapshot.v2.stale-artifact-warning.json`, which includes `PI_PACKAGE_WARN_STALE_ARTIFACT_PRUNED` in its `warnings` array (`tests/spec-fixtures/resource-snapshot.v2.stale-artifact-warning.json:314-320`).

This shows an existing repo pattern for validating warning payloads using fixture JSON rather than live execution. It is currently limited to the proof-set snapshot schema and the small warning-code allowlist in `resource-snapshot.mjs`.

### Nix/build tests validate installation shape, not runtime update status
The flake checks build Home Manager activation packages and verify expected files in the resulting `home-files` tree (`tests/specs/flake-eval-spec.sh:26-118`). The Pi module activation script installs managed packages, compiles facades, and writes `managed-packages.report.json` (`nix/modules/pi/default.nix:575-646`).

This build layer proves that wrapper assets and activation scripts are present, but it does not execute startup-time status checks. It is better suited to catching packaging regressions than stale/unknown update outcomes.

### The current wrapper configuration means Pi sees generated package facades, not raw upstream package locations
The Pi settings written by the Nix module configure `packages = map (packageId: "./packages/${packageId}") piRuntimePackageIds` (`nix/modules/pi/default.nix:237-269`). The activation script then materializes generated facades under `~/.pi/agent/packages` and emits a compile report (`nix/modules/pi/default.nix:575-658`).

That architecture is relevant to testing because any startup warning implementation in this repo is likely to depend on repo-owned metadata or repo-owned wrapper logic rather than on Pi discovering upstream package versions directly from installed package paths.

## Constraints Discovered
- The `fast` test tier is the only existing tier that is fully repo-local and independent of a real Pi installation (`tests/README.md:5-10`, `tests/run-tests.sh:36-58`).
- There is currently no automated behavioral spec for `scripts/check-updates.sh`; the suite only checks that the script exists and is executable (`tests/run-tests.sh:40-44`, `tests/specs/pi-module-content-spec.sh:78-83`).
- `scripts/check-updates.sh` can model npm success/failure without the network because the npm command path and declarations file are injectable (`scripts/check-updates.sh:14-17`, `scripts/check-updates.sh:391-399`).
- The current script has no git freshness computation at all; it only emits a manual-update warning for git sources (`scripts/check-updates.sh:402-403`).
- The proof-set snapshot layer only accepts a fixed warning-code set; adding new warning categories would require updates to `tests/scripts/resource-snapshot.mjs` and fixture snapshots (`tests/scripts/resource-snapshot.mjs:13-19`, `tests/scripts/resource-snapshot.mjs:699-702`).
- Live proof-set verification depends on the user's active `~/.pi` state and therefore is not a hermetic place to exercise many stale/unknown permutations (`tests/test-fast.sh:25-46`).

## Risks
- Relying primarily on `tests/test-fast.sh` or CLI smoke for stale/unknown cases would couple tests to the local Pi install and home-directory contents, increasing brittleness (`tests/test-fast.sh:25-46`, `tests/run-tests.sh:81-118`).
- Git-based stale detection has no current test harness or command-injection seam analogous to `PI_UPDATE_CHECKER_NPM_BIN`, so new git-status logic could be hard to test deterministically unless it introduces a local seam.
- If new warning codes are surfaced through proof-set snapshots or compile reports, the current warning allowlist will reject them until the snapshot tooling is updated (`tests/scripts/resource-snapshot.mjs:13-19`, `tests/scripts/resource-snapshot.mjs:699-702`).
- The presence of `tests/spec-fixtures/update-checker/pi.nix.sample` without a consuming spec means the repo already has fixture inputs but no regression gate for update-check behavior (`tests/spec-fixtures/update-checker/pi.nix.sample:1-32`, `tests/run-tests.sh:40-44`).

## References
- `tests/run-tests.sh` — test-tier entrypoint; explicitly enumerates fast/all/full coverage and current spec list.
- `tests/README.md` — documents the intended test tiers and fixture layout.
- `tests/specs/compiler-contract-spec.sh` — exemplar offline shell spec using fixtures, temp dirs, exit-code assertions, and `jq` output checks.
- `tests/spec-fixtures/update-checker/pi.nix.sample` — existing mixed npm/git/local update-checker fixture input.
- `scripts/check-updates.sh` — current manual update-check script with injectable command/file paths and npm/git/local source branching.
- `nix/modules/pi/default.nix` — managed package declarations, facade package configuration, and Home Manager activation logic.
- `tests/test-fast.sh` — live proof-set verification against the active `~/.pi` state.
- `tests/scripts/resource-snapshot.mjs` — proof-set snapshot generator that merges local compile-report warnings and enforces a warning-code allowlist.
- `tests/spec-fixtures/resource-snapshot.v2.stale-artifact-warning.json` — example fixture showing how warning payloads are represented in snapshot JSON.
- `tests/specs/flake-eval-spec.sh` — Nix activation-package build verification for module packaging.
