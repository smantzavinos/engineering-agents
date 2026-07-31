# Implementation Plan: Pi Team Execution

**Status:** proposal — actionable checklist
**Date:** 2026-07-31
**Implements:** `pi-team-execution.md` (design) · `pi-team-execution-plan.html` (visual)
**Evidence:** `README.md` — measured baseline and extension evaluation

Ordered so each phase de-risks the next. Phases 1–2 are half-day spikes; nothing
irreversible happens before Phase 3.

---

## Phase 0 — Install & configure (~1 hour)

- [ ] **Install `pi-messenger`:** `pi install npm:pi-messenger`, then `/reload`.
- [ ] **Enable `pi-hooks` extensions:** `pi config` → enable `lsp` (agent-end diagnostics)
      and `checkpoint` (per-turn rollback refs).
- [ ] **Enable the subagents watchdog** on a strong complementary model:
      `/subagents-watchdog recommend-model` → `/subagents-watchdog model recommended` →
      `/subagents-watchdog on`.
- [ ] **Verify child session persistence** (`resume` depends on persisted `.jsonl` child
      sessions) and run `/subagents-doctor`.
- [ ] **Write the config block** (messenger config + `.pi/settings.json`):
      concurrency ≤ 4 · `review.enabled: true`, `review.maxIterations: 3` ·
      `work.maxAttemptsPerTask: 2` · `dependencies: strict` ·
      lane→model map (`cheap`/`std`/`complex`/`visual`) · run budgets
      (`timeoutMs`, `turnBudget`, `toolBudget`).
- [ ] Pin versions of `pi-messenger` and `pi-subagents` (Q5: version-skew risk).

## Phase 1 — Spikes (timeboxed ~half day each; kill or adjust the design on failure)

| ID | Question | Method | Pass criteria | Blocks |
|---|---|---|---|---|
| S1 | Can we materialize a board **without Crew's LLM planner**? | Throwaway repo: create plan record + `task.create` ×5 (diamond DAG, per-task `model`, `riskLabels`), run `work` | Tasks execute in dependency order on the assigned models | Phase 2–4 entirely |
| S2 | Does auto-review reset NEEDS_WORK **with feedback attached**, and can the reviewer prompt be ours? | Seed a deliberate defect; inspect `.pi/messenger/crew/` artifacts; override reviewer via `.pi/messenger/crew/agents/` | Retry receives findings; our review criteria applied | Reviewer skill |
| S3 | Does `subagent resume` beat a fresh remediation agent? | Same defect, both paths; compare `durationMs`/`totalCost` from `status.json` | Resume measurably cheaper/faster | Context rules |
| S4 | Do reservations block a second worker mid-run? Do sentinel paths work as resource locks? | Two workers with overlapping write sets; reserve `.locks/e2e` | Blocked worker gets holder's name; no corruption | Write-set enforcement |
| S5 | Does Crew's autonomous wave loop coexist with a lead-driven wave cycle? | Run one plan `autonomous: true`, one wave-by-wave | Clear winner chosen; no double-scheduling | Lead skill protocol |

Record outcomes in this file. **S1 failing means the substrate choice is wrong — stop and
reconsider a subagents-only design (board kept as a file the lead owns) before writing
anything else.**

## Phase 2 — Build `pi-team` (repo-local extension/scripts)

Three small pieces, in order:

- [ ] **`plan-gates`** — the 4 mechanical checks against a `plan.md` task table:
      critical path ≤ 60% of serial · no task > 20% of critical path ·
      same-wave write-sets disjoint · every task packet self-sufficient (no dangling refs).
      Reuse `tools/critical-path.py` (already emits every verdict; wrap it with the
      write-set and self-sufficiency checks). Output: pass/fail + remedy hints. CLI-invokable.
- [ ] **`board-materializer`** — parse the plan's Tasks/Contracts/Decisions tables →
      `task.create` calls (deps from Deps col, `model` from lane map, `riskLabels` from
      risk flags, packet body as task content, worker contract line injected).
- [ ] **`telemetry-harvest`** — read `.pi-subagents/**/status.json` + Crew artifacts at
      close → emit the telemetry table (wall-clock, cost, per-task time, defects-by-origin,
      rework share) into the plan directory as `telemetry.md`. **Must redact free-text task
      fields by default** — raw task text embeds plan paths, file names, and feature names.
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
      (`/subagents-doctor`, persistence check, watchdog status) so a new machine can be
      provisioned in minutes.
- [ ] **Update `AGENTS.md`** — route to the new process doc; mark the old pipeline docs as
      superseded for Pi.
- [ ] **Trim the three repo hooks** to their contracts: `docs/requirements.md`,
      `docs/testing-strategy.md` (broad = wave gate, targeted = worker loop; drop
      sequential-mode Red-Green-Break-Verify language), `docs/backlog.md` (unchanged).
- [ ] **ADR** — one ADR recording: Pi-only, team-only, conversation-first, sequential mode
      retired, substrate = subagents + messenger. Supersedes ADR 0002/0003 framing.
- [ ] **Archive, don't delete:** `docs/orchestration.md`, `docs/team-mode-execution.md`,
      OpenCode harness configs, and the ~14 retired skills move to an `archive/` (or a
      branch) after the calibration run passes — not before.

## Phase 5 — Calibration run & acceptance

- [ ] Pick a real, representative task (ideally the next cohort of a repeated-shape epic).
      Run it end-to-end: converse → `/pi-team-plan` → execute → close.
- [ ] Harvest telemetry with the Phase 2 `telemetry-harvest` tool; compare against the reported
      baseline in `README.md` (5.3 h active / $47.61 / 1.61x ceiling).
- [ ] **Acceptance criteria:** wall-clock ≤ 60% of a comparable sequential estimate ·
      cost ≤ 2x sequential · zero write-set collisions · all defects caught at handoff or
      wave gate (none surviving to final review that a handoff reviewer should have caught) ·
      human interruptions limited to intent, flagged approvals, and the summary.
- [ ] Record results in `docs/issues_learnings.md`; fix the top friction points; only then
      execute the archive step in Phase 4.

## Explicitly deferred

- Cross-plan/epic parallelism (worktree-level; revisit `pi-dynamic-workflows` after Phase 5).
- OpenCode support (design is Pi-only; the render pipeline stays untouched until archived).
- Risk-tiering away any remaining verification rigor (only after live review is proven in
  Phase 5 — never remove a control before its replacement works).

## Dependency graph

```
Phase 0 ──► S1 ──► S2..S5 ──► Phase 2 ──► Phase 3 ──► Phase 5 ──► archive (Phase 4 tail)
                                   └──► Phase 4 docs (parallel with 3)
```
