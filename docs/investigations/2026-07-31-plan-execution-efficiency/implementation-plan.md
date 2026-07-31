# Implementation Plan: Pi Team Execution

**Status:** reviewed additive rollout; authorized for implementation
**Date:** 2026-07-31
**Implements:** `pi-team-execution.md`
**Evidence:** `README.md` and `notes/`

**Current state:** upstream substrate unit gate passed at `pi-messenger@0.15.0`; nothing is
installed or configured. Canonical process, requirements, and OpenCode behavior remain unchanged
through this rollout.

## Phase 0 — Upstream substrate gate ✅

- [x] At clean tag `v0.15.0`, commit
      `2f5e7dc9c77fd7a3fba4728931e8564ce48d9bab`, ran `npm install && npx vitest run` twice:
      **408/408 tests, 42 files**. This validates the upstream substrate contract, not this repo's
      deployment.

## Locked decisions

| Decision | Resolution |
|---|---|
| Rollout shape | Additive. Do not replace current canonical process, requirements, shared skills, OpenCode rendering, or archive anything. |
| Package | Npm `pi-messenger@0.15.0`; expose `./index.ts` and skill `pi-messenger-crew`. |
| Stable config | `config/pi-team/` is canonical; track one narrow `.pi` symlink for project Crew config; Nix links the global `pi-team` profile from the same source tree. Runtime board/team state remains ignored. |
| Models | `github-copilot/gpt-5.6-terra` for cheap/std/visual; `github-copilot/gpt-5.6-sol` for complex/visual-complex/reviewer/rescue/final review. |
| Risk approval | Labels `migration`, `destructive`, `auth`, `api-contract` always require human approval. |
| Skills | New unique Pi-only canonical skills rendered by the existing pipeline and linked through Nix. Do not modify shared `/discovery` or `/design`. |
| Tools | One deterministic Node CLI, `tools/pi-team.mjs`, with `check`, `init-board`, and `review-wave`. Board task creation remains lead-issued `pi_messenger` calls [SUB-7]. |
| Telemetry | Lead-authored `telemetry.md` from observable fields; no separate harvester in the first rollout. Missing data is `unavailable` [SUB-5]. |
| Promotion | Calibration must pass before a separate approved requirements/process migration. |

## Tool contract

`tools/pi-team.mjs` is dependency-free Node ESM.

### Input grammar

- UTF-8 Markdown, CRLF normalized to LF. The line `Plan schema: 1` is mandatory; all other
  versions are unsupported.
- Section names and table headers must exactly match `pi-team-execution.md` §4. Tables are
  single-line pipe tables; cells are trimmed; escaped or literal `|` inside cells, multiline
  cells, duplicate sections, and text after `## Tasks` are rejected.
- IDs and paths follow §4 exactly. Numeric task ID controls natural order (`T2` before `T10`).
- The v1 warning policy is **no warnings**: every diagnostic is an error and affects the exit
  status. Diagnostic codes are stable uppercase identifiers.

### `check PLAN.md [--json]`

- Checks required fields/columns, unique/resolved IDs, allowed lanes/risks, positive estimates,
  worker/integration/final check coverage, DAG validity, deterministic waves, critical-path
  thresholds, same-wave normalized write-set disjointness, and mechanical packet resolution.
- Human mode prints the summary to stdout and sorted `CODE: message (location)` diagnostics to
  stderr. `--json` prints one object and nothing to stderr with this versioned shape:

```typescript
{
  schemaVersion: 1,
  valid: boolean,
  diagnostics: Array<{ code: string, message: string, location: { section: string, row: number, field: string } }>,
  metrics: null | { serialEstimateMin: number, criticalPathMin: number, criticalPathRatio: number,
    largestCriticalTask: { id: string, estimateMin: number, criticalPathShare: number } },
  waves: Array<{ index: number, taskIds: string[], integrationGroups: string[] }>,
  tasks: Array<{ id: string, title: string, content: string, deps: string[], lane: string,
    estimateMin: number, riskLabels: string[], integration: string, deliverable: string,
    writeSet: string[], contracts: string[], decisions: string[], check: string }>
}
```

  Equal-length critical chains and equal largest-task shares choose the lowest numeric task ID.
- Diagnostics are `{code,message,location:{section,row,field}}`. `row` is the 1-based physical
  source line. Sort by code, section, row, field, then message. Contract/parse diagnostics use
  `PLAN_*`; gate diagnostics use `GATE_*`.
