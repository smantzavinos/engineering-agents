# Testing Strategy

## Standard Level Mapping

| Standard level | Repo command | Scope | Typical timing | Typical duration | What it proves |
|---|---|---|---|---|---|
| Fast feedback | `bash tests/specs/repo-readiness-docs-spec.sh` or `bash tests/specs/proof-set-runtime-spec.sh` | touched-files | During TDD loops | seconds | The touched readiness docs or proof-set helper behavior changed as intended without waiting for the whole suite |
| Integration / task completion gate | `./tests/run-tests.sh fast` | package-wide | Before marking a task complete | under a minute | The repo-local shell spec suite, runner wiring, and doc/helper contracts still agree |
| Local Pi deployment verification | `./scripts/pi-dev.sh --verify` | current checkout | Before pushing Pi-module, package, skill, or extension changes | minutes; network on first run | The sandboxed Home Manager activation, generated facades, and live Pi proof-set work from the working tree |
| Build / final plan gate | `./tests/run-tests.sh all` | repo-wide | Before declaring the plan complete | minutes | Repo-local specs, flake evaluation, and Pi proof-set verification are all trustworthy together |
| Full verification | `./tests/run-tests.sh full` | repo-wide | Optional release smoke after the final gate | minutes | Everything in `all` plus live Pi CLI smoke coverage still works |

## Scope, Timing, and Prerequisites

### `bash tests/specs/repo-readiness-docs-spec.sh`
- **Standard level:** Fast feedback
- **Scope:** touched-files
- **When to run:** During TDD loops for repo-local operational docs
- **Prerequisites:** `bash`
- **What it catches:** missing routes, missing canonical docs, stale anchors, and inconsistent task/final gate references

### `bash tests/specs/proof-set-runtime-spec.sh`
- **Standard level:** Fast feedback
- **Scope:** touched-files
- **When to run:** During TDD loops for proof-set verification helpers
- **Prerequisites:** `bash`, `jq`, `node`
- **What it catches:** current-vs-legacy Pi module path resolution, deterministic snapshot ordering, and explicit non-zero proof-set environment failures

### `./tests/run-tests.sh fast`
- **Standard level:** Integration / task completion gate
- **Scope:** package-wide
- **When to run:** before the task completion gate is recorded in a worklog
- **Prerequisites:** `bash`, `jq`, `node`
- **What it catches:** shell-spec aggregation drift, broken runner wiring, doc/test contract mismatches, and repo-local packaging contract regressions

### `./scripts/pi-dev.sh --verify`
- **Standard level:** Local Pi deployment verification
- **Scope:** current checkout
- **When to run:** before pushing changes to the Pi module, managed packages, extensions, skills, or their activation wiring
- **Prerequisites:** `nix`; network access on the first sandbox activation
- **What it catches:** generated-facade, managed-package installation, and live proof-set failures using the current working tree under `.pi-dev/`
- **Boundary:** this is an isolated sandbox and does not replace `./tests/run-tests.sh all`, which verifies the active Home Manager installation and its production wrapper path

### `./tests/run-tests.sh all`
- **Standard level:** Build / final plan gate
- **Scope:** repo-wide
- **When to run:** before the final plan gate is recorded or the overall plan is marked complete
- **Prerequisites:** everything required for `fast`, plus `nix`, `pi`, and a completed `home-manager switch --flake .#<hostname>` so the proof-set environment exists
- **What it catches:** flake evaluation failures, proof-set verification failures, and broader repo-wide integration drift that the fast suite cannot see

### `./tests/run-tests.sh full`
- **Standard level:** Full verification
- **Scope:** repo-wide
- **When to run:** optional post-plan or release smoke
- **Prerequisites:** everything required for `all`, plus a working `pi` CLI on PATH
- **What it catches:** CLI help/list smoke regressions on top of the final plan gate

## Targeted Shell Specs
- `bash tests/specs/repo-structure-spec.sh` — repo structure and required file presence
- `bash tests/specs/repo-readiness-docs-spec.sh` — root routing and canonical repo-operating docs
- `bash tests/specs/proof-set-runtime-spec.sh` — proof-set runtime contract regression coverage
- `bash tests/specs/skill-content-spec.sh` — skill frontmatter and content checks
- `bash tests/specs/pi-module-content-spec.sh` — Pi module content integrity
- `bash tests/specs/preset-spec.sh` — preset configuration validation
- `bash tests/specs/compiler-contract-spec.sh` — compile helper and fixture contract validation
- `bash tests/specs/flake-eval-spec.sh` — Nix flake evaluation (included by `./tests/run-tests.sh all`)
- `bash tests/specs/pi-dev-spec.sh` — repo-local Pi sandbox isolation and credential-copy contract

## Gate Roles
- **Task completion gate:** `./tests/run-tests.sh fast`
- **Final plan gate:** `./tests/run-tests.sh all`
- **Optional release smoke:** `./tests/run-tests.sh full`

### Team-mode ownership
- **Implementer:** packet-defined formatter, diagnostics, or one targeted smoke check only.
- **Contract/verifier:** early acceptance contracts plus targeted verification evidence.
- **Live reviewer:** adds risk-based remediation or verification tasks; does not run broad gates.
- **Lead:** package/repo integration gates, final gate, commits, and baseline-failure comparison.
- **Final reviewer:** fresh full-diff review after implementation-team closure.

## Related Docs
- `plans/README.md` — tells plans and worklogs where to source these commands and gate roles.
- `tests/README.md` — suite inventory, file layout, and individual spec entry points.
- `docs/issues_learnings.md` — place recurring verification surprises or lessons here when they should stay visible.

`tests/README.md` remains the suite inventory and file-layout companion document. This file is the canonical mapping from the repo's command surface to the standard testing levels used by plans and worklogs.
