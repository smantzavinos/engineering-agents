# Process retrospective: the legacy process and the frontier pilot

**Status:** draft for owner review. Nothing in §7 stages 1–5 runs until the owner approves this plan.
**Date:** 2026-10-15
**Inputs:** [frontier pipeline plan](../2026_10_10_frontier_pipeline/plan.md) and [evaluation](../2026_10_10_frontier_pipeline/evaluation.md); [fast verification plan](../2026_10_13_fast_verification/plan.md) §1–§17.
**Pilot-specific sources:** listed in `retro/sources.md` inside the pilot repo's epic plan directory. This file stays generic.

## 1. Objective

Find out where the time went across every execution approach we ran, what caused the biggest delays, and which steps cost time without adding value. Use the findings to choose the next process changes, ranked by hours saved per child and per epic, with evidence for each.

This is a measurement exercise first. We document the process, the questions and the definitions before collecting data, so the data answers the questions instead of the other way round.

## 2. Questions

| ID | Question |
|---|---|
| Q1 | Where does elapsed time go, per child and per epic, by phase (§4)? What share is on the critical path? |
| Q2 | What are the biggest bottlenecks: the phases or waits that most often set the critical path? |
| Q3 | Which steps add time but not value? A step adds value when its output changed the delivered work or prevented later rework (§5.4). |
| Q4 | Which time wasters recur (same cause, several children or eras)? |
| Q5 | Where does the process break down: failed runs, stops, restarts, lost notifications, flakes, infrastructure, rule conflicts? What did each cost? |
| Q6 | Where did parallel lanes, groups and merges save time, and where did they cost more than they saved (§5.6)? |
| Q7 | Where were subagents used well, where did they waste tokens or time, and where should one have been used but wasn't (§5.5)? |
| Q8 | How did each process change (era boundary or mid-era rule) move the measures? Which changes paid off? |
| Q9 | How accurate were estimates (lines, hours), and did sizing rules (splits, merges, size limit) help or hurt? |
| Q10 | What did reviews find, at which stage, and would a later stage have caught it? What did each review loop cost? |
| Q11 | How much orchestration overhead is there (orchestrator turns, compactions, decision records, bookkeeping), and what drives it? |
| Q12 | How much time went to changing the process itself mid-run (skill changes, restarts, prep work), and was it recovered? |
| Q13 | How do agent-hours, tokens and elapsed time relate? Where is effort high but elapsed time low, or the reverse? |
| Q14 | Other learnings: anything the data shows that the questions above don't cover. |

## 3. What we compare: process eras

| Era | Period | Work | Process |
|---|---|---|---|
| **A. Legacy** | 10-09 → 10-11 | Reference epic, children 01–03 complete, 04 stopped in planning | Brief → approach → approach review → plan → plan review → worklog → one `execute-task` per plan task → code review. Full-suite gates per task. |
| **B. Frontier v1** | 10-12 14:46 → 10-13 ~14:40 | Pilot children 01–04 (04 split into 04a/04b) | Frontier pipeline (plan §3–§9): epic `scope`, per-child plan loop and implement loop with fresh reviewers, oracle for disputes, helpers for errands. Orchestrator did a large share of building through helpers. Old gates. |
| **Switch** | 10-13 ~14:40 → ~21:00 | Fast-verification prep in a separate worktree | Tiered verification, checkpoints, test-budget rules, lane pools (fast verification §3–§13). |
| **C. Fast verification** | 10-13 ~21:00 → 10-14 15:08 | Children 05–09 (with a/b slices, groups G1–G3) | Era B plus fast verification, Sonnet implementer, test contracts, plan-ahead with refresh (§14–§15), parallel lanes in a worktree pool. |
| **D. Group integration and size rule** | 10-14 15:10 → 10-15 07:37 | Children 10a–12c, epic close | Era C plus §16 (group integration, refresh review level, review-level rules, compaction at clean points) and the owner size limit (§17). Implementer thinking lowered mid-era by owner decision. |
| **E. Proposed** | — | — | Plan and build in one session (projection only; not measured). |

The exact boundaries and the mid-era rule changes (decision records with timestamps) are part of the data collection (§7, stage 2).

## 4. Phase model

Every minute of an era is assigned to one phase per child, plus the epic-level rows. A run can serve one phase only; waits are explicit.

**Per child**

| Phase | Starts | Ends | Eras |
|---|---|---|---|
| Brief / approach (+ review) | first brief commit or run | approach approved | A |
| Plan | plan-author (or planner) launched | plan submitted for review | A–D |
| Plan review loop | first plan review | plan approved (revisions and oracle consults inside) | A–D |
| Plan-ahead wait | plan approved | the child's lane can start (dependencies integrated) | C–D |
| Refresh (+ refresh review) | refresh launched | refreshed plan approved | C–D |
| Lane setup | dependencies ready | implementer launched (pool, branch, env) | C–D |
| Build | implementer launched | build reported done (build assists by helpers included) | A–D |
| Code review loop | first code review | approved (fix runs inside) | A–D |
| Integration | merge into the work branch | integration green (T1, integration fixes and reviews inside) | B–D |
| Close | integration green | state recorded | A–D |

