# Approach: Team-mode wave execution

**Created:** 2026-07-14
**Plan:** ./brief.md
**Based on:** ./findings/

## Solution Model

### Guiding philosophy: a fast lane, not a replacement
This mode exists to make plan execution **faster**, accepting a deliberate reduction in rigor to get there. When a user wants the most in-depth process possible, they keep using the existing sequential [execution-orchestrator](../../skills/execution-orchestrator/SKILL.md) unchanged. Team-mode wave execution is an opt-in peer. Every design choice below is justified by throughput, and each rigor sacrifice is named explicitly rather than hidden.

### Scope boundary: only the implementation phase parallelizes
The artifact pipeline is inherently serial — each stage consumes the previous one's output. Only task execution has independent units. So the mode is a **hybrid**:

```
[SEQUENTIAL, unchanged]
  create-plan -> review-plan (loop) -> approval gate -> commit plan
  -> create-team-worklog -> commit worklog
        |
        v
[TEAM PHASE — new]
  spawn team once -> for each wave:
     slice wave -> create team tasks -> workers claim & implement in parallel (<=4)
     -> reviewer reviews live + at wave end -> lead resolves blockers
     -> lead runs wave gate once -> lead commits the wave -> update team worklog -> next wave
  -> close team (Closure Sequence)
        |
        v
[SEQUENTIAL, unchanged]
  final cross-wave review-code (loop, fix between) -> complete
```

### Components
- **Wave-slicing algorithm** — turns the plan task graph into an ordered list of waves, each a set of tasks that are dependency-satisfied, file-disjoint, and within the worker cap. Fully specified in [wave-slicing-spec.md](./wave-slicing-spec.md).
- **Team lead (orchestrator + single committer)** — the only agent that runs git. Slices waves, creates team tasks, resolves blockers, runs the wave gate, commits each wave, updates the team worklog, and closes the team. Does not implement tasks.
- **Implementation members** — up to 4 concurrent workers (`category="deep"` for backend/logic, `category="visual-engineering"` for UI). Each reads the `execute-task` skill file, claims one unblocked task, implements it in the shared tree with TDD-minus-break-it, runs its scoped fast tests, reports done, then re-checks the board.
- **Reviewer member** — a persistent `category="ultrabrain"` member that reads the `review-code` skill file and reviews each task's diff live as it completes, plus a combined end-of-wave review. Persistence is intentional: cross-wave context helps catch integration drift.
- **Team worklog** — a new wave-oriented durable artifact that replaces the single-`NEXT STEP` cursor with a per-wave board and log. Distinct from the sequential worklog.

### How they fit together (the wave loop)
1. **Slice** the next wave from the task graph (deps satisfied by *already-committed* waves; tasks file-disjoint within the wave; width ≤ 4). See the spec.
2. **Create team tasks** for the wave with `blockedBy` reflecting plan dependencies; workers claim unblocked tasks lowest-ID-first.
3. **Implement in the shared tree**, Red → Green → Verify (no break-it). Each worker announces its declared file set via `team_send_message`; if it discovers it must touch a file another active worker owns, they resolve it live or the lead reslots the loser to a later wave.
4. **Live review** — as each worker reports done, the reviewer reviews that task's changes; the worker fixes on the spot before the wave closes.
5. **End-of-wave review** — the reviewer reviews the combined wave diff for integration issues.
6. **Resolve blockers** — the lead assigns fixes for any open Blocker/Critical/Major findings (cap per wave), re-review.
7. **Wave gate** — the lead runs the package/repo-wide verification gate **once** for the wave (workers only ran scoped fast tests).
8. **Commit the wave** — the lead (single committer) commits all wave changes together, including the team worklog update, as `wave(N): <summary>`.
9. **Advance** — update the team worklog's current-wave pointer; go to the next wave. When all waves are done, close the team, then run the sequential final cross-wave review.

## Key Decisions