- Cycles, dangling dependencies, and other cases without computable metrics/waves are malformed
  contracts and exit `2`; JSON emits `metrics: null`, `waves: []`, and `tasks: []`.
  Exit `1` is reserved for a structurally valid DAG failing threshold or overlap gates, so its
  metrics/waves are always complete. Exit `0` is valid.
- Numeric IDs compare as arbitrary-size digit strings: digit count, then lexical value. Equal
  critical chains choose the lexicographically lowest full numeric-ID sequence; equal largest
  tasks on that chain choose the lowest numeric ID. Arrays use those rules. Same input yields
  byte-identical JSON.

### `init-board PLAN.md --crew-dir DIR --repo-root ROOT`

- Runs `check`; PLAN must resolve inside ROOT. `prd` is its normalized repo-relative path.
- Allows stable `DIR/config.json` and `DIR/agents/`. Refuses only runtime entries:
  `plan.json`, `plan.md`, `tasks/`, `blocks/`, `artifacts/`, `planning-progress.md`, or
  `planning-outline.md`.
- Atomically publishes only `DIR/plan.json` with no-clobber hard-link semantics: `prd`, UTC
  ISO-8601 `created_at`/`updated_at`, `task_count: 0`, and `completed_count: 0` [SUB-3] [SUB-8].
  It never creates tasks or copies the authored plan. Crew's optional missing-`plan.md` validation
  warning is expected; any graph/count error or any other warning fails materialization.
- Exit `0`: initialized. Exit `1`: gate failure or existing runtime state. Exit `2`: malformed
  input, unsafe path, or I/O failure. Human diagnostics go to stderr.

### `review-wave PLAN.md --scope T1,T2 --bundle T2 --repo-root ROOT --base COMMIT --output-dir DIR`

- Runs `check`. Normal review uses the original wave for both comma-separated sets. Retry uses
  scope = original wave and bundle = retried tasks. Integration remediation uses scope = original
  wave plus failed-group tasks and bundle = tasks whose paths the remediation changed. Bundle IDs
  must be a subset of scope; scope must match one computed chunk plus zero or more complete
  integration groups.
- The lead requires a clean tree when recording BASE. The command requires `HEAD == BASE`,
  mechanically rejecting worker commits. It uses `git status --porcelain=v1 -z`,
  `git diff --binary BASE -- <write-set>`, and binary no-index diffs for untracked files. Paths
  are compared after plan normalization.
- Exit `1` if any changed path is outside scope's write-set union, a bundled task has no changed
  path, evidence exceeds 102400 bytes for a bundled task, or `HEAD != BASE`. Exit `2` for malformed
  input/git/I/O errors. It never truncates evidence.
- Atomically writes `<TASK_ID>.diff` for bundle IDs and `manifest.json`. Manifest schema:
  `{"schemaVersion":1,"base":"<sha>","tasks":[{"id":"T2","bundle":"T2.diff","bytes":0,"sha256":"hex","changedPaths":["path"]}],"affectedGroups":[{"id":"G1","revision":"sha256"}]}`.
  An integration revision hashes sorted `path NUL type NUL content-sha256` records for every
  existing/missing path under the group's exact-file/directory union; symlinks fail closed.
  `affectedGroups` includes every group whose union intersects any changed path. Tasks, groups,
  and paths are numeric-ID/lexically sorted. Existing output is refused.
- The lead passes each changed bundle plus the exact packet to a fresh read-only reviewer. Peer
  write sets may be in allowed dirty scope but never enter another task's bundle.

Recovery moves only the seven board runtime entries above to
`.pi/messenger/crew-runs/<YYYYMMDDTHHMMSSZ>/`. It never moves `config.json` or `agents/`.
Incomplete started work requires human confirmation; pre-worker partial materialization may be
archived automatically. Board materialization follows the byte-level packet template in
`pi-team-execution.md` §4, captures returned Crew IDs, translates dependencies, and runs
`crew.validate`. No hidden second plan format.

## Tasks

### T1 — Package and reproducible configuration

**Depends:** Phase 0
**Owns:** `nix/modules/pi/default.nix`, `tests/fixtures/proof-set.json`,
`config/pi-team/{crew-config.json,team-profile.json}`, `.gitignore`,
`.pi/messenger/crew/config.json`, `tests/specs/pi-team-config-spec.sh`,
`tests/specs/pi-module-content-spec.sh`, `tests/specs/proof-set-runtime-spec.sh`,
`tests/run-tests.sh`, `tests/README.md`
**Requirements:** FR-002, OPR-001
**Deliverables:**

