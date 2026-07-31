# Implementation Plan: Pi Team Execution

**Status:** proposal — actionable checklist
**Date:** 2026-07-31
**Implements:** `pi-team-execution.md` (design) · `pi-team-execution-plan.html` (visual)
**Evidence:** `README.md` — measured baseline and extension evaluation ·
`notes/` — substrate findings from source inspection

**Progress so far:** the five Phase 1 spikes are **resolved by source inspection** (see
`notes/`). Nothing has been installed or configured — `pi-messenger` is not installed, there
is no messenger config and no Team profile. Every checkbox below is still open.

**Repo constraint:** Pi is installed and configured **declaratively via the Nix flake +
home-manager**, not by `pi install` / `pi config`. Phase 0 uses a deliberately temporary
imperative install to run the kill gate; Phase 1b converts it into a flake declaration. See
"Nix constraints" under Phase 0.

Ordered so each phase de-risks the next. Phase 1 is a **kill gate**, but most of it is now
upstream's own test suite rather than a live run — deterministic and free. Only the minimum
setup the residual live check needs happens before it.

---

## Phase 0 — Declare the minimum the gate needs

**This repo installs Pi declaratively via a Nix flake + home-manager.** `pi install ...` and
`pi config` are the wrong verbs here — see "Nix constraints" below. Phase 0 is deliberately
minimal: everything required to run the Phase 1 live check, nothing else. If the gate fails,
this is all that was spent.

- [ ] **Gate-only install (temporary, imperative).** Run `pi install npm:pi-messenger` *without*
      touching the flake. Rationale: the gate may reject the substrate outright, and a rejected
      dependency should never have entered the reproducible declaration. Record that this is
      deliberate, temporary, and machine-local; `pi uninstall` reverts it.
      **Do not commit anything in `nix/` at this stage.**
- [ ] **Create a two-lane Team profile** — `worker-cheap` and `worker-std` with distinct models,
      enough to prove lane routing works. **Verify it is active** [SUB-2b]. This lives in
      messenger's own config, which is not Nix-managed (see below).

### Nix constraints this plan must respect

| Constraint | Consequence for this plan |
|---|---|
| Packages are declared in `nix/modules/pi/default.nix` (`piPackages`) and installed by the home-manager activation script | A permanent `pi install` is invisible to the flake: unpinned, unreproducible, absent from a new machine. Post-gate adoption **must** be a declaration, not a command. |
| Activation does **not** prune undeclared packages | An imperative install silently persists and appears to work — the failure is deferred to the next machine. This is why the temporary install above must be explicitly reverted or promoted. |
| `settings.json` is **merged with Nix winning** (`jq -s '.[0] * .[1]'`, Nix second) | Hand-editing any Nix-managed settings key is silently reverted on the next `home-manager switch`. Pi-level settings changes must go in the module. |
| Pi's `packages` list is generated from `piRuntimePackageIds` | A declared package is wired into Pi automatically; an imperatively installed one is not necessarily registered the same way. **Verify parity after promotion** rather than assuming it. |
| `lsp.hookMode = "agent_end"` is **already set** declaratively | The old "enable `lsp` via `pi config`" step was redundant and wrong. Dropped. |
| Git-source packages must pin a 40-hex commit; `tests/fixtures/proof-set.json` updates in the same change (`nix/AGENTS.md`) | "Pin versions" is a repo contract with a test, not a reminder. Spelled out in Phase 1b. |

## Phase 1 — Verify the substrate: tests first, then a narrow live check

The five original spikes were answered by reading `pi-messenger` v0.15.0 source rather than
running experiments — cheaper, faster, and more definitive. Findings with `file:line`
citations are in `notes/`.

| ID | Question | Outcome |
|---|---|---|
| S1 | Board without Crew's LLM planner? | **Feasible.** `task.create` takes `title`/`content`/`dependsOn`/`role`/`riskLabels`. Needs a `plan.json` record we write directly [SUB-3]. |
| S2 | Auto-review feedback + our reviewer? | **Yes to both.** Findings are injected into the retry prompt [SUB-6]; a project `crew-reviewer.md` overrides the packaged one. |
| S3 | `resume` vs fresh remediation? | **Moot.** Resume does not exist for Crew workers [SUB-1]. |
| S4 | Do reservations block? | **Partially** — backstop, not a control [SUB-4]. |
| S5 | Autonomous loop vs lead-driven waves? | **Not a conflict.** `work` runs exactly one wave; `autonomous: true` is opt-in. |

**Lane routing resolved.** Lanes are Team roles [SUB-2], which keeps materialization on the
public API instead of direct store writes — removing the version-skew coupling this plan
previously accepted.

What reading cannot establish, the **upstream test suite can** — and does, far better than the
integration smoke test originally planned here. `pi-messenger` v0.15.0 ships 408 tests that run
in ~1.4 s with no model spend, including one (`team-work.test.ts:94`) that executes this
design's exact materialization path and asserts the lane role's model reaches the spawned
worker. See "Verified by upstream's own test suite" in `notes/README.md`.

