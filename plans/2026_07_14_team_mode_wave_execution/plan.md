# Plan: Team-Mode Wave Execution

**Status:** draft
**Owner:** execution orchestrator (Sisyphus)
**Created:** 2026-07-14
**Related:** [brief.md](./brief.md), [approach.md](./approach.md), [wave-slicing-spec.md](./wave-slicing-spec.md), [findings/](./findings/)

---

## Execution Contract
This plan is executed with strict TDD (Red → Green → Break-it → Verify). Because this repo has no application runtime, "tests" are the repo's shell specs: the failing-test-first step means extending the relevant spec to assert the new artifact/route/content, confirming red, then making it green by creating the artifact and re-rendering `dist/`.

No canonical-skill or reference change is complete until `node tools/render-skills.mjs --write` has regenerated `dist/` and the drift gate in `./tests/run-tests.sh fast` passes.

---

## Change Summary
- **What changes:** A new OpenCode-only fast-lane execution mode is added as repo process artifacts — a `execution-orchestrator-team` skill and a `create-team-worklog` skill (+ template) — plus an optional per-task `Touched files` field in the plan template, Nix wiring, and process-doc updates.
- **What stays the same:** The sequential [execution-orchestrator](../../skills/execution-orchestrator/SKILL.md) and every other skill, agent, and Nix behavior are unchanged. Pi harness output is unaffected (the new skills are OpenCode-only). No new verification command surface is introduced.
- **Motivation:** Give users an opt-in way to execute independent plan tasks in parallel via OpenCode team mode, trading some rigor for wall-clock speed, while keeping the sequential mode as the maximum-rigor default.

## Goals
- [ ] A canonical `skills/execution-orchestrator-team/SKILL.md` exists, restricted to OpenCode, embedding the hybrid wave-execution process and the wave-slicing procedure as prose.
- [ ] A canonical `skills/create-team-worklog/SKILL.md` (+ `references/team-worklog-template.md`) exists, restricted to OpenCode, producing a wave-oriented team worklog.
- [ ] The plan template gains an optional per-task `Touched files` field (Task Graph column + Task Details line) per [wave-slicing-spec.md](./wave-slicing-spec.md) §2.1.
- [ ] `dist/` is regenerated and drift-clean; the two new skills render to the OpenCode tree only (never Pi).
- [ ] The new OpenCode-only skills are wired into `openCodeSkills` in `nix/modules/opencode/config.nix`.
- [ ] Process docs document the new mode as a peer to the sequential orchestrator.
- [ ] `./tests/run-tests.sh fast` passes; `./tests/run-tests.sh all` passes on a Nix/Pi host (see gate policy).

## Non-goals
- Implementing a runtime wave-slicer program (there is no application runtime; wave-slicing lives as prose the agent executes).
- Changing the sequential execution-orchestrator, execute-task, or create-worklog skills' behavior.
- Rendering the new skills for the Pi harness or adding them to the Pi skills list.
- Worktree-based git isolation (explicitly rejected; the mode uses shared-tree + single-committer).
- Removing the per-task break-it check from this plan's own execution (the "drop break-it" decision is a property of the feature being built, not of how we build it).

## Related Backlog Items
Items outside this plan's executable scope but relevant for context:
- Deferred (create in `docs/backlog.md` only if/when pursued): precise glob-vs-glob intersection for `Touched files`; a read-only file-set distinct from the write set; runtime rebalancing/pull-forward for uneven waves. These are recorded as Open Questions in the wave-slicing spec.

## Related Requirements
- Actors/personas: engineers running the execution process via OpenCode (`ACT-001` if applicable).
- Use cases: executing an approved plan to completion (`UC-001` if applicable).
- Workflows/scenarios: the Execution phase in `docs/orchestration.md`.
- Requirement refs: `FR-002` (canonical verification command surface — the wave gate reuses it), `OPR-001` (gate policy). No requirement mandates sequential-only execution.

## Requirement Updates
Approved requirement changes to apply during execution:

| Requirement change | Applied in task | Notes |
|--------------------|-----------------|-------|
| none | — | This plan adds process artifacts; it does not change canonical requirements. If review finds a requirement/ADR is warranted for a second execution mode, raise it for human approval rather than editing canonically here. |

