# Pi Team Execution — design & rollout

A redesign of how plans get executed in Pi: conversation-first, one plan artifact, a small
parallel team with review-on-handoff. Replaces the Discovery/Design/Execute pipeline and
sequential mode.

| File | What it is |
|---|---|
| `pi-team-execution.md` | **The design.** Roles, lifecycle, event model, context rules. Start here. |
| `pi-team-execution-plan.html` | Visual companion — sequence diagrams, trigger taxonomy, model tiers. |
| `implementation-plan.md` | The rollout checklist: install, spikes, build, skills, docs, calibration. |
| `notes/` | Substrate findings from `pi-messenger` source inspection, with `file:line` citations. |

Supporting tooling produced by this work lives in `tools/` (see Analysis tools below), not
here, because this directory is staging. Per `implementation-plan.md` Phase 4,
`pi-team-execution.md` is promoted to `docs/pi-team-execution.md` once the calibration run
passes, and this directory is archived.

---

## Evidence base

One production sequential-mode plan (18 tasks) was measured end to end: **5.3 h active
wall-clock, $47.61, 33 subagent runs**. The findings below are what the design responds to.
The subject repo is private; project, plan, file, and commit identifiers are omitted, and the
per-run telemetry CSV is deliberately not committed. Figures are reported, not third-party
reproducible.

**1. Parallelism alone could not have fixed it.** Measured critical path was 95 min against
153 min serial — a hard ceiling of **1.61x** regardless of team size. Two packets (UI, E2E)
were 49% of the critical path; the last three dependency levels held one task each. Cause:
layered decomposition (schema → adapters → API → UI → E2E), where each layer depends on the
*implementation* of the one below.
→ *Design response: acceptance contracts decouple layers; four mechanical plan gates block
approval on fat packets and single-task tail waves.*

**2. Every significant defect was found by review or E2E. None by per-task break-it TDD.**

| Defect | Found by | Would per-task unit TDD have caught it? |
|---|---|---|
| Authorization bypass in a hierarchical view guard | step review | No — tests passed |
| Ordering defect: resolve-before-validate | final review | No — tests passed |
| State-transition gating gap | E2E test | Yes (integration level) |
| "A field is load-bearing" assumption | break-it step | Confirmed *test quality*; found no defect |

Rework was **27% of subagent time**, and the ordering defect was introduced in T7 but not
caught until after T18.
→ *Design response: review fires on every handoff, not at plan end. Per-task break-it is
retired in favour of contracts + handoff review + wave gates.*

**3. Verification cost is concentrated, not uniform.** ~7.5 gate invocations per task,
≈21–24% of implementer time — but backend gates cost 4–13 s warm while frontend lint cost
52 s and one E2E spec ~7.4 min. The two packets that ran expensive profiles inside their own
loop became the two largest packets on the critical path.
→ *Design response: profiles carry measured cost; only inner-loop-safe profiles run in a
worker; expensive profiles are lead-owned wave gates.*

**4. Cheap-model routing works.** Cheap-lane tasks averaged 5.4 min / ~$0.60 against 15 min /
~$3.10 for the standard lane, with no quality regression attributable to the cheap lane.
→ *Design response: three model tiers routed by plan lane tag; target ≥50% of tasks on cheap.*

**5. Rework is mostly re-discovery.** A remediation agent starting fresh re-reads the plan,
re-locates files, and re-derives a mental model before changing a few lines.
→ *Design response: the retry carries the review findings and the worker's own progress log
rather than starting cold. (An earlier draft resumed the original session; source inspection
later showed Crew workers run `--no-session`, so resume is unavailable — see `notes/`.)*

> **A caution worth keeping.** An earlier draft reported gate cost at 45–59% of implementer
> time from 25 s/64 s measurements. Those were cold-cache first invocations; warm re-runs gave
> 4 s/13 s and the finding was revised down to 21–24%. The original number would have sent
> effort toward warm-runner infrastructure for a fraction of the predicted return. Measure
> twice, and record cache state.

---

## Extension evaluation

Verdicts from surveying the Pi ecosystem for a coordination substrate:

| Package | Verdict | Why |
|---|---|---|
| **`pi-subagents`** | **Adopt** (installed) | Spawn/resume/steer, worktrees, budgets, intercom, durable lifecycle artifacts, edit-gated watchdog. **Used lead-side only** — see the correction below. Cannot provide a durable board or file locks. |
| **`pi-messenger`** | **Adopt** | The only candidate with a dependency-ordered task board *and* file reservations that block *and* a built-in review-on-handoff loop with retry-with-feedback. Cross-process (file-based). `task.create` accepts `dependsOn`, `role`, and `riskLabels`, so our plan DAG can be projected onto the board without running its own planner. |
| **`pi-hooks`** | **Adopt** (lsp, checkpoint) | Free per-edit diagnostics; per-turn rollback refs. |
| `pi-dynamic-workflows` | **Defer** | Excellent deterministic wave engine with journaled edited-script replay — best fit for epic-level repeated cohorts. Revisit after single-plan team mode works. |
| `@gjczone/pi-swarm` | **Decline** | Redundant second spawner alongside `pi-subagents`; no task board or DAG. Its pattern/keyword auto-routing idea is worth stealing separately. |
| `@pi-unipi/subagents` | **Decline** | Different harness ecosystem (`~/.unipi/`); dominated by `pi-subagents` except for file locking, which `pi-messenger` does better. |

Two runtime constraints that shaped the design:

- **The lead cannot be a subagent.** Child sessions don't get the `subagent` tool by default
  and nesting is depth-bounded — so the team lead must be the primary Pi session.
- **Forking strips Anthropic thinking blocks** and forces child thinking to `off`, which is
  why workers get a fresh packet rather than a forked context.

> **Correction from source inspection.** This table was written before reading
> `pi-messenger`'s source, and its division of labour was wrong. Crew spawns its own
> `pi --mode json --no-session` workers and explicitly does not launch `pi-subagents`
> (`crew/handlers/plan.ts:599`). `pi-subagents` is therefore **not** the execution primitive
> for task work; it is used lead-side only, for rescuing blocked tasks and the final review.
> That also removes worker session resume, watchdog coverage over workers, and `status.json`
> cost telemetry. Full findings with citations: `notes/`.

**On watching for code changes:** review triggers on *handoff*, not on commit. In this design
the lead is the only committer and commits happen at wave gates, so commit-triggered review
would fire at almost exactly the moment wave-gate review already does — the late feedback that
let the ordering defect survive T7→T18. Timed polling is banned outright.

---

## Analysis tools

Promoted to `tools/` as live repo tooling; `implementation-plan.md` Phase 2 builds on them.

| Script | Use |
|---|---|
| `tools/critical-path.py` | Critical path, wave structure, threshold verdicts from a DAG spec. Backs the plan gates. |
| `tools/measure-gate-cost.sh` | Wall-clock vs runner-reported time per verification profile. Run twice — first invocation is cold. |
| `tools/examples/baseline-dag.json` | The measured 18-task DAG behind finding 1. Fixture and worked example. |

```bash
python3 tools/critical-path.py tools/examples/baseline-dag.json
```

A third script aggregated per-run subagent telemetry into the figures above. It is not
retained: it read an artifact layout from the subject repo's pi-subagents version that cannot
be verified against current releases, and Phase 2 specifies a fresh `telemetry-harvest` built
against the documented `status.json` / `events.jsonl` lifecycle artifacts. Whatever replaces
it must redact free-text task fields by default — raw task text embeds plan paths and feature
names, which is what forced the redaction of this investigation's own data.