- [ ] **Run the upstream suite at our pinned version** (`npm install && npx vitest run` in a
      clone). Confirms the substrate contract deterministically. Expect 408/408.
      **Regressions here ⇒ stop; do not pin that version.**
- [ ] **Narrow live check (~10 min).** The suite mocks `spawnAgents` and uses placeholder model
      strings, so three things remain unproven: that the *npm-installed build* matches the
      source tree, that our real provider/model IDs resolve, and behavior under real
      concurrency. Create a two-task board through the `pi_messenger` tool with two lanes and
      run one wave. **Fail ⇒ stop.** `pi uninstall pi-messenger` reverts; nothing has entered
      `nix/`.

## Phase 1b — Adopt into the flake, then configure (only after the gate passes)

The gate has proven the substrate. Now make it reproducible — this is the step that converts a
local experiment into repo state.

- [ ] **Declare `pi-messenger` in `nix/modules/pi/default.nix`** under `piPackages`, following
      the existing shape (`source.type`, `packageName`, `spec`, `installSpec`). Use a pinned
      npm version (`pi-messenger@<version>`) or a 40-hex commit for a git source — never a
      branch or tag ref, which defeats the no-change rebuild skip (`nix/AGENTS.md`).
- [ ] **Update `tests/fixtures/proof-set.json` in the same change** if the package ships
      extensions/skills/themes, with its `resourceExpectations`. This is an enforced contract
      (`tests/specs/proof-set-runtime-spec.sh`), not a formality.
- [ ] **Run `home-manager switch`**, then confirm the declared install replaced the temporary
      one and that `pi-messenger` appears in the generated `packages` list. Re-run the Phase 1
      live check once to confirm declared-install parity [SUB-8] — cheap, and it catches the
      case where the imperative and declared installs behave differently.
- [ ] **Add `checkpoint` to the module's Pi settings** if wanted (per-turn rollback refs).
      `lsp` is already configured declaratively (`hookMode = "agent_end"`) — nothing to do.
      Note both apply to the **lead session**; reaching Crew workers requires adding the
      extension path to `crew-worker.md` frontmatter.
- [ ] **Watchdog:** enable on the lead session only. It does **not** cover Crew workers
      [SUB-1], so it is not a quality control for task work.
- [ ] **Write the messenger config** — `~/.pi/agent/pi-messenger.json`, project override at
      `.pi/messenger/crew/config.json`:
      `concurrency.workers: 4` · `dependencies: "strict"` (default is `advisory`) ·
      `review.enabled: true`, `review.maxIterations: 3` · `work.maxAttemptsPerTask: 2` ·
      `artifacts.enabled: true`. Ready-to-paste block in `notes/reservations-and-config.md`.
      **These paths are not Nix-managed.** Decide explicitly: leave machine-local (simple, but
      a new machine starts unconfigured) or bring under the module (reproducible, more wiring).
      Prefer the project-level override — it is version-controlled with the repo.
- [ ] **Complete the Team profile** — add `worker-complex` (with `thinking`) and
      `worker-visual`, plus `approval.mode: "risk-labels"` with our risk labels.
- [ ] **Override the reviewer:** copy `crew-reviewer.md` to `.pi/messenger/crew/agents/` and
      replace its criteria with ours (project-level agents override extension defaults by name).
- [ ] Re-check `plan.json`'s on-disk shape [SUB-3] after any `pi-messenger` version bump.

## Phase 2 — Build `pi-team` (repo-local extension/scripts)

Three small pieces. **`pi_messenger` is a Pi tool, not a CLI** [SUB-7], which decides what can
be a script and what cannot:

- [ ] **`plan-gates`** — a real script (pure file analysis, no messenger involvement): the 4
      mechanical checks against a `plan.md` task table:
      critical path ≤ 60% of serial · no task > 20% of critical path ·
      same-wave write-sets disjoint · every task packet self-sufficient (no dangling refs).
      Reuse `tools/critical-path.py` (already emits every verdict; wrap it with the
      write-set and self-sufficiency checks). Output: pass/fail + remedy hints. CLI-invokable.
- [ ] **`board-materializer`** — **not a script** [SUB-7]. Board creation happens inside a Pi
      session as `pi_messenger` tool calls, so this is lead-agent behavior specified in the
      `pi-team-lead` skill: assert the Team profile is active [SUB-2b], ensure the plan record
      exists [SUB-3], then walk the plan's Tasks/Contracts/Decisions tables issuing
      `task.create` calls (deps from Deps col, `role` from the lane map [SUB-2], `riskLabels`
      from risk flags, packet body as task content, worker contract line injected). A helper
      script may *parse the plan and emit the intended calls* for the lead to execute, but it
      cannot make them itself.
- [ ] **`telemetry-harvest`** — a real script (plain reads of `.pi/messenger/crew/`): task
      state, progress logs, the activity feed, and optional debug artifacts at close → emit the
      telemetry table (wall-clock, per-task time, defects-by-origin, rework share) into the plan
      directory as `telemetry.md`. Crew stores no per-task cost [SUB-5]; source it separately or
      record the gap. **Must redact free-text task fields by default** — raw task text embeds
      plan paths, file names, and feature names.