| Decision | Options Considered | Chosen | Rationale | Consequences | Revisit If |
|----------|-------------------|--------|-----------|--------------|------------|
| What parallelizes | Whole pipeline; implementation only | Implementation only (Step 5) | Only task execution has independent units; the rest is a serial artifact chain. | Plan/review/worklog/final review stay sequential and lead-driven. | A future need arises to parallelize independent research or multi-package planning. |
| Execution unit | Per independent task; per wave | Per **wave** | Speed comes from batching independent tasks and reviewing them together; per-task rigor is the sequential mode's role. | Commit and worklog granularity become per-wave, not per-task. | Per-task rollback granularity becomes a hard requirement. |
| Git model | Worktree-per-member + integration merge; shared tree + single committer; shared tree + selective per-task staging | **Shared tree + single committer (per-wave commit)** | Only one agent runs git → zero index races. No merge step. File conflicts surface live during the wave, not at integration. | Two workers editing the same file race at the content level; mitigated by file-disjoint slicing + live coordination. Coarser history. | Merge-based isolation is later shown to be cheaper than live conflict avoidance for a given workload. |
| Conflict detection | At commit/merge time; at wave-planning time | **At wave-planning time** via per-task declared file sets | "Identify conflicts earlier." File overlap becomes a slicing input rather than a late surprise. | The planner must declare per-task touched files; undeclared files are treated conservatively (exclusive). | A reliable content-level live-merge workflow removes the need for static disjointness. |
| Coordination substrate | Mutated shared worklog; team task list | **`team_task_list` (live) + team worklog (durable)** | A single `NEXT STEP` cannot express a parallel front; the task list already models `blockedBy`/`owner`. | New team worklog artifact; the sequential worklog is unchanged for the sequential mode. | Team mode gains a first-class durable log of its own. |
| Reviewer placement | Outside the team (fresh context each pass); inside the team (persistent) | **Inside the team, persistent** | Category members match today's review tier, so no quality loss; persistence adds cross-wave integration context the sequential fresh-context model lacks. | Mild review bias/context growth; bounded by teardown/respawn on very large plans. | Review bias measurably degrades findings, at which point fall back to fresh per-wave reviewers. |
| Break-it check | Keep; drop by default | **Drop by default** | It is the single largest per-task time cost. The reviewer's test-adequacy gate (tautological/source-reading/export-only detection) partially compensates. | Weaker per-test proof-of-behavior; explicitly the fast-lane trade. A max-rigor run should use the sequential mode. | Escaped defects trace to weak tests often enough to justify re-enabling it as an option. |
| Reviewer count | Always 1; scale with wave width | **1 default, up to 2 for wide waves** | One reviewer can bottleneck 4 simultaneous finishers; the end-of-wave review is the guaranteed catch-all. | Stays within the 8-member / 4-worker bounds. | Live review latency consistently gates wave completion. |
| Final review | Drop (per-wave reviews suffice); keep | **Keep (sequential)** | Cross-wave integration issues can escape per-wave reviews; a full-branch pass is a cheap safety net relative to a whole plan. | One sequential review pass after the team closes. | Measured redundancy with per-wave reviews makes it optional in a max-speed sub-mode. |

## What Changes vs What Stays
- **Changes:**
  - A new `execution-orchestrator-team` skill (fast-lane peer to the sequential orchestrator).
  - A new team worklog artifact (and either a `create-team-worklog` skill or a branch in `create-worklog`).
  - A per-task **Touched files** declaration added to the plan template's task graph and task details.
  - The wave-slicing algorithm as a specified, testable component.
  - Commit granularity in this mode: per-wave `wave(N): …` commits by a single committer.
- **Stays:**
  - The sequential execution orchestrator, its worklog, and its per-task atomic commits — unchanged and still the default/max-rigor path.
  - Plan creation, plan review, and approach review.
  - TDD as the implementation discipline (minus the break-it step in this mode only).
  - Backlog and requirement capture through documented repo mechanisms; local-only commits (no push).
  - Canonical verification sources (`docs/testing-strategy.md`, `plans/README.md`); this mode invents no new command surface.

## Configuration
A team is declared per plan run (inline or `~/.omo/teams/exec-<slug>/config.json`):