**Epic level**

| Row | What |
|---|---|
| Scope / epic authoring | epic or plan-set authoring and its reviews |
| Checkpoints | full gates at checkpoints, triage and fixes |
| Epic close | whole-epic review, final gates |
| Orchestration | orchestrator turns not attributable to one child, compactions, restarts, decision records |
| Owner time | stops waiting for the owner, owner-requested fixes, owner reviews |
| Process change | prep work, skill changes, redeploys and restarts done to change the process mid-run |
| Incidents | flakes, infrastructure failures (ports, disk, stalls), lost notifications, failed runs and their recovery |
| Idle | no run active and no stop recorded (unexplained gaps) |

**Waits.** For each child we record when it *could* have started each phase (its inputs were ready) and when it *did*. The difference is a wait, attributed to a cause: dependency, lane or pool full, orchestrator busy or compacting, owner, incident, ordering mistake.

## 5. Measures and definitions

### 5.1 Time
- **Elapsed** per phase per child, from the start and end events above.
- **Critical path** per era: the chain of phases and waits that set the epic's end. A phase is on the critical path if shortening it would have moved the end.
- **Agent-hours** per phase: the sum of run durations, overlapping runs counted separately.
- **Parallelism:** concurrent active runs over time; epic elapsed ÷ sum of child elapsed.

### 5.2 Effort
- Tokens (input, output, cache), turns and tool calls per run, from run records and session logs.
- Compactions per session and their trigger (size or clean point).
- Model and thinking level per run.

### 5.3 Size and estimates
- Changed lines per child excluding generated files, split into production, tests and docs.
- Estimate (lines, hours) at plan, refresh and any re-size, against actuals.

### 5.4 Review findings and value
For every finding in plan, refresh, code, integration and epic reviews, record:
- stage, pass, severity (blocker, major, minor) and kind: behaviour bug, security or data integrity, design or performance, test-plan mechanics, claims/docs/scope, sizing/timing, process;
- **later catch:** would a later stage most likely have caught it (yes, probably, no), and the estimated rework cost if caught later;
- **cost:** the fix and re-review time it caused.

A review step **adds value** when at least one finding would not have been caught later, or would have cost more later than the review loop cost. It **adds time without value** when all its findings would have been caught later at equal or lower cost, or it found nothing and was not a required safety gate.

### 5.5 Subagent effectiveness
Classify each subagent run:
- **Effective:** its output was used and it saved orchestrator or critical-path time, or found something that mattered.
- **Redundant:** repeated work already done, or its output was not used.
- **Wasted:** failed, was stopped, or was superseded before its output mattered.
- **Overkill:** a heavier model or longer run than the task needed.

And record **missed delegation**: work the orchestrator or an implementer did itself that a helper could have done faster or cheaper (long reads, gate runs, log digests), or work done serially that could have run in parallel.

### 5.6 Parallel lanes and groups
For each group or parallel pair: elapsed with parallelism, the estimated serial alternative (sum of member critical paths), and the extra cost of parallelism (claims and coordination, group integration, conflicts, red T1 after merge, serialized resources such as E2E ports). Net saving = serial estimate − actual.

### 5.7 Breakdowns
Every failed or stopped run, restart, flake, infrastructure incident, rule conflict and owner stop: time lost (to the critical path and in agent-hours), cause, and whether the process now prevents it.

## 6. Data sources

| Source | Gives |
|---|---|
| Orchestrator and child session logs | turns, tool calls, timestamps, compactions, decisions as they happened |
| Subagent run records (`status.json`, snapshotted) | run start/end, agent, model, tokens, status, worktree, parent session |
| Work traces (from `tools/pi-work-trace.mjs`) | one normalized timeline per era |
| Git first-parent logs and merges | plan approvals, lane merges, integrations, timestamps |
| Epic plan directory: `epic.md`, `state.json`, per-child `plan.md` and `review.md` | decisions, estimates, review findings, stops, checkpoints, groups |
| Legacy epic directory | briefs, approaches, plans, worklogs, reviews, state |
| Supervising session (owner and assistant) | process changes, owner messages, analyses made during the run |
| Engineering-agents plans and review ledgers | the rule set in force for each era |

## 7. Method

### Stage 0: document and freeze (now)
1. This plan, `retro/sources.md` with the exact paths, and the run-record snapshot. ✅ snapshot taken 10-15.
2. Owner review of the questions, eras, phase model and definitions. Changes go here before stage 1.

### Stage 1: base dataset (deterministic, done by the coordinating session)
Scripts, not agents, produce:
- `runs.csv`: one row per run (era, child, phase, agent, model, thinking, start, end, status, tokens, turns, tools, worktree, parent, revived).
- `git_events.csv`: plan approvals, lane merges, integrations, re-merges, resets, per child.
- `compactions.csv`, `decisions.csv` (decision ID, timestamp from git, child, kind).
- `children.csv` skeleton: dependencies, group, era, changed lines by category, estimates.
- Condensed orchestrator transcripts per era: user, assistant text and tool names with timestamps, tool output dropped. This keeps stage 2 readers inside a fast model's context.
- Work traces per era, for viewing.