- [ ] Later, optional: lane auto-suggestion from write-set globs
      (`*.tsx` → `visual`, `**/migrations/**` → `complex` + `riskLabels`).

## Phase 3 — Write the 5 skills (replacing ~19)

All under `skills/` (or `.pi/skills/` if we keep them repo-local first — decide at Phase 3
start; repo-local is safer for iteration).

| Skill | Frontmatter | Content |
|---|---|---|
| `/pi-team-plan` | `disable-model-invocation: true` | The pivot: create `plans/<date>-<slug>/`, freeze conversation → `plan.md` (Intent · Contracts · Decisions · Checks · Tasks template inline), run `plan-gates`, approval only if risk-flagged/requested, then hand to `pi-team-lead` |
| `/discovery` | `disable-model-invocation: true` | Slimmed Socratic mode (adapt from existing `discovery` skill, cut artifact ceremony) |
| `/design` | `disable-model-invocation: true` | Slimmed option-comparison + throwaway scout fanout (adapt from existing `design`; output to chat, not files) |
| `pi-team-lead` | model-discoverable | Execution protocol: materialize board → dispatch → event table (§07 of the HTML) → wave gate + commit → escalation ladder → close sequence |
| `pi-team-worker` | injected into packets, not discoverable | Claim/reserve/implement/check/handoff(≤15 lines)/release contract; never commit, never broad suites |

Keep each skill under ~150 lines. State every rule once; the lead skill links to the plan
template rather than restating it.

## Phase 4 — Documentation

New/replacing docs in this repo:

- [ ] **`docs/pi-team-execution.md`** — promote the design doc from the investigation dir
      (near-verbatim). This is the canonical process doc.
- [ ] **`docs/pi-team-setup.md`** — the Phase 0 + 1b steps + preflight checklist (declared in
      `piPackages`, `home-manager switch` applied, Team profile **active**,
      `dependencies: strict`, reviewer override in place, `.pi-subagents/` and `.pi/messenger/`
      ignored). Since install is declarative, provisioning a new machine is
      `home-manager switch` plus the non-Nix messenger config — call out exactly which parts
      are *not* reproducible.
- [ ] **Update `AGENTS.md`** — route to the new process doc; mark the old pipeline docs as
      superseded for Pi.
- [ ] **Trim the three repo hooks** to their contracts: `docs/requirements.md`,
      `docs/testing-strategy.md` (broad = wave gate, targeted = worker loop; drop
      sequential-mode Red-Green-Break-Verify language), `docs/backlog.md` (unchanged).
- [ ] **ADR** — one ADR recording: Pi-only, team-only, conversation-first, sequential mode
      retired, substrate = `pi-messenger` Crew for execution with `pi-subagents` lead-side
      only. Supersedes ADR 0002/0003 framing.
- [ ] **Archive, don't delete:** `docs/orchestration.md`, `docs/team-mode-execution.md`,
      OpenCode harness configs, and the ~14 retired skills move to an `archive/` (or a
      branch) after the calibration run passes — not before.

## Phase 5 — Calibration run & acceptance

- [ ] Pick a real, representative task (ideally the next cohort of a repeated-shape epic).
      Run it end-to-end: converse → `/pi-team-plan` → execute → close.
- [ ] Harvest telemetry with the Phase 2 `telemetry-harvest` tool; compare against the reported
      baseline in `README.md` (5.3 h active / 1.61x ceiling). **Cost is not directly comparable**
      [SUB-5]; compare wall-clock and task counts, and note the gap.
- [ ] **Acceptance criteria:** wall-clock ≤ 60% of a comparable sequential estimate ·
      zero write-set collisions · all defects caught at handoff or wave gate (none surviving
      to final review that a handoff reviewer should have caught) · human interruptions
      limited to intent, flagged approvals, and the summary. **Cost is deliberately not an
      acceptance criterion** [SUB-5] — a cost bound would be unfalsifiable. Track it
      out-of-band if a ceiling matters.
- [ ] Record results in `docs/issues_learnings.md`; fix the top friction points; only then
      execute the archive step in Phase 4.

## Explicitly deferred

- Cross-plan/epic parallelism (worktree-level; revisit `pi-dynamic-workflows` after Phase 5).
- OpenCode support (design is Pi-only; the render pipeline stays untouched until archived).
- Risk-tiering away any remaining verification rigor (only after live review is proven in
  Phase 5 — never remove a control before its replacement works).

## Dependency graph

```
Phase 0 (temp install) ──► Phase 1 UPSTREAM TESTS + narrow live check ──► Phase 1b (declare in nix + configure) ──► Phase 2 ──► Phase 3
                            │  kill gate (408 tests, ~1.4s, free)                                                        │
                            └─ fail ⇒ pi uninstall, stop.               ┌───────────────────────────────────────┘
                               nix/ never touched                      ▼
                                                       Phase 5 ──► archive (Phase 4 tail)
                                                          ▲
                                           Phase 4 docs ───┘ (parallel with 3)
```