## Impacted Surface Area
- **Entry points affected:** OpenCode `execute` mode gains an alternative execution skill; no CLI/API/UI runtime change.
- **Modules/components likely touched:** `skills/execution-orchestrator-team/`, `skills/create-team-worklog/`, `skills/create-plan/references/plan-template.md`, `dist/skills/opencode/*`, `dist/skills/pi/create-plan/*` (template re-render), `nix/modules/opencode/config.nix`, `docs/orchestration.md`, `docs/plan-directory-structure.md`, `README.md`, and the specs under `tests/specs/`.
- **External contracts affected:** The rendered `dist/` skill trees (consumed by the Nix modules) and the `openCodeSkills` list.

## Context
The design is fully documented in [approach.md](./approach.md) and [wave-slicing-spec.md](./wave-slicing-spec.md). Key repo mechanics that constrain this plan (from [docs/skill-rendering.md](../../docs/skill-rendering.md)):
- Canonical skills live in `skills/<name>/SKILL.md`, are harness-neutral, and MUST NOT contain a `compatibility:` frontmatter line (the renderer injects it). Harness-specific delegation uses `{{delegate:…}}` / `{{note:…}}` macros.
- A skill restricts itself to a harness with `harnesses: [opencode]` in frontmatter (precedent: `configure-opencode`).
- After any canonical change, run `node tools/render-skills.mjs --write` and commit `dist/`. `tests/specs/skill-render-spec.sh` (in `./tests/run-tests.sh fast`) fails on drift, unexpanded macros, wrong delegation syntax per harness, or wrong `compatibility` stamping.
- Team coordination uses OpenCode `team_*` tools described directly in prose; no new render roles/notes are expected in `harnesses/opencode.json` (confirm during T3).

## Constraints
- OpenCode team-mode bounds: max 8 members, max 4 parallel workers, 32KB/message, 256KB unread inbox (already configured in `nix/modules/opencode/config.nix` → `team_mode`).
- The new skills are OpenCode-only; the render spec asserts they are excluded from the Pi tree (mirroring `configure-opencode`).
- Do not invent verification commands; use only those in [docs/testing-strategy.md](../../docs/testing-strategy.md).
- Do not hand-edit `dist/`; route through the renderer.
- Preserve all existing spec assertions and doc anchors (see `tests/specs/repo-readiness-docs-spec.sh` and `repo-structure-spec.sh`).