- Add npm package `pi-messenger@0.15.0` and exact proof expectations:
  extension `./index.ts`, skill `pi-messenger-crew`, no themes.
- Create the two canonical files under `config/pi-team/`. Nix links `team-profile.json` to
  `~/.pi/agent/messenger/team-profiles/pi-team.json`; matching task risk labels persist pending
  approval and are excluded from ready/start paths until `task.approve` [SUB-9].
- Track one relative symlink from the admitted `.pi` config path to the canonical config.
- Use the exact Crew JSON in `pi-team-execution.md` §5: four workers, strict dependencies,
  Crew auto-review disabled, two attempts, one wave, stop on block, artifacts enabled, and
  minimal coordination.
- Narrowly unignore only the stable config symlink; leave all board/team/review/activity state
  ignored.

**TDD:**

1. Add failing assertions to `pi-module-content-spec.sh`, `proof-set-runtime-spec.sh`, and a focused
   `pi-team-config-spec.sh` for exact package/profile/config contracts.
2. Implement the minimum declarations/files.
3. Wire the new spec into `tests/run-tests.sh fast` and document it in `tests/README.md` in this
   task.
4. Break-it: prove runtime board files remain ignored and an invalid profile/risk policy fails.
5. Verify:
   `bash tests/specs/pi-team-config-spec.sh` ·
   `bash tests/specs/proof-set-runtime-spec.sh` ·
   `bash tests/specs/pi-module-content-spec.sh` · `./tests/run-tests.sh fast`.

### T2 — Deterministic plan compiler and board initializer

**Depends:** T1
**Owns:** `tools/pi-team.mjs`, `tests/specs/pi-team-tool-spec.sh`,
`tests/spec-fixtures/pi-team/`, `tests/run-tests.sh`, `tests/README.md`
**Requirements:** FR-002, OPR-001
**Deliverables:** implement the locked CLI contract and fixture-backed acceptance tests.

**TDD:**

1. Add fixtures for valid diamond DAG; cycle; dangling references; invalid lane/risk/path;
   zero estimate; missing worker/integration/final checks; write overlap; threshold failure;
   malformed/unsupported tables; stable config coexisting with init; runtime-state refusal; and
   tracked/untracked review changes.
2. Write failing spec for grammar, diagnostic schema/order, exit codes, deterministic JSON,
   metrics/waves, atomic no-clobber record shape, exact packet bytes, review manifest/bundles,
   and no task creation.
3. Implement the minimum parser/checker/initializer/review bundler and wire/document the spec in
   the fast suite.
4. Break-it: shuffled task rows produce identical output; CRLF normalizes; traversal/symlink/glob
   paths fail; partial/malformed board state is never overwritten; directory-prefix overlap is
   detected; `config.json` and `agents/` survive initialization; out-of-set/untracked/oversized
   review evidence fails closed; peer write sets never enter another task's bundle.
5. Verify: `bash tests/specs/pi-team-tool-spec.sh` · `./tests/run-tests.sh fast`.

### T3 — Additive Pi-only skills and deployment wiring

**Depends:** T2
**Owns:** `skills/pi-team-plan/`, `skills/pi-team-lead/`, `skills/pi-team-worker/`,
`agents/pi-team-reviewer.md`, `dist/skills/pi/pi-team-{plan,lead,worker}/`,
`nix/modules/pi/default.nix`, `tests/specs/skill-content-spec.sh`,
`tests/specs/skill-render-spec.sh`, `tests/specs/pi-module-content-spec.sh`
**Requirements:** FR-002, OPR-001
**Deliverables:**

- `pi-team-plan` (`disable-model-invocation: true`): create the exact plan contract; run CLI check;
  commission fresh semantic review; never auto-waive risk approval.
- `pi-team-lead`: active-profile preflight; exact init/materialization algorithm; clean-tree and
  `HEAD == BASE` isolation; one-wave dispatch; review-bundle generation; fresh task-reviewer
  calls; per-wave commits; board reset/block transitions; every affected completed integration
  group once per content digest with two remediation revisions; bounded rescue; lead gates/close.
- `pi-team-worker`: packet/write-set discipline, one minimal check, concise handoff, no commit/broad
  suite/bash-write bypass.
- `pi-team-reviewer` agent: read-only; one packet plus complete bundle; exact
  `SHIP|NEEDS_WORK|MAJOR_RETHINK`; no truncation or peer-write-set inspection.