```json
{
  "name": "exec-<slug>",
  "lead": { "kind": "subagent_type", "subagent_type": "sisyphus" },
  "members": [
    { "name": "impl-1", "kind": "category", "category": "deep",
      "prompt": "Backend/logic worker. FIRST read the execute-task skill at <abs path> and follow it EXACTLY, EXCEPT skip the break-it step (this fast mode drops it). Read the team worklog and plan.md for context. Claim ONE unblocked team task (lowest ID first), implement with Red->Green->Verify in the shared working tree, run only your scoped fast tests, announce your declared file set to the team before editing, update your task's entry in the team worklog, set the task completed, and message the reviewer + lead. Do NOT run git. Do ONE task, then re-check the board." },
    { "name": "impl-2", "kind": "category", "category": "deep", "prompt": "…same…" },
    { "name": "impl-3", "kind": "category", "category": "deep", "prompt": "…same…" },
    { "name": "ui-1", "kind": "category", "category": "visual-engineering",
      "prompt": "Frontend/UI worker. Same discipline as impl-*, UI tasks only." },
    { "name": "reviewer", "kind": "category", "category": "ultrabrain",
      "prompt": "Reviewer. FIRST read the review-code skill at <abs path> and follow it. Review each task's diff live as workers report done, and the combined wave diff at wave end. Apply the test-adequacy gate strictly (this mode dropped break-it, so weak tests are your responsibility to catch). Report findings by severity to the lead. Do NOT modify code; do NOT run git." }
  ]
}
```

Notes: real concurrency is capped at 4 workers regardless of member count; route UI tasks to the `visual-engineering` member; keep plan review and the final code review OUT of the team (lead calls them sequentially, as today); the lead is the sole committer.

## Boundary Definitions
- The **lead** owns wave slicing, team-task lifecycle, all git operations, the wave gate, the team worklog, and team closure. It does not implement tasks or write code.
- **Implementation members** own exactly one claimed task at a time. They edit the shared tree, run scoped fast tests, and announce their file sets. They never run git and never touch `state.json`.
- The **reviewer** reads diffs and reports findings. It never modifies code, plan, worklog task list, or git state.
- The **wave-slicing algorithm** decides only *which tasks run together*. It does not execute, commit, or review.
- The **team worklog** is the durable record of wave composition and outcomes; the **team task list** is the live coordination cursor. Neither is a second source of verification/backlog/requirements policy.

## Design Tenets (non-negotiable even if details change)
- **Fast lane is opt-in** — the sequential mode remains the default and is never silently replaced.
- **One committer** — only the lead runs git, eliminating index races.
- **Conflicts are found at slicing time** — intra-wave tasks are file-disjoint by construction; overlaps serialize or are resolved live, never merged after the fact.
- **The task list is the parallel cursor** — no single mutable `NEXT STEP` in this mode.
- **Named rigor trades** — every dropped guarantee (break-it, per-task commits, fresh-context review) is explicit and recorded, so users can choose the sequential mode when they need it.
- **No new verification surface** — the wave gate uses the repo's canonical commands only.

## Invariants & Safety Properties
- Within any single wave, no two tasks declare overlapping file sets.
- Every task in wave *i* has all of its dependencies committed in waves 1..(i−1); there are no intra-wave dependencies.
- At most 4 implementation members are working concurrently.
- Only the lead commits, and each commit corresponds to exactly one completed, reviewed wave (plus its worklog update).
- The package/repo-wide gate runs exactly once per wave, by the lead, after integration of that wave.
- A wave is not committed while any of its tasks has an open Blocker/Critical/Major review finding.
- The team is always closed via the Closure Sequence once all waves are terminal (no lingering idle members).
- `state.json` is written only by the lead.

