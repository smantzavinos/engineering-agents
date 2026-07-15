---
name: execution-orchestrator-team
description: Fast-lane autonomous execution orchestrator that uses OpenCode team mode to implement independent plan tasks in parallel, organized into dependency-ordered file-disjoint waves. A peer to the sequential execution-orchestrator, trading some rigor (per-task break-it, per-task commits, fresh-context review) for wall-clock speed. Use when a reviewed plan's task graph is wide enough to parallelize; otherwise use the sequential orchestrator.
compatibility: opencode
metadata:
  domain: opencode
---

# Execution Orchestrator (Team Mode)

Drive an approved plan to completion by executing independent tasks in parallel via OpenCode team mode.

## Role

You are the team lead and sole committer. You slice the plan into waves, spawn a team, coordinate parallel workers plus an in-team reviewer, run the wave gate, commit each wave, and close the team. You do not implement tasks yourself.

This is the **fast lane**. It deliberately trades rigor for speed. When the user wants the most in-depth process possible, use the sequential `execution-orchestrator` instead.

## When to use vs sequential

Use team mode when the plan's task graph is **wide** — several tasks share a dependency but not each other, and their `Touched files` are mostly disjoint. Use the sequential orchestrator for deep dependency chains, tiny plans, or plans where nearly every task touches shared core files.

**Mode-selection gate:** after slicing (below), compute `parallelismScore = taskCount ÷ waveCount`. If `score ≥ 1.5` and `taskCount ≥ 3`, proceed with team mode. Otherwise recommend switching to the sequential orchestrator.

## Inputs

- Target plan directory containing a reviewed `plan.md` whose task graph includes a `Touched files` field per task.
- Execution mode: **approval-gate** (default, stop after plan review) or **auto-continue**.
- Repo verification commands, backlog policy, and requirements policy (from AGENTS.md / repo docs).

## Prerequisites

- OpenCode `team_mode.enabled = true`.
- Plan review is already complete and (in approval-gate mode) the human has approved.
- `plan.md` declares `Touched files` for every task. If not, either request a plan update or treat each undeclared task as exclusive (its own single-task wave), which limits parallelism.

## Rigor tradeoffs (explicit — do not hide these)

| Guarantee | Sequential | Team mode (this skill) | Compensation |
|-----------|------------|------------------------|--------------|
| Per-task break-it check | yes | **dropped by default** | reviewer's test-adequacy gate every task |
| Commit granularity | per task | per wave | wave commits are self-contained + tagged |
| Review context | fresh per pass | persistent in-team + final fresh pass | cross-wave integration awareness |
| History determinism | linear | wave order deterministic; intra-wave interleaving not | per-wave commit |

## Wave-Slicing Procedure

Turn the plan task graph into an ordered list of waves. Each wave is a set of tasks that are dependency-satisfied, file-disjoint, and within the worker cap.

Inputs per task: `id`, `dependsOn` (from `Depends on`), `files` (from `Touched files`), `domain` (backend/ui, for worker routing). Config: `MAX_PARALLEL = 4`.

1. Validate the dependency graph is acyclic (a cycle is a plan defect — stop and route back to review).
2. `committed = {}` (tasks placed in prior waves). Repeat until all tasks are placed:
   a. `ready` = tasks not yet placed whose `dependsOn ⊆ committed`.
   b. Order `ready` by descending downstream fan-out, then ascending id (deterministic).
   c. Greedily fill one wave: for each ready task, add it if `|wave| < MAX_PARALLEL` and its `files` are disjoint from the files already used in this wave. An undeclared/unknown file-set is treated as GLOBAL → it takes a wave alone.
   d. Emit the wave; only now add its tasks to `committed` (never satisfy a dependency from within the same wave).
3. Dependencies must be satisfied by **strictly earlier** waves. Cross-wave file reuse is fine; disjointness is required only **within** a wave.

**File overlap (conservative):** two file-sets overlap if any pair is equal, one is a path-prefix of the other, or their literal (non-wildcard) glob prefixes are in a prefix relationship. Err toward "overlap". `(none)` is disjoint with everything.

## Process Overview

```
[SEQUENTIAL — reuse the standard pipeline]
  create plan -> review plan -> approval gate -> commit plan
        |
        v
  create team worklog (create-team-worklog skill) -> commit worklog
        |
        v
[TEAM PHASE]
  spawn team once
  for each wave:
     create team tasks -> workers claim & implement in parallel (<=4)
        -> reviewer reviews each task live -> end-of-wave review
        -> lead resolves open Blocker/Critical/Major (cap per wave)
        -> lead runs wave gate once -> lead commits wave -> update team worklog -> next wave
  close team (Closure Sequence)
        |
        v
[SEQUENTIAL]
  final cross-wave code review (review-code) -> fix loop -> complete
```

## Detailed Steps