- All three skills use `harnesses: [pi]`, render through the existing pipeline, and install via
  Nix together with the reviewer agent.

**TDD:**

1. Add failing content/render/module assertions for Pi-only presence and required protocol anchors.
2. Write the canonical skills and render with `node tools/render-skills.mjs --write`.
3. Add Nix skill links.
4. Break-it: verify no OpenCode outputs exist for these skills and no stale/hand-edited dist passes.
5. Verify: `bash tests/specs/skill-content-spec.sh` ·
   `bash tests/specs/skill-render-spec.sh` · `bash tests/specs/pi-module-content-spec.sh` ·
   `./tests/run-tests.sh fast`.

### T4 — Setup documentation and current-checkout deployment proof

**Depends:** T3
**Owns:** `docs/pi-team-setup.md`, `AGENTS.md`, `tests/specs/repo-readiness-docs-spec.sh`
**Requirements:** FR-001, FR-002, NFR-002, OPR-001
**Deliverables:** route an additive setup/preflight doc without changing canonical execution policy.
Document package/profile/config provenance, profile activation, board recovery, exact gates, and
that the investigation remains non-canonical pending calibration.

**TDD and verification:**

1. Add failing readiness assertions, then write the minimum doc/route.
2. Break-it: stale package version, missing profile activation, or claims that runtime state is
   tracked must fail the targeted spec.
3. Run `bash tests/specs/repo-readiness-docs-spec.sh` and `./tests/run-tests.sh fast`.
4. Run `./scripts/pi-dev.sh --verify` against the current checkout.
5. Run `home-manager switch --flake .#<hostname>` for the active installation, then verify package,
   skill, profile, project config, reviewer, and callable `pi_messenger` tool.
6. Record any pre-existing environment failure separately; new failures block T4.

### T5 — Bootstrap calibration and fresh final review

**Depends:** T4
**Owns:** `docs/investigations/2026-07-31-plan-execution-efficiency/calibration/bootstrap/`,
`docs/investigations/2026-07-31-plan-execution-efficiency/README.md`,
`docs/investigations/2026-07-31-plan-execution-efficiency/pi-team-execution-plan.html`,
`docs/investigations/2026-07-31-plan-execution-efficiency/check-doc-refs.sh`,
`docs/issues_learnings.md`;
no canonical `plans/`, process, requirements, or backlog changes
**Requirements:** FR-002, OPR-001
**Deliverables:**

1. Self-host the new flow on a frozen, file-disjoint documentation/tool task: align the
   investigation `README.md` and visual HTML with the reviewed additive architecture, and extend
   `check-doc-refs.sh` to reject the stale phrases `review-on-handoff`, `every handoff`,
   `Phase 1b`, and `plans/<date>-<slug>` in those two promoted summaries. Store its
   plan/review/telemetry under `calibration/bootstrap/`, outside canonical `plans/`.
2. Freeze packet estimates and their serial sum before materialization. Use at most three workers
   with the configured models.
3. Record objective telemetry: timestamps, task/attempt/review-reset counts, out-of-write-set
   findings, gate failures, classified interruptions, actual wall-clock, and frozen serial
   estimate. Cost stays `unavailable`.
4. Bootstrap pass: zero out-of-write-set changes; no significant defect surviving final review;
   targeted/fast/deployment/all gates green relative to baseline; no unclassified interruption.
5. Run `./tests/run-tests.sh all`, then commission a fresh
   `github-copilot/gpt-5.6-sol` full-diff review. Allow at most two fresh remediation passes;
   after each, rerun `all` and re-review. Completion requires both green on the same commit.
6. Record outcomes and top friction in `docs/issues_learnings.md`.

This bootstrap proves mechanics and does **not** count as a representative code-change run.
Canonical promotion remains blocked until three additional representative code-change
calibrations pass and their median wall-clock is ≤ 60% of their frozen serial estimates. Failure leaves the additive
implementation available but **not canonical**. A later migration needs explicit approval and an
inventory of `WF-005`, `FR-007`, `FR-008`, `NFR-003`, and `OPR-003` changes.

## Dependency graph

```text
Phase 0 ✅ → T1 package/config → T2 tool → T3 skills → T4 deploy/docs → T5 calibrate/final review
```

No tasks are parallelized in the bootstrap plan because T2 consumes T1's config contract, T3
consumes T2's CLI contract, T4 proves the assembled deployment, and T5 consumes the live system.
Team-mode parallelism begins with calibration, not while building its own control plane.