## Rigor Tradeoffs vs the Sequential Mode (explicit)
| Guarantee | Sequential | Team-mode (fast) | Compensation |
|-----------|------------|------------------|--------------|
| Break-it check per task | Yes | **No** (default) | Reviewer test-adequacy gate on every task. |
| Commit granularity | Per task (atomic) | Per wave | Waves are self-contained + tagged; bisect lands on a wave. |
| Review context | Fresh per pass | Persistent in-team + final fresh pass | Cross-wave integration awareness; final sequential review as net. |
| History determinism | Linear, deterministic | Wave order deterministic; intra-wave interleaving not | Deterministic slicing; per-wave commit hides interleaving. |
| Conflict handling | N/A (serial) | Live, worker-resolved | File-disjoint slicing minimizes occurrence. |

## Anticipated Issues & Pre-emptive Solutions
| # | Issue | Solution |
|---|-------|----------|
| 1 | Members can't `load_skills` → discipline lost | Member prompt requires reading the canonical skill file first (execute-task / review-code). |
| 2 | Concurrent git → index corruption/interleaving | Single committer (lead); members never run git. |
| 3 | Two workers edit the same file in the shared tree | File-disjoint wave slicing is the primary defense; residual overlaps are announced via messages and resolved live or reslotted. |
| 4 | Single `NEXT STEP` can't express a parallel front | `team_task_list` + `blockedBy` is the live cursor; team worklog is the durable per-wave log. |
| 5 | Concurrent test/build runs collide in the shared tree | Workers run only scoped/fast tests on their own paths; the authoritative package/repo gate runs once, by the lead, at wave end. |
| 6 | Worker A edits file X while worker B's test imports X | Primarily prevented by file-disjoint slicing; secondarily by scoping test runs to own paths. |
| 7 | Uneven wave (one long task, several short) → idle workers burn budget | Lead pulls a dependency-satisfied, file-disjoint task from a later wave forward, or shuts down idle members mid-wave. |
| 8 | One reviewer can't keep up with 4 finishers | Live reviews queue; end-of-wave review is the catch-all; allow a 2nd reviewer for wide waves. |
| 9 | Coarser per-wave history hurts rollback | Accepted trade; keep wave commits self-contained and tagged for clean revert. |
| 10 | Convergence caps under parallelism | Per-task fix cap (≤2) and per-loop review cap (≤5) retained; add a stuck-team timeout + "all remaining tasks blocked" escalation. |
| 11 | A member dies mid-task | Task stays claimed with no progress → lead reassigns to another member or itself; partial edits in the shared tree are inspected before reuse. |
| 12 | Long-lived members bloat context | Members do one task then re-read the board; for very large plans, tear down and respawn the team between wave-groups. |
| 13 | Lingering team burns budget | Closure invariant: after each terminal task update, if the Closure Contract holds, run the Closure Sequence in the same turn. |
| 14 | Backlog/requirement doc writes race | Route all backlog/requirement writes through the lead post-integration, never concurrently by members. |
| 15 | Overhead exceeds benefit on narrow graphs | Mode-selection gate: only use team mode when max wave width ≥ ~3 (parallelism score ≥ ~1.5); otherwise fall back to sequential. |
| 16 | Dropped break-it lets weak tests through | Reviewer applies the review-code test-adequacy gate strictly on every task's diff, live. |

## Deviation Protocol
If reality forces a change during a future build:
- **Preserve:** opt-in fast lane, single committer, slicing-time conflict detection, task-list-as-cursor, explicit rigor trades, canonical-only verification.
- **Can change safely:** member counts within bounds, exact prompts, team/artifact file names, wave commit message format, the parallelism-score threshold, and whether the team worklog is its own skill or a branch of `create-worklog`.
- **Record:** deviations in `plan.md` → Implementation Notes → Deviations.

## Open Questions (to resolve during planning)
- Glob-precision for file-set overlap (v1 uses conservative path/prefix checks — see spec).
- Static waves written into `plan.md` by the planner vs. waves computed at execution time by the orchestrator.
- Whether the final cross-wave review is mandatory or optional in a max-speed sub-mode.
- Team worklog as a new `create-team-worklog` skill vs. a mode branch inside `create-worklog`.
- Plan-size threshold for tearing down and respawning the team between wave-groups.
