# Implementation Plan: Pi Team Execution

**Status:** proposal — actionable checklist
**Date:** 2026-07-31
**Implements:** `pi-team-execution.md` (design) · `pi-team-execution-plan.html` (visual)
**Evidence:** `README.md` — measured baseline and extension evaluation ·
`notes/` — substrate findings from source inspection

Ordered so each phase de-risks the next. Phase 1 is now a single smoke test (the spikes it
replaced were resolved by source inspection); nothing irreversible happens before Phase 3.

---

## Phase 0 — Install & configure (~1 hour)

- [ ] **Install `pi-messenger`:** `pi install npm:pi-messenger`, then `/reload`.
- [ ] **Enable `pi-hooks` extensions:** `pi config` → enable `lsp` (agent-end diagnostics)
      and `checkpoint` (per-turn rollback refs). Note these apply to the **lead session**;
      reaching Crew workers requires adding the extension path to `crew-worker.md` frontmatter
      (path-like `tools` entries are passed through as `--extension`).
- [ ] **Watchdog:** enable on the lead session only. It does **not** cover Crew workers —
      `agent_end` deliberately ignores them — so it is not a quality control for task work.
- [ ] **Write the messenger config** (`~/.pi/agent/pi-messenger.json`, project override at
      `.pi/messenger/crew/config.json`):
      `concurrency.workers: 4` · `dependencies: "strict"` (default is `advisory`) ·
      `review.enabled: true`, `review.maxIterations: 3` · `work.maxAttemptsPerTask: 2` ·
      `artifacts.enabled: true`. Ready-to-paste block in `notes/reservations-and-config.md`.
- [ ] **Create and activate the Team profile** defining the lane roles `worker-cheap`,
      `worker-std`, `worker-complex`, `worker-visual`, each with its `model` (and `thinking`
      where wanted), plus `approval.mode: "risk-labels"` with our risk labels. **Verify it is
      active** — an inactive profile makes every lane silently fall back to the default model.
- [ ] **Override the reviewer:** copy `crew-reviewer.md` to `.pi/messenger/crew/agents/` and
      replace its criteria with ours (project-level agents override extension defaults by name).
- [ ] Pin versions of `pi-messenger` and `pi-subagents` — we depend on `plan.json`'s on-disk
      shape, so re-check that file after any upgrade.

## Phase 1 — Substrate verification (**spikes resolved by source inspection**)

All five original spikes were answered by reading `pi-messenger` v0.15.0 source rather than
running experiments — cheaper, faster, and more definitive. Findings with `file:line`
citations are in `notes/`.

| ID | Question | Outcome |
|---|---|---|
| S1 | Board without Crew's LLM planner? | **Feasible.** `task.create` takes `title`/`content`/`dependsOn`/`role`/`riskLabels`. Needs a `plan.json` record, which has no public non-LLM create action — we write that one file. `notes/board-materialization.md` |
| S2 | Auto-review feedback + our reviewer? | **Yes to both.** Feedback persists to `task.last_review` and is injected into the retry prompt; a project `crew-reviewer.md` overrides the packaged one. `notes/review-loop.md` |
| S3 | `resume` vs fresh remediation? | **Moot.** Crew workers run `--no-session`; resume does not exist. Retry is a fresh process carrying findings + progress log. `notes/crew-execution-model.md` |
| S4 | Do reservations block? | **Partially.** Structured `edit`/`write` only; **bash writes bypass entirely**; registry has no locking. Backstop, not a control. `notes/reservations-and-config.md` |
| S5 | Autonomous loop vs lead-driven waves? | **Not a conflict.** `work` runs exactly one wave; `autonomous: true` is opt-in. |

**Lane routing resolved.** `task.create` accepts no `model`, but it accepts `role`, and a Team
role carries `model` + `thinking` + `skills` (`crew/team/types.ts:13-17`), consumed at
`crew/handlers/work.ts:176-183`. Lanes are therefore Team roles, which keeps materialization
on the public API instead of direct store writes — removing the version-skew coupling this
plan previously accepted.

### The one remaining experiment

- [ ] **Smoke test (~20 min, throwaway repo).** Write `plan.json`, `task.create` ×5 in a
      diamond DAG across two lanes, activate the Team profile, run one `work` wave.
      Verifies the three things reading cannot establish: integration reality, dependency
      ordering under real concurrency, and that lane roles actually route models.
      **Fail ⇒ stop and reconsider the substrate before Phase 2.**

## Phase 2 — Build `pi-team` (repo-local extension/scripts)

Three small pieces, in order:

- [ ] **`plan-gates`** — the 4 mechanical checks against a `plan.md` task table:
      critical path ≤ 60% of serial · no task > 20% of critical path ·
      same-wave write-sets disjoint · every task packet self-sufficient (no dangling refs).
      Reuse `tools/critical-path.py` (already emits every verdict; wrap it with the
      write-set and self-sufficiency checks). Output: pass/fail + remedy hints. CLI-invokable.
- [ ] **`board-materializer`** — assert the Team profile is active (silent-degradation guard),
      write the `plan.json` record, then parse the plan's Tasks/Contracts/Decisions tables →
      `task.create` calls (deps from Deps col, `role` from the lane map, `riskLabels` from
      risk flags, packet body as task content, worker contract line injected).
- [ ] **`telemetry-harvest`** — read Crew task state, progress logs, the activity feed, and
      optional debug artifacts at close → emit the telemetry table (wall-clock, per-task time,
      defects-by-origin, rework share) into the plan directory as `telemetry.md`. Note Crew
      stores **no per-task cost**; source it separately or record the gap. **Must redact
      free-text task fields by default** — raw task text embeds plan paths, file names, and
      feature names.
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
- [ ] **`docs/pi-team-setup.md`** — Phase 0 install/config steps + preflight checklist
      (messenger installed, Team profile **active**, `dependencies: strict`, reviewer override
      in place, `.pi-subagents/` and `.pi/messenger/` ignored) so a new machine can be
      provisioned in minutes.
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
      — Crew records no per-task cost; compare wall-clock and task counts, and note the gap.
- [ ] **Acceptance criteria:** wall-clock ≤ 60% of a comparable sequential estimate ·
      zero write-set collisions · all defects caught at handoff or wave gate (none surviving
      to final review that a handoff reviewer should have caught) · human interruptions
      limited to intent, flagged approvals, and the summary. **Cost is deliberately not an
      acceptance criterion** — Crew records none, so a cost bound would be unfalsifiable.
      Track it out-of-band if a ceiling matters.
- [ ] Record results in `docs/issues_learnings.md`; fix the top friction points; only then
      execute the archive step in Phase 4.

## Explicitly deferred

- Cross-plan/epic parallelism (worktree-level; revisit `pi-dynamic-workflows` after Phase 5).
- OpenCode support (design is Pi-only; the render pipeline stays untouched until archived).
- Risk-tiering away any remaining verification rigor (only after live review is proven in
  Phase 5 — never remove a control before its replacement works).

## Dependency graph

```
Phase 0 ──► Phase 1 smoke test ──► Phase 2 ──► Phase 3 ──► Phase 5 ──► archive (Phase 4 tail)
                                      └──► Phase 4 docs (parallel with 3)
```