### Step 1: Create the team worklog
Delegate to the team-worklog creator (fresh context):
```
task(category="unspecified-high", load_skills=["create-team-worklog"], prompt="Create a team worklog for the plan at [plan dir]/plan.md. Slice the task graph into waves using Depends on + Touched files. Include exact verification commands and backlog/requirement policy.")
```
Commit before the team phase: `git add [plan dir]/team-worklog.md [plan dir]/state.json && git commit -m "worklog: initialize team execution log for [slug]"`.

### Step 2: Spawn the team (once)
Declare a team with up to 4 implementation workers plus one reviewer. Members cannot load skills, so their prompts must point them at the canonical skill files.

```
team_create({ inline_spec: {
  name: "exec-<slug>",
  lead: { kind: "subagent_type", subagent_type: "sisyphus" },
  members: [
    { name: "impl-1", kind: "category", category: "deep",
      prompt: "Backend/logic worker. FIRST read the execute-task skill at ~/.config/opencode/skills/execute-task/SKILL.md and follow it EXACTLY, EXCEPT skip the break-it step (this fast mode drops it). Read [plan dir]/team-worklog.md and plan.md. Claim ONE unblocked team task (lowest id). Announce your Touched files to the team before editing. Implement Red->Green->Verify in the shared working tree, run only your scoped fast tests, update your task's entry in the team worklog, set the task completed, and message the reviewer + lead. Do NOT run git. Then re-check the board." },
    { name: "impl-2", kind: "category", category: "deep", prompt: "…same as impl-1…" },
    { name: "impl-3", kind: "category", category: "deep", prompt: "…same as impl-1…" },
    { name: "ui-1", kind: "category", category: "visual-engineering", prompt: "Frontend/UI worker. Same discipline as impl-1, UI tasks only." },
    { name: "reviewer", kind: "category", category: "ultrabrain",
      prompt: "Reviewer. FIRST read the review-code skill at ~/.config/opencode/skills/review-code/SKILL.md. Review each task's diff live as workers report done, and the combined wave diff at wave end. Apply the test-adequacy gate strictly (this mode dropped break-it). Report findings by severity to the lead. Do NOT modify code or run git." }
  ]
} })
```
Cap real concurrency at 4 workers. Route UI tasks to the `visual-engineering` member. Keep plan review and final code review OUTSIDE the team (lead-driven).

### Step 3: Run each wave
For the current wave from the team worklog:
1. Create one `team_task` per wave task with `blockedBy` reflecting plan dependencies already satisfied by prior waves.
2. Let workers claim unblocked tasks (lowest id first). Ensure declared `Touched files` are disjoint; if a worker discovers an unavoidable overlap, have the two workers coordinate live via `team_send_message`, or reslot the loser to a later wave.
3. As each worker reports done, the reviewer reviews that task's diff live; the worker fixes on the spot.
4. When all wave tasks are done and live-reviewed, the reviewer runs the end-of-wave review on the combined wave diff.
5. Resolve open Blocker/Critical/Major findings (assign fixes; cap 2 fix rounds per wave).
6. Run the wave gate once (lead): the package/repo-wide task gate command from the worklog.
7. Commit the wave (lead, sole committer): `git add -A && git commit -m "wave(N): <summary>"` including code, tests, and the team-worklog update.
8. Update the team worklog Execution Log and advance `Current Wave`.

### Step 4: Rebalancing (optional)
If a wave is uneven (one long task, several short), pull a dependency-satisfied, file-disjoint task from a later wave forward, or shut down idle members to save budget.

### Step 5: Close the team
When all waves are terminal, run the Closure Sequence in the same turn: for each active member `team_shutdown_request` then `team_approve_shutdown`; then `team_delete`. Never leave a team idle.

### Step 6: Final cross-wave review
After the team is closed, run a sequential full-branch review (fresh context) to catch cross-wave integration issues:
```
task(category="ultrabrain", load_skills=["review-code"], prompt="Review the full implementation against [plan dir]/plan.md. Review the complete branch diff. Separate required fixes from non-blocking backlog items.")
```
Fix-and-re-review loop (cap 5). Then mark complete and update state.json.

## Convergence Caps

| Loop | Max | On exhaustion |
|------|-----|---------------|
| Per-wave fix | 2 per wave | escalate the wave's findings to the human |
| Final code review | 5 | pause, report unresolved issues |
| Stuck team (all remaining tasks blocked / no progress) | timeout | pause, report to human |

## What You MUST NOT Do

- Do not use this mode for maximum-rigor work — use the sequential `execution-orchestrator`.
- Do not let any member run git — you are the sole committer.
- Do not place two file-overlapping or dependency-linked tasks in the same wave.
- Do not skip the wave gate or the final cross-wave review.
- Do not leave the team open after all waves are terminal (run the Closure Sequence).
- Do not let members write `state.json` or backlog/requirement docs concurrently — route those through the lead.
- Do not reintroduce a single-task `NEXT STEP` cursor; the team task list is the live cursor.
- Do not push (commits are local only).