### Stage 2: dossiers (delegated, read-only, parallel)
Helper agents each read a bounded slice and fill a fixed schema (§8). Lanes:

| Lane | Count | Reads | Produces |
|---|---|---|---|
| Child dossier | ~10 runs, 3 children each (30 children: 4 legacy, 26 pilot) | the child's plan, review ledger, epic entry and decisions, its rows of the base dataset, its git events | `dossiers/child-<key>.json` + `.md` |
| Era orchestration | 4 (A, B, C, D) | condensed orchestrator transcript, era decisions, stops | `dossiers/era-<x>.json` + `.md`: waits, ordering choices, overhead, breakdowns, missed delegation |
| Incidents | 1 | flakes, failed runs, restarts, infrastructure notes | `dossiers/incidents.json` |
| Process changes | 1 | supervising session, engineering-agents plans and ledgers | `dossiers/process-changes.json`: each change, when, why, cost, expected effect |

Rules for every lane:
- Read-only. No git commands that change state, no builds or tests, no edits outside the assigned output file.
- Every timing and claim cites its source (file and line, commit, run ID).
- Unknown stays unknown; no guessing.
- Model: a mid-tier model with judgment for dossiers (finding classification needs it); the fastest model only for purely mechanical extraction. Exact agents and models are an owner decision (§9).

### Stage 3: compile and check (coordinating session)
- Merge dossiers into the base dataset; recompute the measures in §5 with scripts.
- Cross-check: every dossier phase time against `runs.csv` and `git_events.csv`; flag differences over 10 minutes.
- Spot-check 10% of findings classifications and subagent classifications by reading the source.
- Produce tables and the evolution traces (anonymized, one per era plus the era E projection).

### Stage 4: synthesis (oracle, fresh context)
The oracle gets this plan, the definitions, the compiled dataset and the dossier summaries, not the raw logs. It answers Q1–Q14 with findings ranked by hours saved, each citing data rows. A fresh reviewer then checks the top findings against the dataset and dossiers and records disagreements.

### Stage 5: report and discussion
`retro.md` here (generic: findings, measures, traces, strategy options) and the pilot-specific evidence in the pilot repo's `retro/` directory. Then an owner discussion to choose process changes, written up as a separate plan.

## 8. Child dossier schema

```json
{
  "child": "10b", "era": "D", "group": null, "dependsOn": ["10a"],
  "size": {"estimate": {"lines": "3.2-3.9k", "hours": 3.3}, "actual": {"prod": 0, "tests": 0, "docs": 0}},
  "phases": [{"phase": "build", "start": "ISO", "end": "ISO", "runs": ["runId"], "onCriticalPath": true, "source": "..."}],
  "waits": [{"before": "build", "readyAt": "ISO", "startedAt": "ISO", "cause": "dependency|pool|orchestrator|owner|incident|ordering", "source": "..."}],
  "reviews": [{"stage": "plan|refresh|code|integration|epic", "pass": 1, "durationMin": 0, "verdict": "...",
    "findings": [{"id": "F1", "severity": "major", "kind": "...", "laterCatch": "yes|probably|no", "laterCostMin": 0, "fixCostMin": 0, "source": "..."}]}],
  "subagents": [{"runId": "...", "role": "...", "class": "effective|redundant|wasted|overkill", "why": "...", "source": "..."}],
  "missedDelegation": [{"what": "...", "estMin": 0, "source": "..."}],
  "incidents": [{"what": "...", "lostMin": 0, "criticalPath": true, "source": "..."}],
  "notes": "anything else that bears on Q1–Q14"
}
```

Era, incident and process-change dossiers use the same conventions (ISO times, sources on every row) with their own fields, fixed before stage 2 starts.

## 9. Owner decisions before stage 1

1. **Questions, eras, phase model, definitions:** approve or change §2–§5.
2. **Dossier agent and model:** proposed `worker` (Sonnet, medium) for child and era dossiers; `helper` (Haiku) only for mechanical extraction if a lane needs it.
3. **Synthesis:** proposed `oracle` for stage 4 and a fresh `reviewer` to check its top findings.
4. **Concurrency:** proposed at most 6 dossier runs at once.
5. **Where pilot-specific material lives:** proposed in the pilot repo's `retro/` directory (local branch, not pushed); only generic findings and anonymized traces here.

## 10. Constraints

- Read-only on every pilot and legacy worktree; no runs there while this work happens.
- Nothing pushed without the owner's OK.
- Generic text only in this repository.

## 11. Risks and limits

- **Phase attribution:** phase labels come from task wording; revived runs that continued a build may be labelled as fixes. Stage 3 cross-checks against git events and ledgers.
- **Missing data:** the switch prep ran in another session; the legacy era used different artifacts. Gaps are recorded, not filled by guessing.
- **Counterfactuals:** "later catch" and "serial alternative" are estimates. They are labelled as estimates, with their reasoning.
- **Small sample:** era A has 3 completed children and era D about 8. Findings that rest on one child are marked as anecdotes.
- **Context load:** orchestrator logs are 8–10 MB. Stage 1 condenses them before any agent reads them.