## Assumptions
- The OpenCode-only skill pattern (`harnesses: [opencode]`) behaves for the new skills exactly as it does for `configure-opencode`.
- `bash`, `jq`, and `node` are available for the fast suite. `nix` and a completed `home-manager switch` are required for `./tests/run-tests.sh all` and may not be present in every execution environment (see Gate Policy).
- Separate `create-team-worklog` and `execution-orchestrator-team` skills are preferred over a mode-branch inside existing skills (resolves the approach's open question).

## Open Questions

| Question | Owner | Resolution |
|----------|-------|------------|
| Static waves written into `plan.md` by the planner vs. computed at execution time by the orchestrator | human/review | Default: computed at execution time from the task graph + `Touched files`; the plan template only supplies the input field. Revisit if reviewers want pre-computed waves recorded in the plan. |
| Is the final cross-wave review mandatory or optional in a max-speed sub-mode | human/review | Default: mandatory (documented in the skill). |
| Should a second execution mode be captured as an ADR | human | Raise during code review; do not author canonically without approval. |

## Risks & Mitigations

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Changing `plan-template.md` causes `dist/` drift and fails the fast gate | med | high | Each canonical/reference change re-renders `dist/` within the same task before its gate. |
| New OpenCode-only skill leaks into the Pi tree | med | low | T3 adds a render-spec assertion mirroring the `configure-opencode` exclusion; renderer honors `harnesses: [opencode]`. |
| `all`/`full` gates unavailable (no Nix/Pi host) | low | med | Gate policy `allow-scoped-completion`; the fast suite is the enforceable gate here and the `all` gate is run on a Nix host or flagged as a pre-merge follow-up. |
| Editing shared specs (`repo-structure-spec.sh`, etc.) across tasks causes churn | low | med | Sequence tasks so later ones depend on earlier ones that touch the same spec; keep additions additive. |
| Orchestrator skill accidentally uses Pi `subagent(` syntax | low | low | T3 content check + render-spec's OpenCode `subagent(`-absence assertion. |

## Decisions

| Decision | Options Considered | Chosen | Rationale | Consequences | Revisit If |
|----------|-------------------|--------|-----------|--------------|------------|
| Skill count/shape | One mega-skill; two skills (orchestrator + team worklog) | Two skills | Mirrors the sequential split (execution-orchestrator + create-worklog); each is independently loadable | Two canonical dirs + two dist renders | A single skill proves simpler to maintain |
| Harness scope | Both harnesses; OpenCode-only | OpenCode-only | `team_*` tools do not exist on Pi | Render excludes Pi tree; Pi list untouched | Pi gains a team primitive |
| Wave-slicing form | Executable code; skill-embedded prose | Skill-embedded prose | No application runtime in repo; skills are executed prose | Verified by structure/content specs, not unit tests | Repo gains a runtime for tooling |

## Work Plan

### Task Graph
| ID | Task | Depends on | Touched files | Deliverable | Verification | Status |
|---:|---|---|---|---|---|---|
| T1 | Add optional per-task `Touched files` field to the plan template | — | `skills/create-plan/references/plan-template.md`, `tests/specs/skill-content-spec.sh`, `dist/skills/pi/create-plan/references/plan-template.md`, `dist/skills/opencode/create-plan/references/plan-template.md` | Plan template documents the field; spec asserts it | `bash tests/specs/skill-content-spec.sh`; `bash tests/specs/skill-render-spec.sh`; `./tests/run-tests.sh fast` | ⬜ |
| T2 | Create `create-team-worklog` skill + team-worklog template (OpenCode-only) and wire into Nix | — | `skills/create-team-worklog/SKILL.md`, `skills/create-team-worklog/references/team-worklog-template.md`, `tests/specs/repo-structure-spec.sh`, `tests/specs/skill-content-spec.sh`, `nix/modules/opencode/config.nix`, `dist/skills/opencode/create-team-worklog/` | New skill renders OpenCode-only; installed via `openCodeSkills` | `bash tests/specs/repo-structure-spec.sh`; `bash tests/specs/skill-content-spec.sh`; `bash tests/specs/skill-render-spec.sh`; `./tests/run-tests.sh fast` | ⬜ |
| T3 | Create `execution-orchestrator-team` skill (OpenCode-only) embedding the wave process + wave-slicing prose; wire into Nix | T1, T2 | `skills/execution-orchestrator-team/SKILL.md`, `tests/specs/repo-structure-spec.sh`, `tests/specs/skill-content-spec.sh`, `tests/specs/skill-render-spec.sh`, `nix/modules/opencode/config.nix`, `dist/skills/opencode/execution-orchestrator-team/` | New orchestrator skill renders OpenCode-only; installed | `bash tests/specs/repo-structure-spec.sh`; `bash tests/specs/skill-render-spec.sh`; `./tests/run-tests.sh fast` | ⬜ |
| T4 | Document the mode in process docs | T2, T3 | `docs/orchestration.md`, `docs/plan-directory-structure.md`, `README.md`, `tests/specs/repo-readiness-docs-spec.sh` | Docs describe the team-mode alternative + team worklog artifact + `Touched files` | `bash tests/specs/repo-readiness-docs-spec.sh`; `bash tests/specs/repo-structure-spec.sh`; `./tests/run-tests.sh fast` | ⬜ |
| T5 | Final repo-wide gate + coverage confirmation | T1, T2, T3, T4 | `plans/2026_07_14_team_mode_wave_execution/worklog.md` | All gates green; coverage matrix satisfied | `./tests/run-tests.sh fast`; `./tests/run-tests.sh all` (Nix/Pi host) | ⬜ |

### Task Details

#### T1: Add `Touched files` field to the plan template
**Depends on:** —
**Deliverable:** `skills/create-plan/references/plan-template.md` documents an optional per-task `Touched files` field (Task Graph column + Task Details line) exactly as specified in [wave-slicing-spec.md](./wave-slicing-spec.md) §2.1; `skill-content-spec.sh` asserts its presence; `dist/` re-rendered.
**Requirement refs:** FR-002 (plan verification surface consistency)

**TDD checklist:**
- [ ] Add a failing assertion to `tests/specs/skill-content-spec.sh` that `skills/create-plan/references/plan-template.md` contains the string `Touched files`.
- [ ] Run `bash tests/specs/skill-content-spec.sh` — confirm failure (red).
- [ ] Edit `plan-template.md`: add a `Touched files` column to the Task Graph table and a `**Touched files:**` line to each Task Details block, with the guidance from spec §2.1 (explicit paths preferred; globs allowed; `(none)` for no-write tasks; omit only if unknown).
- [ ] Run `node tools/render-skills.mjs --write` to regenerate `dist/`.
- [ ] Run `bash tests/specs/skill-content-spec.sh` and `bash tests/specs/skill-render-spec.sh` — confirm pass (green).
- [ ] **Break-it check:** remove the `Touched files` line from the template, re-render, confirm `skill-content-spec.sh` fails, restore and re-render.
- [ ] Run task completion gate: `./tests/run-tests.sh fast`.

**Verification scope:**
- Fast feedback: `bash tests/specs/skill-content-spec.sh` — scope: touched-files
- Task completion gate: `./tests/run-tests.sh fast` — scope: package-wide

---

#### T2: Create `create-team-worklog` skill + template (OpenCode-only) and wire into Nix
**Depends on:** —
**Deliverable:** `skills/create-team-worklog/SKILL.md` (frontmatter `harnesses: [opencode]`, no `compatibility:` line) with a `references/team-worklog-template.md` implementing the wave-oriented worklog (wave manifest, per-wave board, append log, current-wave pointer) per [approach.md](./approach.md); added to `openCodeSkills` in `nix/modules/opencode/config.nix`; `dist/` re-rendered (OpenCode tree only).
**Requirement refs:** none

**TDD checklist:**
- [ ] Add failing assertions: in `tests/specs/repo-structure-spec.sh` add `create-team-worklog` to the `SKILLS` array (and bump the count comment); in `tests/specs/skill-content-spec.sh` add `create-team-worklog` to `SKILLS_WITH_REFS` and assert the SKILL.md references "wave".
- [ ] Run `bash tests/specs/repo-structure-spec.sh` and `bash tests/specs/skill-content-spec.sh` — confirm failure (red).
- [ ] Create `skills/create-team-worklog/SKILL.md` and `references/team-worklog-template.md`.
- [ ] Add `"create-team-worklog"` to `openCodeSkills` in `nix/modules/opencode/config.nix`.
- [ ] Run `node tools/render-skills.mjs --write`; confirm `dist/skills/opencode/create-team-worklog/` exists and `dist/skills/pi/create-team-worklog/` does NOT.
- [ ] Run the three specs — confirm pass (green).
- [ ] **Break-it check:** temporarily add a `compatibility: opencode` line to the canonical SKILL.md, re-render/`--check`, confirm `skill-render-spec.sh` fails ("canonical skills hardcode compatibility"), restore.
- [ ] Run task completion gate: `./tests/run-tests.sh fast`.

**Verification scope:**
- Fast feedback: `bash tests/specs/repo-structure-spec.sh` — scope: touched-files
- Task completion gate: `./tests/run-tests.sh fast` — scope: package-wide

---

#### T3: Create `execution-orchestrator-team` skill (OpenCode-only) and wire into Nix
**Depends on:** T1, T2
**Deliverable:** `skills/execution-orchestrator-team/SKILL.md` (frontmatter `harnesses: [opencode]`, no `compatibility:` line) embedding: the hybrid scope, the wave loop, the wave-slicing procedure as prose (from [wave-slicing-spec.md](./wave-slicing-spec.md)), the shared-tree single-committer git model, the in-team reviewer, break-it dropped by default, team spec/config guidance, closure discipline, convergence caps, and the mode-selection gate. It references `create-team-worklog` (T2) and the `Touched files` field (T1). Added to `openCodeSkills`; `dist/` re-rendered (OpenCode tree only).
**Requirement refs:** none

**TDD checklist:**
- [ ] Add failing assertions: in `tests/specs/repo-structure-spec.sh` add `execution-orchestrator-team` to `SKILLS`; in `tests/specs/skill-render-spec.sh` add assertions that `dist/skills/opencode/execution-orchestrator-team/SKILL.md` exists and `dist/skills/pi/execution-orchestrator-team` does NOT (mirroring the `configure-opencode` exclusion block); in `tests/specs/skill-content-spec.sh` assert the skill references `wave`, `team`, and `single committer`.
- [ ] Run the specs — confirm failure (red).
- [ ] Create `skills/execution-orchestrator-team/SKILL.md`. Use OpenCode `task(...)` / `team_*` prose; do NOT use the Pi `subagent(` token. Reuse existing `{{delegate:…}}` roles for the sequential plan-review/final-review steps if helpful; add no new roles unless the renderer requires one (if so, add to `harnesses/opencode.json` only).
- [ ] Add `"execution-orchestrator-team"` to `openCodeSkills` in `nix/modules/opencode/config.nix`.
- [ ] Run `node tools/render-skills.mjs --write`; confirm OpenCode-only render.
- [ ] Run the specs — confirm pass (green).
- [ ] **Break-it check:** temporarily change frontmatter to `harnesses: [pi]`, re-render, confirm the new render-spec assertion fails (skill would appear in the Pi tree / vanish from OpenCode), restore.
- [ ] Run task completion gate: `./tests/run-tests.sh fast`.

**Verification scope:**
- Fast feedback: `bash tests/specs/skill-render-spec.sh` — scope: touched-files
- Task completion gate: `./tests/run-tests.sh fast` — scope: package-wide

---

#### T4: Document the mode in process docs
**Depends on:** T2, T3
**Deliverable:** `docs/orchestration.md` gains a "Team-Mode Wave Execution (fast lane)" section documenting the alternative as a peer to the sequential orchestrator; `docs/plan-directory-structure.md` documents the team worklog artifact and the optional `Touched files` field; `README.md` skills table lists the two new skills (and the count is updated). A new assertion in `tests/specs/repo-readiness-docs-spec.sh` guards the orchestration.md section anchor.
**Requirement refs:** none

**TDD checklist:**
- [ ] Add a failing assertion to `tests/specs/repo-readiness-docs-spec.sh` that `docs/orchestration.md` contains the new section anchor (e.g. `## Team-Mode Wave Execution`).
- [ ] Run `bash tests/specs/repo-readiness-docs-spec.sh` — confirm failure (red).
- [ ] Update `docs/orchestration.md`, `docs/plan-directory-structure.md`, and `README.md`. Preserve every existing required anchor and do NOT introduce any string the spec's `assert_file_not_contains` checks forbid (e.g. the `agentOverrides` shorthand on line 235).
- [ ] Run `bash tests/specs/repo-readiness-docs-spec.sh` and `bash tests/specs/repo-structure-spec.sh` — confirm pass (green).
- [ ] **Break-it check:** rename the new anchor, confirm the readiness spec fails, restore.
- [ ] Run task completion gate: `./tests/run-tests.sh fast`.

**Verification scope:**
- Fast feedback: `bash tests/specs/repo-readiness-docs-spec.sh` — scope: touched-files
- Task completion gate: `./tests/run-tests.sh fast` — scope: package-wide

---

#### T5: Final repo-wide gate + coverage confirmation
**Depends on:** T1, T2, T3, T4
**Deliverable:** All gates green; every Coverage Matrix row has a satisfying assertion; the worklog records the final gate results.
**Requirement refs:** OPR-001 (gate roles)

**TDD checklist:**
- [ ] Run `./tests/run-tests.sh fast` — confirm pass.
- [ ] Run `./tests/run-tests.sh all` on a Nix/Pi host — confirm flake evaluation + proof-set pass. If no Nix/Pi host is available, record that `all` is deferred to a pre-merge follow-up per the gate policy and confirm `fast` is green.
- [ ] Confirm each Coverage Matrix row maps to a passing spec assertion.
- [ ] Record results in `worklog.md`.

**Verification scope:**
- Task completion gate: `./tests/run-tests.sh fast` — scope: package-wide
- Final plan gate: `./tests/run-tests.sh all` — scope: repo-wide (Nix/Pi host)

---

## Behavior / Coverage Matrix

| Behavior | Source of truth | Primary test layer | Negative/edge cases | Needs E2E? | Regression risk |
|----------|----------------|-------------------|---------------------|------------|-----------------|
| Plan template exposes `Touched files` | `skills/create-plan/references/plan-template.md` | `skill-content-spec.sh` | field removed → spec fails | no | low |
| `create-team-worklog` exists, OpenCode-only, has refs | canonical skill + `dist/` | `repo-structure-spec.sh`, `skill-content-spec.sh`, `skill-render-spec.sh` | hardcoded `compatibility:` → render fails; missing refs → content fails | no | med |
| `execution-orchestrator-team` exists, OpenCode-only | canonical skill + `dist/` | `repo-structure-spec.sh`, `skill-render-spec.sh`, `skill-content-spec.sh` | appears in Pi tree → render fails | no | med |
| New skills installed for OpenCode | `nix/modules/opencode/config.nix` | `repo-structure-spec.sh` (content assertion) + `flake-eval-spec.sh` (`all`) | missing from `openCodeSkills` → not installed | no | med |
| `dist/` stays drift-free after canonical changes | renderer + `dist/` | `skill-render-spec.sh` (`--check`) | stale dist → fast gate fails | no | high |
| Docs document the mode | `docs/orchestration.md` etc. | `repo-readiness-docs-spec.sh` | missing anchor → fails | no | low |

## Baseline Gate Audit
Before T1, run all package-wide gates to record baseline status (carry into the worklog).

| Command | Scope | Baseline status | Related failures? | Notes |
|---------|-------|-----------------|-------------------|-------|
| `./tests/run-tests.sh fast` | package-wide | ✅ pass / ❌ N failures | to record | Must be green before T1; if pre-existing failures exist, document them |
| `./tests/run-tests.sh all` | repo-wide | to record | to record | Requires `nix` + completed `home-manager switch`; may be deferred |

### Gate policy for this plan
**Policy:** allow-scoped-completion
**Rationale:** The repo-local `fast` suite (bash/jq/node) is the enforceable task and integration gate in any environment and covers every artifact this plan produces (structure, content, render drift, readiness docs). The `all`/`full` gates additionally require a Nix host and a completed `home-manager switch` for flake evaluation and Pi proof-set verification; where that host is unavailable, a task completes on its own scope passing `fast`, and the `all` gate is run on a Nix host or recorded as a required pre-merge follow-up. Unrelated pre-existing failures are documented, not fixed under this plan.

## Verification Plan

### Commands
| Command | Scope | When | What it proves |
|---------|-------|------|----------------|
| `bash tests/specs/<spec>.sh` | touched-files | During TDD loops | The touched spec's contract changed as intended |
| `./tests/run-tests.sh fast` | package-wide | Before each task completion | Structure, content, render drift, readiness docs all agree |
| `./tests/run-tests.sh all` | repo-wide | Before plan completion | Flake evaluation + Pi proof-set are trustworthy (Nix/Pi host) |

### Completion Criteria
- [ ] All tasks marked done
- [ ] `./tests/run-tests.sh fast` passes
- [ ] `./tests/run-tests.sh all` passes on a Nix/Pi host (or recorded as a pre-merge follow-up per gate policy)
- [ ] All coverage matrix rows have satisfying spec assertions
- [ ] `dist/` is drift-clean (`node tools/render-skills.mjs --check` exits 0)

## Tooling & Contract Plans
The new skills are versioned process artifacts consumed by the Nix modules through the render pipeline, so they carry contract obligations:
- **Versioned I/O contract:** The team worklog template is the durable artifact contract for team-mode execution; changes to it are reference-file changes that must be re-rendered and drift-checked.
- **Exit code policy:** N/A (no new executable); the relevant exit contract is `node tools/render-skills.mjs --check` (0 = drift-free, non-zero = stale) enforced by `skill-render-spec.sh`.
- **Determinism rules:** Rendering is deterministic; `dist/` must equal a fresh render. Skills are added to `openCodeSkills` in a stable position.
- **File/module skeleton:** `skills/execution-orchestrator-team/SKILL.md`; `skills/create-team-worklog/{SKILL.md,references/team-worklog-template.md}`; `dist/skills/opencode/<name>/…` (generated); `nix/modules/opencode/config.nix` (`openCodeSkills`).
- **Acceptance checklist:** new canonical skills exist with `harnesses: [opencode]` and no `compatibility:` line; `dist/` renders them OpenCode-only; specs updated and green; docs updated; `openCodeSkills` includes both.

## Compatibility & Migration
- **Backwards compatibility:** Additive only. The sequential orchestrator, the standard worklog, and Pi rendering are untouched. Existing plans without a `Touched files` field remain valid (the field is optional).
- **Forwards compatibility:** Plans authored with `Touched files` are ignored by the sequential mode and consumed by the team mode.
- **Migration steps:** None required; the new mode is opt-in.
- **Rollback strategy:** Revert the feature commits and re-run `node tools/render-skills.mjs --write`; removing the skills from `openCodeSkills` and `dist/` restores prior behavior.

---

## Implementation Notes (update during execution)

### Progress Log
- 2026-07-14: Plan created from approach + wave-slicing spec.

### Evidence Ledger
- (to be filled during execution)

### Deviations
- (none yet)

### Issues Encountered
- (none yet)

### Follow-ups
Do not add new executable tasks here. Capture accepted follow-ups in `docs/backlog.md` and reference their stable IDs.
- (none yet)
